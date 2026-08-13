--- Publishes mason.nvim tool updates to EasyBar's native inbox.

local inbox = require("inbox")
local text = require("text")

local SOURCE = "mason.nvim"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "mason.nvim",
	icon = easybar.asset("assets/mason.svg"),
	color = "#5FAF8F",
}

local STORAGE_WIDGET = "nvim-mason-inbox"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
local STORAGE_SOURCE_ORDER_KEY = "source_order"
local STORAGE_CONTEXT_ORDER_KEY = "context_order"
local DEFAULT_REFRESH_INTERVAL_MINUTES = 60
local DEFAULT_SOURCE_ORDER = 36
local DEFAULT_CONTEXT_ORDER = 36
local MINIMUM_REFRESH_INTERVAL_MINUTES = 5
local MAXIMUM_REFRESH_INTERVAL_MINUTES = 10080
local NETWORK_READY_DELAY_SECONDS = 3
local MIN_ACTIVITY_COMPLETION_DELAY_SECONDS = 0.2
local MAX_ITEMS = 500

local EXEC = {
	check = { timeout_seconds = 5 * 60, max_output_bytes = 4 * 1024 * 1024, log_operation = "refresh" },
	update = { timeout_seconds = 30 * 60, max_output_bytes = 8 * 1024 * 1024, log_operation = "update" },
}

local CHECK_SCRIPT = table.concat({
	"local ok, err = pcall(function()",
	"local registry = require('mason-registry')",
	"local a = require('mason-core.async')",
	"a.run_blocking(function()",
	"local success, result = a.wait(registry.update)",
	"if not success then error(tostring(result)) end",
	"end)",
	"local updates = {}",
	"for _, pkg in ipairs(registry.get_installed_packages()) do",
	"local current = pkg:get_installed_version()",
	"local latest = pkg:get_latest_version()",
	"if current and latest and current ~= latest and pkg:is_installable({ version = latest }) then",
	"updates[#updates + 1] = { name = pkg.name, installed = current, latest = latest, homepage = pkg.spec.homepage, categories = pkg.spec.categories }",
	"end",
	"end",
	"table.sort(updates, function(a1, b1) return a1.name < b1.name end)",
	"vim.api.nvim_out_write('EASYBAR_NVIM_MASON_UPDATES=' .. vim.json.encode(updates) .. '\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_NVIM_MASON_ERROR=' .. message)",
	"vim.cmd('cquit 1')",
	"end",
}, " ")

local UPDATE_SCRIPT = table.concat({
	"local ok, err = pcall(function()",
	"local registry = require('mason-registry')",
	"local a = require('mason-core.async')",
	"a.run_blocking(function()",
	"local success, result = a.wait(registry.refresh)",
	"if not success then error(tostring(result)) end",
	"end)",
	"local target = vim.env.EASYBAR_NVIM_MASON_PACKAGE or ''",
	"local packages = {}",
	"for _, pkg in ipairs(registry.get_installed_packages()) do",
	"local current = pkg:get_installed_version()",
	"local latest = pkg:get_latest_version()",
	"if (target == '' or pkg.name == target) and current and latest and current ~= latest and pkg:is_installable({ version = latest }) then packages[#packages + 1] = pkg end",
	"end",
	"local pending = #packages",
	"local errors = {}",
	"for _, pkg in ipairs(packages) do",
	"local name = pkg.name",
	"pkg:install({}, function(success, result)",
	"if not success then errors[#errors + 1] = name .. ': ' .. tostring(result) end",
	"pending = pending - 1",
	"end)",
	"end",
	"if pending > 0 and not vim.wait(29 * 60 * 1000, function() return pending == 0 end, 100) then error('Mason update timed out') end",
	"if #errors > 0 then error(table.concat(errors, '; ')) end",
	"vim.api.nvim_out_write('EASYBAR_NVIM_MASON_UPDATED=' .. #packages .. '\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_NVIM_MASON_ERROR=' .. message)",
	"vim.cmd('cquit 1')",
	"end",
}, " ")

local NVIM = text.trim(os.getenv("NVIM") or "")
if NVIM == "" then
	NVIM = "nvim"
end

local configured_refresh_interval =
	easybar.storage.get(STORAGE_WIDGET, STORAGE_REFRESH_INTERVAL_KEY, DEFAULT_REFRESH_INTERVAL_MINUTES)
local refresh_interval_minutes = tonumber(configured_refresh_interval)
if
	refresh_interval_minutes == nil
	or refresh_interval_minutes ~= math.floor(refresh_interval_minutes)
	or refresh_interval_minutes < MINIMUM_REFRESH_INTERVAL_MINUTES
	or refresh_interval_minutes > MAXIMUM_REFRESH_INTERVAL_MINUTES
then
	easybar.log(
		easybar.level.warn,
		"invalid widgets.nvim-mason-inbox.refresh_interval_minutes; using " .. tostring(DEFAULT_REFRESH_INTERVAL_MINUTES)
	)
	refresh_interval_minutes = DEFAULT_REFRESH_INTERVAL_MINUTES
end

--- Reads and validates an Inbox order setting.
local function configured_order(key, default)
	local configured = easybar.storage.get(STORAGE_WIDGET, key, default)
	local value = tonumber(configured)
	if value == nil or value ~= math.floor(value) or value < -10000 or value > 10000 then
		easybar.log(easybar.level.warn, "invalid widgets.nvim-mason-inbox." .. key .. "; using " .. tostring(default))
		return default
	end
	return value
end

local source_order = configured_order(STORAGE_SOURCE_ORDER_KEY, DEFAULT_SOURCE_ORDER)
local context_order = configured_order(STORAGE_CONTEXT_ORDER_KEY, DEFAULT_CONTEXT_ORDER)
SOURCE_PRESENTATION.order = source_order
local POLL_INTERVAL_SECONDS = refresh_interval_minutes * 60
local state = { updates = {}, error = nil, operation = nil }
local pending_refresh = nil
local refresh

--- Returns the first category supplied by Mason.
local function package_category(categories)
	if type(categories) == "table" and type(categories[1]) == "string" and text.trim(categories[1]) ~= "" then
		return text.trim(categories[1])
	end
	return "Tools"
end

--- Accepts HTTP(S) package homepages for native Open behavior.
local function homepage_url(value)
	value = type(value) == "string" and text.trim(value) or ""
	return value:match("^https?://") and value or nil
end

--- Decodes and validates the Mason update payload.
local function decode_updates(output)
	local payload = tostring(output or ""):match("EASYBAR_NVIM_MASON_UPDATES=([^\r\n]+)")
	if payload == nil then
		return nil, "Neovim returned no mason.nvim update list"
	end
	local ok, decoded = pcall(easybar.json.decode, payload)
	if not ok or not easybar.json.is_array(decoded) then
		return nil, "Neovim returned an invalid mason.nvim update list"
	end

	local updates = {}
	local seen = {}
	for _, entry in ipairs(decoded) do
		if type(entry) ~= "table" or easybar.json.is_array(entry) then
			return nil, "mason.nvim returned an invalid tool update"
		end
		local name = type(entry.name) == "string" and text.trim(entry.name) or ""
		local installed = type(entry.installed) == "string" and text.trim(entry.installed) or ""
		local latest = type(entry.latest) == "string" and text.trim(entry.latest) or ""
		if name == "" or installed == "" or latest == "" then
			return nil, "mason.nvim returned an incomplete tool update"
		end
		if not seen[name] and #updates < MAX_ITEMS then
			seen[name] = true
			updates[#updates + 1] = {
				id = "package:" .. name,
				name = name,
				installed = installed,
				latest = latest,
				category = package_category(entry.categories),
				url = homepage_url(entry.homepage),
			}
		end
	end
	return updates, nil
end

--- Finds the retained update represented by an Inbox item.
local function update_for_id(item_id)
	for _, update in ipairs(state.updates) do
		if update.id == item_id then
			return update
		end
	end
	return nil
end

--- Publishes source actions for the current operation and snapshot.
local function configure_source_actions()
	local operation = state.operation
	local interval = {
		id = "refresh_interval",
		title = "Refresh every " .. tostring(refresh_interval_minutes) .. " minutes",
		enabled = false,
	}
	local actions
	if operation ~= nil then
		actions = {
			{
				id = "activity",
				title = operation.title,
				enabled = false,
				busy = operation.item_id == nil,
				include_in_refresh_all = operation.kind == "refresh" or nil,
			},
			interval,
		}
	else
		actions = {
			{ id = "refresh", title = "Refresh", include_in_refresh_all = true },
			{
				id = "update_all",
				title = #state.updates > 0 and "Update all (" .. tostring(#state.updates) .. ")" or "No updates",
				enabled = #state.updates > 0,
			},
			interval,
		}
	end
	easybar.inbox.configure(SOURCE, { order = context_order, presentation = SOURCE_PRESENTATION, actions = actions })
end

--- Publishes current Mason updates and any retained error.
local function publish()
	local items = {}
	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = "Could not check mason.nvim updates",
			body = state.error.message,
			severity = "error",
			unread = true,
			timestamp = state.error.timestamp,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end
	for _, update in ipairs(state.updates) do
		local action
		if state.operation ~= nil and state.operation.item_id == update.id then
			action = { id = "update", title = state.operation.title, enabled = false, busy = true }
		elseif state.operation == nil then
			action = { id = "update", title = "Update" }
		end
		items[#items + 1] = {
			id = update.id,
			title = update.name,
			body = update.installed .. " → " .. update.latest,
			category = update.category,
			severity = "info",
			unread = true,
			url = update.url,
			source = SOURCE_PRESENTATION,
			actions = action ~= nil and { action } or {},
		}
	end
	configure_source_actions()
	easybar.inbox.replace(SOURCE, items)
end

--- Completes an operation after preserving visible activity briefly.
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

--- Returns the best Mason error embedded in command output.
local function command_error(output, fallback)
	local message = tostring(output or ""):match("EASYBAR_NVIM_MASON_ERROR=([^\r\n]+)")
	return message ~= nil and text.truncate(text.trim(message), 12000, "…") or inbox.error_message(output, fallback)
end

--- Builds a shell-free headless Neovim invocation.
local function nvim_command(script, package_name)
	local command = {}
	if package_name ~= nil then
		command = { "/usr/bin/env", "EASYBAR_NVIM_MASON_PACKAGE=" .. package_name }
	end
	command[#command + 1] = NVIM
	command[#command + 1] = "--headless"
	command[#command + 1] = "-c"
	command[#command + 1] = "lua " .. script
	command[#command + 1] = "-c"
	command[#command + 1] = "qa"
	return command
end

--- Refreshes Mason registry metadata and publishes outdated tools.
refresh = function(reason)
	if state.operation ~= nil then
		return
	end
	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end
	local operation = { kind = "refresh", title = "Checking tool updates…", item_id = nil }
	state.operation = operation
	publish()
	easybar.log(easybar.level.debug, "mason.nvim inbox refresh started reason=" .. tostring(reason or "unspecified"))
	easybar.spawn_async(nvim_command(CHECK_SCRIPT), EXEC.check, function(output, code)
		if state.operation ~= operation then
			return
		end
		finish_operation(operation, function()
			if code ~= 0 then
				state.error = {
					message = command_error(output, "Headless Neovim exited with code " .. tostring(code)),
					timestamp = os.time(),
				}
			else
				local updates, err = decode_updates(output)
				if updates == nil then
					state.error = { message = err, timestamp = os.time() }
				else
					state.updates = updates
					state.error = nil
				end
			end
			publish()
		end)
	end)
end

--- Updates one selected tool or every outdated tool, then reconciles.
local function run_update(update)
	if state.operation ~= nil then
		return
	end
	local package_name = update ~= nil and update.name or ""
	local title = update ~= nil and ("Updating " .. update.name .. "…") or "Updating all tools…"
	local operation = { kind = "update", title = title, item_id = update ~= nil and update.id or nil }
	state.operation = operation
	state.error = nil
	publish()
	easybar.spawn_async(nvim_command(UPDATE_SCRIPT, package_name), EXEC.update, function(output, code)
		if state.operation ~= operation then
			return
		end
		finish_operation(operation, function()
			if code ~= 0 or not tostring(output or ""):find("EASYBAR_NVIM_MASON_UPDATED=", 1, true) then
				state.error = { message = command_error(output, "Could not update Mason tools"), timestamp = os.time() }
				publish()
				return
			end
			refresh("post_update")
		end)
	end)
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "")
	if action_id == "refresh" then
		refresh("item")
	elseif action_id == "update" then
		local update = update_for_id(tostring(event.target_widget_id or ""))
		if update ~= nil then
			run_update(update)
		end
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "")
	if action_id == "refresh" then
		refresh("manual")
	elseif action_id == "update_all" and #state.updates > 0 then
		run_update(nil)
	end
end)

--- Replaces a pending delayed refresh.
local function schedule_refresh(reason, delay_seconds)
	if pending_refresh ~= nil then
		pending_refresh:cancel()
	end
	pending_refresh = easybar.after(delay_seconds, function()
		pending_refresh = nil
		refresh(reason)
	end)
end

local timer = easybar.add(easybar.kind.item, "nvim_mason_inbox_timer", {
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
