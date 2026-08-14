--- Publishes lazy.nvim plugin updates to EasyBar's native inbox.

local inbox = require("inbox")
local text = require("text")

local SOURCE = "lazy.nvim"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "lazy.nvim",
	icon = easybar.asset("assets/lazy.svg"),
	color = "#8B7CF6",
}

local STORAGE_WIDGET = "nvim-lazy-inbox"
local STORAGE_AUTOMATIC_UPDATES_KEY = "automatic_updates"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
local STORAGE_SOURCE_ORDER_KEY = "source_order"
local STORAGE_CONTEXT_ORDER_KEY = "context_order"
local DEFAULT_AUTOMATIC_UPDATES = true
local DEFAULT_REFRESH_INTERVAL_MINUTES = 60
local DEFAULT_SOURCE_ORDER = 35
local DEFAULT_CONTEXT_ORDER = 35
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
	"local lazy = require('lazy')",
	"lazy.check({ wait = true, show = false })",
	"local checker = require('lazy.manage.checker')",
	"local plugins = require('lazy.core.config').plugins",
	"local updates = {}",
	"for _, name in ipairs(checker.updated) do",
	"local plugin = plugins[name]",
	"local change = plugin and plugin._ and plugin._.updates or {}",
	"updates[#updates + 1] = { name = name, from = change.from and change.from.commit or nil, to = change.to and change.to.commit or nil, url = plugin and plugin.url or nil }",
	"end",
	"table.sort(updates, function(a, b) return a.name < b.name end)",
	"vim.api.nvim_out_write('EASYBAR_NVIM_LAZY_UPDATES=' .. vim.json.encode(updates) .. '\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_NVIM_LAZY_ERROR=' .. message)",
	"vim.cmd('cquit 1')",
	"end",
}, " ")

local UPDATE_SCRIPT = table.concat({
	"local ok, err = pcall(function()",
	"local plugin = vim.env.EASYBAR_NVIM_LAZY_PLUGIN",
	"local opts = { wait = true, show = false }",
	"if plugin and plugin ~= '' then opts.plugins = { plugin } end",
	"require('lazy').update(opts)",
	"vim.api.nvim_out_write('EASYBAR_NVIM_LAZY_UPDATED=1\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_NVIM_LAZY_ERROR=' .. message)",
	"vim.cmd('cquit 1')",
	"end",
}, " ")

local NVIM = text.trim(os.getenv("NVIM") or "")
if NVIM == "" then
	NVIM = "nvim"
end

local configured_automatic_updates =
	easybar.storage.get(STORAGE_WIDGET, STORAGE_AUTOMATIC_UPDATES_KEY, DEFAULT_AUTOMATIC_UPDATES)
local automatic_updates = configured_automatic_updates
if type(automatic_updates) ~= "boolean" then
	automatic_updates = DEFAULT_AUTOMATIC_UPDATES
	easybar.log(
		easybar.level.warn,
		"invalid widgets.nvim-lazy-inbox.automatic_updates; using " .. tostring(DEFAULT_AUTOMATIC_UPDATES)
	)
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
		"invalid widgets.nvim-lazy-inbox.refresh_interval_minutes; using " .. tostring(DEFAULT_REFRESH_INTERVAL_MINUTES)
	)
	refresh_interval_minutes = DEFAULT_REFRESH_INTERVAL_MINUTES
end

--- Reads and validates a configured Inbox source or context-menu order.
local function configured_order(key, default)
	local configured = easybar.storage.get(STORAGE_WIDGET, key, default)
	local value = tonumber(configured)
	if value == nil or value ~= math.floor(value) or value < -10000 or value > 10000 then
		easybar.log(easybar.level.warn, "invalid widgets.nvim-lazy-inbox." .. key .. "; using " .. tostring(default))
		return default
	end
	return value
end

local source_order = configured_order(STORAGE_SOURCE_ORDER_KEY, DEFAULT_SOURCE_ORDER)
local context_order = configured_order(STORAGE_CONTEXT_ORDER_KEY, DEFAULT_CONTEXT_ORDER)
SOURCE_PRESENTATION.order = source_order
local POLL_INTERVAL_SECONDS = refresh_interval_minutes * 60

local state = {
	updates = {},
	error = nil,
	operation = nil,
}
local pending_refresh = nil
local refresh
local run_update

--- Returns a concise commit identifier or nil when Lazy did not provide one.
local function short_commit(value)
	value = type(value) == "string" and text.trim(value) or ""
	return value ~= "" and value:sub(1, 7) or nil
end

--- Converts a plugin Git URL into a browser URL when possible.
local function browser_url(value)
	value = type(value) == "string" and text.trim(value) or ""
	if not value:match("^https?://") then
		return nil
	end
	return value:gsub("%.git$", "")
end

--- Extracts and validates the JSON update payload emitted by headless Neovim.
local function decode_updates(output)
	local payload = tostring(output or ""):match("EASYBAR_NVIM_LAZY_UPDATES=([^\r\n]+)")
	if payload == nil then
		return nil, "Neovim returned no lazy.nvim update list"
	end

	local ok, decoded = pcall(easybar.json.decode, payload)
	if not ok or not easybar.json.is_array(decoded) then
		return nil, "Neovim returned an invalid lazy.nvim update list"
	end

	local updates = {}
	local seen = {}
	for _, entry in ipairs(decoded) do
		if type(entry) ~= "table" or easybar.json.is_array(entry) then
			return nil, "lazy.nvim returned an invalid plugin update"
		end
		local name = type(entry.name) == "string" and text.trim(entry.name) or ""
		if name == "" then
			return nil, "lazy.nvim returned a plugin update without a name"
		end
		if not seen[name] and #updates < MAX_ITEMS then
			seen[name] = true
			updates[#updates + 1] = {
				id = "plugin:" .. name,
				name = name,
				from = short_commit(entry.from),
				to = short_commit(entry.to),
				url = browser_url(entry.url),
			}
		end
	end
	return updates, nil
end

--- Finds the retained plugin represented by an Inbox item identifier.
local function update_for_id(item_id)
	for _, update in ipairs(state.updates) do
		if update.id == item_id then
			return update
		end
	end
	return nil
end

--- Publishes source-level refresh, update, and automatic-update actions.
local function configure_source_actions()
	local operation = state.operation
	local automatic_action = {
		id = "toggle_automatic_updates",
		title = "Automatic updates: " .. (automatic_updates and "On" or "Off"),
		enabled = operation == nil,
	}
	local interval_action = {
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
			automatic_action,
			interval_action,
		}
	else
		actions = {
			{ id = "refresh", title = "Refresh", include_in_refresh_all = true },
			{
				id = "update_all",
				title = #state.updates > 0 and "Update all (" .. tostring(#state.updates) .. ")" or "No updates",
				enabled = #state.updates > 0,
			},
			automatic_action,
			interval_action,
		}
	end

	easybar.inbox.configure(SOURCE, {
		order = context_order,
		presentation = SOURCE_PRESENTATION,
		actions = actions,
	})
end

--- Publishes the current lazy.nvim update and error snapshot.
local function publish()
	local items = {}
	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = "Could not check lazy.nvim updates",
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

		local body = "Update available"
		if update.from ~= nil and update.to ~= nil then
			body = update.from .. " → " .. update.to
		end
		items[#items + 1] = {
			id = update.id,
			title = update.name,
			body = body,
			category = "Plugins",
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

--- Completes an operation after keeping its activity visible briefly.
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

--- Returns the most useful Lazy error embedded in mixed Neovim output.
local function command_error(output, fallback)
	local message = tostring(output or ""):match("EASYBAR_NVIM_LAZY_ERROR=([^\r\n]+)")
	return message ~= nil and text.truncate(text.trim(message), 12000, "…") or inbox.error_message(output, fallback)
end

--- Builds a headless Neovim command for one embedded Lua program.
local function nvim_command(script, plugin_name)
	local command = {}
	if plugin_name ~= nil then
		command = { "/usr/bin/env", "EASYBAR_NVIM_LAZY_PLUGIN=" .. plugin_name }
	end
	command[#command + 1] = NVIM
	command[#command + 1] = "--headless"
	command[#command + 1] = "-c"
	command[#command + 1] = "lua " .. script
	command[#command + 1] = "-c"
	command[#command + 1] = "qa"
	return command
end

--- Checks Lazy for plugin updates and optionally installs them after the check.
---@param reason string
---@param automatic? boolean
refresh = function(reason, automatic)
	automatic = automatic == true
	if state.operation ~= nil then
		return
	end
	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	local operation = { kind = "refresh", title = "Checking plugin updates…", item_id = nil }
	state.operation = operation
	publish()
	easybar.log(easybar.level.debug, "lazy.nvim inbox refresh started reason=" .. tostring(reason or "unspecified"))

	easybar.spawn_async(nvim_command(CHECK_SCRIPT), EXEC.check, function(output, code)
		if state.operation ~= operation then
			return
		end
		finish_operation(operation, function()
			local should_update = false
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
					should_update = automatic and automatic_updates and #state.updates > 0
				end
			end
			publish()
			if should_update then
				run_update(nil)
			end
		end)
	end)
end

--- Runs one Lazy update operation and refreshes the resulting snapshot.
run_update = function(plugin)
	if state.operation ~= nil then
		return
	end

	local plugin_name = plugin ~= nil and plugin.name or ""
	local title = plugin ~= nil and ("Updating " .. plugin.name .. "…") or "Updating all plugins…"
	local operation = { kind = "update", title = title, item_id = plugin ~= nil and plugin.id or nil }
	state.operation = operation
	state.error = nil
	publish()

	easybar.spawn_async(nvim_command(UPDATE_SCRIPT, plugin_name), EXEC.update, function(output, code)
		if state.operation ~= operation then
			return
		end
		finish_operation(operation, function()
			if code ~= 0 or not tostring(output or ""):find("EASYBAR_NVIM_LAZY_UPDATED=1", 1, true) then
				state.error = {
					message = command_error(output, "Could not update lazy.nvim plugins"),
					timestamp = os.time(),
				}
				publish()
				return
			end
			refresh("post_update", false)
		end)
	end)
end

--- Persists automatic-update behavior and starts a cycle when enabled.
---@param enabled boolean
local function set_automatic_updates(enabled)
	if type(enabled) ~= "boolean" or enabled == automatic_updates then
		configure_source_actions()
		return
	end

	local ok, err = easybar.storage.set(STORAGE_WIDGET, STORAGE_AUTOMATIC_UPDATES_KEY, enabled)
	if not ok then
		state.error = { message = tostring(err or "EasyBar could not update config.toml"), timestamp = os.time() }
		publish()
		return
	end

	automatic_updates = enabled
	easybar.log(easybar.level.info, "lazy.nvim inbox automatic updates", "enabled=" .. tostring(enabled))
	publish()
	if enabled then
		refresh("setting_enabled", true)
	end
end

--- Runs one scheduled check and allows an automatic update when enabled.
---@param reason string
local function run_automatic_update_cycle(reason)
	refresh(reason, automatic_updates)
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "")
	if action_id == "refresh" then
		refresh("item", false)
	elseif action_id == "update" then
		local plugin = update_for_id(tostring(event.target_widget_id or ""))
		if plugin ~= nil then
			run_update(plugin)
		end
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "")
	if action_id == "refresh" then
		refresh("manual", false)
	elseif action_id == "update_all" and #state.updates > 0 then
		run_update(nil)
	elseif action_id == "toggle_automatic_updates" then
		set_automatic_updates(not automatic_updates)
	end
end)

--- Replaces any pending delayed refresh with a newly scheduled request.
local function schedule_refresh(reason, delay_seconds)
	if pending_refresh ~= nil then
		pending_refresh:cancel()
	end
	pending_refresh = easybar.after(delay_seconds, function()
		pending_refresh = nil
		run_automatic_update_cycle(reason)
	end)
end

local timer = easybar.add(easybar.kind.item, "nvim_lazy_inbox_timer", {
	drawing = false,
	interval = POLL_INTERVAL_SECONDS,
	on_interval = function()
		run_automatic_update_cycle("interval")
	end,
})

timer:subscribe(easybar.events.forced, function()
	run_automatic_update_cycle("forced")
end)

timer:subscribe(easybar.events.system_woke, function()
	schedule_refresh("wake", NETWORK_READY_DELAY_SECONDS)
end)

timer:subscribe(easybar.events.session_active, function()
	schedule_refresh("session_active", NETWORK_READY_DELAY_SECONDS)
end)

schedule_refresh("startup", NETWORK_READY_DELAY_SECONDS)
