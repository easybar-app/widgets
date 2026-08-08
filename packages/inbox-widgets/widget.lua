-- EasyBar package updates in the native inbox.

local inbox = require("inbox")
local retry = require("retry")

local SOURCE = "Widgets"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "Widgets",
	icon = easybar.asset("assets/easybar.svg"),
	color = "#6C8EEF",
}
local REGISTRY_URL = "https://raw.githubusercontent.com/easybar-app/widget-registry/main/index.json"
local STORAGE_WIDGET = "inbox-widgets"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
local DEFAULT_REFRESH_INTERVAL_MINUTES = 360
local MINIMUM_REFRESH_INTERVAL_MINUTES = 5
local MAXIMUM_REFRESH_INTERVAL_MINUTES = 10080
local configured_refresh_interval =
	easybar.storage.get(STORAGE_WIDGET, STORAGE_REFRESH_INTERVAL_KEY, DEFAULT_REFRESH_INTERVAL_MINUTES)
local refresh_interval_minutes = tonumber(configured_refresh_interval)
if
	refresh_interval_minutes == nil
	or refresh_interval_minutes ~= math.floor(refresh_interval_minutes)
	or refresh_interval_minutes < MINIMUM_REFRESH_INTERVAL_MINUTES
	or refresh_interval_minutes > MAXIMUM_REFRESH_INTERVAL_MINUTES
then
	refresh_interval_minutes = DEFAULT_REFRESH_INTERVAL_MINUTES
end
local POLL_INTERVAL_SECONDS = refresh_interval_minutes * 60
local NETWORK_READY_DELAY_SECONDS = 3
local MIN_ACTIVITY_COMPLETION_DELAY_SECONDS = 0.2
local REFRESH_BACKOFF_SECONDS = { 2, 5 }

local EXEC = {
	read = { timeout_seconds = 10, max_output_bytes = 5 * 1024 * 1024, log_operation = "read_installed" },
	registry = { timeout_seconds = 30, max_output_bytes = 5 * 1024 * 1024, log_operation = "fetch_registry" },
	update = { timeout_seconds = 5 * 60, max_output_bytes = 2 * 1024 * 1024, log_operation = "update_package" },
}

local state = {
	updates = {},
	error = nil,
	operation = nil,
}
local pending_refresh = nil
local refresh
local log = easybar.log

if refresh_interval_minutes ~= configured_refresh_interval then
	log(
		easybar.level.warn,
		"invalid widgets.inbox-widgets.refresh_interval_minutes; using " .. tostring(DEFAULT_REFRESH_INTERVAL_MINUTES)
	)
end

local function installed_database_path()
	local active_directory = os.getenv("EASYBAR_INTERNAL_WIDGET_PACKAGES_DIRECTORY")
	if type(active_directory) == "string" and active_directory ~= "" then
		local packages_directory = active_directory:gsub("/+$", ""):match("^(.*)/[^/]+$")
		if packages_directory ~= nil then
			return packages_directory .. "/installed.json"
		end
	end

	local home = os.getenv("HOME")
	if type(home) ~= "string" or home == "" then
		return nil
	end
	return home .. "/.local/share/easybar/packages/installed.json"
end

local function decode_object(output, label)
	local ok, value = pcall(easybar.json.decode, tostring(output or ""))
	if not ok or type(value) ~= "table" or easybar.json.is_array(value) then
		return nil, label .. " did not contain a JSON object"
	end
	return value, nil
end

local function parse_version(value)
	if type(value) ~= "string" then
		return nil
	end
	local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
	local prerelease = nil
	if major == nil then
		major, minor, patch, prerelease = value:match("^(%d+)%.(%d+)%.(%d+)%-([0-9A-Za-z][0-9A-Za-z.-]*)$")
	end
	if major == nil then
		return nil
	end
	return {
		major = tonumber(major),
		minor = tonumber(minor),
		patch = tonumber(patch),
		prerelease = prerelease ~= "" and prerelease or nil,
	}
end

local function compare_prerelease(left, right)
	if left == right then
		return 0
	elseif left == nil then
		return 1
	elseif right == nil then
		return -1
	end

	local left_parts = {}
	for part in left:gmatch("[^.]+") do
		left_parts[#left_parts + 1] = part
	end
	local right_parts = {}
	for part in right:gmatch("[^.]+") do
		right_parts[#right_parts + 1] = part
	end

	for index = 1, math.max(#left_parts, #right_parts) do
		local left_part = left_parts[index]
		local right_part = right_parts[index]
		if left_part == nil then
			return -1
		elseif right_part == nil then
			return 1
		elseif left_part ~= right_part then
			local left_number = left_part:match("^%d+$") and tonumber(left_part) or nil
			local right_number = right_part:match("^%d+$") and tonumber(right_part) or nil
			if left_number ~= nil and right_number ~= nil then
				return left_number < right_number and -1 or 1
			elseif left_number ~= nil then
				return -1
			elseif right_number ~= nil then
				return 1
			end
			return left_part < right_part and -1 or 1
		end
	end
	return 0
end

local function compare_versions(left_value, right_value)
	local left = parse_version(left_value)
	local right = parse_version(right_value)
	if left == nil or right == nil then
		return nil
	end
	for _, key in ipairs({ "major", "minor", "patch" }) do
		if left[key] ~= right[key] then
			return left[key] < right[key] and -1 or 1
		end
	end
	return compare_prerelease(left.prerelease, right.prerelease)
end

local function release_sources(package)
	local sources = {}
	if not easybar.json.is_array(package.versions) then
		return sources
	end
	for _, release in ipairs(package.versions) do
		if type(release) == "table" and type(release.archive) == "string" then
			sources[release.archive] = true
		end
	end
	return sources
end

local function find_updates(installed_output, registry_output)
	local installed, installed_error = decode_object(installed_output, "The installed package database")
	if installed == nil then
		return nil, installed_error
	end
	if not easybar.json.is_array(installed.packages) then
		return nil, "The installed package database has no packages array"
	end

	local registry, registry_error = decode_object(registry_output, "The widget registry")
	if registry == nil then
		return nil, registry_error
	end
	if registry.registry_version ~= 1 or not easybar.json.is_array(registry.packages) then
		return nil, "The widget registry has an unsupported format"
	end

	local registry_by_name = {}
	for _, package in ipairs(registry.packages) do
		if type(package) == "table" and type(package.name) == "string" then
			registry_by_name[package.name] = package
		end
	end

	local updates = {}
	for _, package in ipairs(installed.packages) do
		if
			type(package) == "table"
			and type(package.name) == "string"
			and type(package.version) == "string"
			and type(package.source) == "string"
		then
			local available = registry_by_name[package.name]
			if available ~= nil and type(available.latest) == "string" then
				local known_sources = release_sources(available)
				local comparison = compare_versions(package.version, available.latest)
				if known_sources[package.source] and comparison ~= nil and comparison < 0 then
					updates[#updates + 1] = {
						id = "package:" .. package.name,
						name = package.name,
						kind = package.kind == "library" and "library" or "widget",
						installed = package.version,
						latest = available.latest,
					}
				end
			end
		end
	end
	table.sort(updates, function(left, right)
		return left.name < right.name
	end)
	return updates, nil
end

local function package_for_id(id)
	for _, package in ipairs(state.updates) do
		if package.id == id then
			return package
		end
	end
	return nil
end

local function configure_source_actions()
	local operation = state.operation
	if operation ~= nil then
		easybar.inbox.configure(SOURCE, {
			actions = {
				{
					id = "activity",
					title = operation.title,
					enabled = false,
					busy = operation.item_id == nil,
					include_in_refresh_all = operation.kind == "refresh" or nil,
				},
			},
		})
	else
		easybar.inbox.configure(SOURCE, {
			actions = { { id = "refresh", title = "Refresh", include_in_refresh_all = true } },
		})
	end
end

local function publish()
	local items = {}
	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = state.error.title,
			body = state.error.message,
			severity = "error",
			unread = true,
			timestamp = state.error.timestamp,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end

	for _, package in ipairs(state.updates) do
		local action
		if state.operation ~= nil and state.operation.item_id == package.id then
			action = { id = "update", title = state.operation.title, enabled = false, busy = true }
		elseif state.operation == nil then
			action = { id = "update", title = "Update" }
		end
		items[#items + 1] = {
			id = package.id,
			title = package.name,
			body = package.installed .. " → " .. package.latest,
			category = package.kind == "library" and "Libraries" or "Widgets",
			severity = "info",
			unread = true,
			source = SOURCE_PRESENTATION,
			actions = action ~= nil and { action } or {},
		}
	end

	configure_source_actions()
	easybar.inbox.replace(SOURCE, items)
end

local function finish_operation(operation, callback)
	if state.operation ~= operation then
		return
	end
	easybar.after(MIN_ACTIVITY_COMPLETION_DELAY_SECONDS, function()
		if state.operation == operation then
			state.operation = nil
			callback()
		end
	end)
end

local function fail_operation(operation, title, output, fallback)
	finish_operation(operation, function()
		state.error = {
			title = title,
			message = inbox.error_message(output, fallback),
			timestamp = os.time(),
		}
		publish()
	end)
end

refresh = function(reason, activity_item_id)
	if state.operation ~= nil then
		return
	end
	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	local database_path = installed_database_path()
	if database_path == nil then
		state.error = {
			title = "Could not check package updates",
			message = "Could not resolve EasyBar's package directory",
			timestamp = os.time(),
		}
		publish()
		return
	end

	local operation = {
		kind = "refresh",
		title = "Checking package updates…",
		item_id = activity_item_id,
	}
	state.operation = operation
	publish()
	log(easybar.level.debug, "package update refresh started reason=" .. tostring(reason or "unspecified"))

	easybar.spawn_async({ "/bin/cat", database_path }, EXEC.read, function(installed_output, installed_code)
		if state.operation ~= operation then
			return
		end
		if installed_code ~= 0 then
			fail_operation(operation, "Could not check package updates", installed_output, "Could not read " .. database_path)
			return
		end

		operation.handle = retry.run(easybar, {
			delays = REFRESH_BACKOFF_SECONDS,
			attempt = function(done)
				return easybar.spawn_async({
					"/usr/bin/curl",
					"--fail",
					"--silent",
					"--show-error",
					"--location",
					REGISTRY_URL,
				}, EXEC.registry, done)
			end,
			should_retry = retry.is_transient_network_error,
			on_complete = function(registry_output, registry_code)
				if registry_code ~= 0 then
					fail_operation(
						operation,
						"Could not fetch the widget registry",
						registry_output,
						"curl exited with code " .. tostring(registry_code)
					)
					return
				end

				local updates, parse_error = find_updates(installed_output, registry_output)
				if updates == nil then
					fail_operation(operation, "Could not check package updates", parse_error, parse_error)
					return
				end
				finish_operation(operation, function()
					state.updates = updates
					state.error = nil
					log(easybar.level.debug, "package update refresh completed updates=" .. tostring(#updates))
					publish()
				end)
			end,
		})
	end)
end

local function update_package(package)
	if state.operation ~= nil then
		return
	end
	local operation = {
		kind = "update",
		title = "Updating " .. package.name .. "…",
		item_id = package.id,
	}
	state.operation = operation
	state.error = nil
	publish()

	easybar.spawn_async(
		{ "/usr/bin/env", "easybar", "widgets", "install", package.name },
		EXEC.update,
		function(output, code)
			if code ~= 0 then
				fail_operation(
					operation,
					"Could not update " .. package.name,
					output,
					"easybar widgets install exited with code " .. tostring(code)
				)
				return
			end
			finish_operation(operation, function()
				refresh("post_update", package.id)
			end)
		end
	)
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "")
	if action_id == "refresh" then
		refresh("item")
	elseif action_id == "update" then
		local package = package_for_id(tostring(event.target_widget_id or ""))
		if package ~= nil then
			update_package(package)
		end
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	if tostring(event.action_id or "") == "refresh" then
		refresh("manual")
	end
end)

local function schedule_refresh(reason, delay_seconds)
	if pending_refresh ~= nil then
		pending_refresh:cancel()
	end
	pending_refresh = easybar.after(delay_seconds, function()
		pending_refresh = nil
		refresh(reason)
	end)
end

local timer = easybar.add(easybar.kind.item, "easybar_package_updates_timer", {
	drawing = false,
	interval = POLL_INTERVAL_SECONDS,
	on_interval = function()
		refresh("interval")
	end,
})

timer:subscribe(easybar.events.forced, function()
	refresh("forced")
end)

timer:subscribe(easybar.events.system_woke, function()
	schedule_refresh("wake", NETWORK_READY_DELAY_SECONDS)
end)

timer:subscribe(easybar.events.session_active, function()
	schedule_refresh("session_active", NETWORK_READY_DELAY_SECONDS)
end)

schedule_refresh("startup", NETWORK_READY_DELAY_SECONDS)
