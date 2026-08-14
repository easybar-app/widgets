--- Shows the number of available lazy.nvim plugin updates.
---
--- Left-click or use the context menu to check again. `NVIM` may point to
--- an executable name or absolute path, but must not contain shell arguments.

local text = require("text")

local STORAGE_WIDGET = "nvim-lazy"
local STORAGE_AUTOMATIC_UPDATES_KEY = "automatic_updates"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
local DEFAULT_AUTOMATIC_UPDATES = true
local DEFAULT_REFRESH_INTERVAL_MINUTES = 60
local MINIMUM_REFRESH_INTERVAL_MINUTES = 1
local MAXIMUM_REFRESH_INTERVAL_MINUTES = 1440

local ICONS = {
	checking = "󰑐",
	lazy = "󰒲",
}

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	accent = easybar.theme.ref.accent,
	warning = easybar.theme.ref.warning,
	error = easybar.theme.ref.error,
	popup_bg = easybar.theme.ref.background,
	border = easybar.theme.ref.border_strong,
}

local COMMAND_OPTIONS = {
	check = {
		timeout_seconds = 5 * 60,
		max_output_bytes = 4 * 1024 * 1024,
	},
	update = {
		timeout_seconds = 30 * 60,
		max_output_bytes = 8 * 1024 * 1024,
	},
}

local CHECK_SCRIPT = table.concat({
	"local ok, err = pcall(function()",
	"local lazy = require('lazy')",
	"lazy.check({ wait = true, show = false })",
	"local value = require('lazy.status').updates() or ''",
	"local count = tonumber(value:match('%d+')) or 0",
	"vim.api.nvim_out_write('EASYBAR_LAZY_UPDATES=' .. count .. '\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_LAZY_ERROR=' .. message)",
	"vim.cmd('cquit 1')",
	"end",
}, " ")

local UPDATE_SCRIPT = table.concat({
	"local ok, err = pcall(function()",
	"require('lazy').update({ wait = true, show = false })",
	"vim.api.nvim_out_write('EASYBAR_LAZY_UPDATED=1\\n')",
	"end)",
	"if not ok then",
	"local message = tostring(err):gsub('[\\r\\n]+', ' ')",
	"vim.api.nvim_err_writeln('EASYBAR_LAZY_ERROR=' .. message)",
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
		"invalid widgets.nvim-lazy.automatic_updates; using " .. tostring(DEFAULT_AUTOMATIC_UPDATES)
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
		"invalid widgets.nvim-lazy.refresh_interval_minutes; using " .. tostring(DEFAULT_REFRESH_INTERVAL_MINUTES)
	)
	refresh_interval_minutes = DEFAULT_REFRESH_INTERVAL_MINUTES
end

local widget
local popup_status
local popup_detail

local state = {
	phase = "checking",
	update_count = 0,
	last_checked = nil,
	error = nil,
}

local refresh
local run_update_all
local refresh_running = false
local update_running = false
local refresh_pending = false
local refresh_pending_automatic = false

--- Reports whether a check or update operation is active.
---@return boolean
local function operation_running()
	return refresh_running or update_running
end

--- Coalesces a refresh request while another operation is active.
---@param automatic boolean
local function queue_refresh(automatic)
	refresh_pending = true
	refresh_pending_automatic = refresh_pending_automatic or automatic
end

--- Runs one coalesced refresh request, if any.
---@return boolean
local function run_pending_refresh()
	if not refresh_pending then
		return false
	end

	local automatic = refresh_pending_automatic
	refresh_pending = false
	refresh_pending_automatic = false
	refresh(automatic)
	return true
end

--- Returns the first meaningful error line from Neovim's output.
local function error_detail(output, code)
	local marker = output:match("EASYBAR_LAZY_ERROR=([^\r\n]+)")
	if marker ~= nil then
		return text.truncate(text.trim(marker), 160)
	end

	for line in tostring(output or ""):gmatch("[^\r\n]+") do
		local normalized = text.trim(line)
		if normalized ~= "" and not normalized:match("^EASYBAR_LAZY_UPDATES=") then
			return text.truncate(normalized, 160)
		end
	end

	return "Neovim exited with code " .. tostring(code)
end

--- Builds the widget's native context menu.
local function context_menu()
	local busy = operation_running()
	return {
		{
			id = "refresh",
			title = refresh_running and "Checking…" or "Refresh",
			enabled = not busy,
		},
		{
			id = "update_all",
			title = state.update_count > 0 and "Update all (" .. tostring(state.update_count) .. ")" or "No updates",
			enabled = not busy and state.update_count > 0,
		},
		{
			id = "toggle_automatic_updates",
			title = "Automatic updates: " .. (automatic_updates and "On" or "Off"),
			enabled = not update_running,
		},
	}
end

--- Returns a human-readable status for the popup.
local function status_label()
	if state.phase == "checking" then
		return "Lazy · Checking for updates…"
	end
	if state.phase == "updating" then
		return "Lazy · Updating plugins…"
	end
	if state.phase == "error" then
		return "Lazy · Check failed"
	end
	if state.update_count == 0 then
		return "Lazy · Up to date"
	end

	local noun = state.update_count == 1 and "update" or "updates"
	return "Lazy · " .. tostring(state.update_count) .. " " .. noun .. " available"
end

--- Returns secondary status text for the popup.
local function detail_label()
	if state.phase == "error" then
		return state.error or "Unable to query lazy.nvim"
	end
	if state.phase == "updating" then
		return "Installing available plugin updates"
	end
	if state.last_checked ~= nil then
		return "Last checked: " .. tostring(os.date("%H:%M", state.last_checked))
	end
	return "Starting headless Neovim"
end

--- Renders the current check state.
local function render()
	local color = COLORS.muted
	local label = ""
	local icon = ICONS.lazy

	if state.phase == "checking" or state.phase == "updating" then
		color = COLORS.accent
		icon = ICONS.checking
	elseif state.phase == "error" then
		color = COLORS.error
		label = "!"
	elseif state.update_count > 0 then
		color = COLORS.warning
		label = tostring(state.update_count)
	end

	widget:set({
		icon = {
			string = icon,
			color = color,
		},
		label = {
			string = label,
			color = color,
		},
		context_menu = context_menu(),
	})

	popup_status:set({
		label = {
			string = status_label(),
			color = state.phase == "error" and COLORS.error or COLORS.text,
		},
	})

	popup_detail:set({
		label = {
			string = detail_label(),
			color = COLORS.muted,
		},
	})
end

--- Runs a lazy.nvim update check in the user's normal Neovim configuration.
local function check_updates(callback)
	easybar.spawn_async(
		{
			NVIM,
			"--headless",
			"-c",
			"lua " .. CHECK_SCRIPT,
			"-c",
			"qa",
		},
		COMMAND_OPTIONS.check,
		function(output, code)
			output = tostring(output or "")
			code = code or 0

			if code ~= 0 then
				callback(nil, error_detail(output, code))
				return
			end

			local count = tonumber(output:match("EASYBAR_LAZY_UPDATES=(%d+)"))
			if count == nil then
				callback(nil, "Neovim returned no lazy.nvim update count")
				return
			end

			callback(count, nil)
		end
	)
end

--- Checks for updates and optionally installs them after an automatic cycle.
---@param automatic? boolean
refresh = function(automatic)
	automatic = automatic == true
	if operation_running() then
		queue_refresh(automatic)
		return
	end

	refresh_running = true
	state.phase = "checking"
	state.error = nil
	render()

	check_updates(function(count, err)
		refresh_running = false
		state.last_checked = os.time()

		if err ~= nil then
			state.phase = "error"
			state.error = err
			easybar.log(easybar.level.warn, "lazy.nvim update check failed", err)
		else
			state.phase = "ready"
			state.update_count = count
			state.error = nil
		end

		render()

		if err == nil and automatic and automatic_updates and state.update_count > 0 then
			run_update_all()
			return
		end

		run_pending_refresh()
	end)
end

--- Updates every available lazy.nvim plugin, then reconciles the update count.
run_update_all = function()
	if operation_running() or state.update_count == 0 then
		return
	end

	update_running = true
	state.phase = "updating"
	state.error = nil
	render()

	easybar.spawn_async(
		{ NVIM, "--headless", "-c", "lua " .. UPDATE_SCRIPT, "-c", "qa" },
		COMMAND_OPTIONS.update,
		function(output, code)
			update_running = false
			output = tostring(output or "")
			code = code or 0

			if code ~= 0 or not output:find("EASYBAR_LAZY_UPDATED=1", 1, true) then
				state.phase = "error"
				state.error = error_detail(output, code)
				easybar.log(easybar.level.warn, "lazy.nvim automatic update failed", state.error)
				render()
				run_pending_refresh()
				return
			end

			refresh_pending = false
			refresh_pending_automatic = false
			refresh(false)
		end
	)
end

--- Persists automatic-update behavior and starts a cycle when enabled.
---@param enabled boolean
local function set_automatic_updates(enabled)
	if type(enabled) ~= "boolean" or enabled == automatic_updates then
		render()
		return
	end

	local ok, err = easybar.storage.set(STORAGE_WIDGET, STORAGE_AUTOMATIC_UPDATES_KEY, enabled)
	if not ok then
		state.phase = "error"
		state.error = tostring(err or "EasyBar could not update config.toml")
		render()
		return
	end

	automatic_updates = enabled
	easybar.log(easybar.level.info, "lazy.nvim automatic updates", "enabled=" .. tostring(enabled))
	render()
	if enabled then
		refresh(true)
	end
end

widget = easybar.add(easybar.kind.item, "nvim_lazy_updates", {
	position = "right",
	order = 2,
	interval = refresh_interval_minutes * 60,
	icon = {
		string = ICONS.checking,
		color = COLORS.accent,
	},
	label = {
		string = "",
	},
	popup = {
		drawing = true,
		background = {
			color = COLORS.popup_bg,
			border_color = COLORS.border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
		spacing = 6,
	},
	on_interval = function()
		refresh(true)
	end,
})

popup_status = easybar.add(easybar.kind.item, "nvim_lazy_updates_popup_status", {
	position = "popup." .. widget.id,
	label = {
		string = "Lazy · Checking for updates…",
		color = COLORS.text,
	},
})

popup_detail = easybar.add(easybar.kind.item, "nvim_lazy_updates_popup_detail", {
	position = "popup." .. widget.id,
	label = {
		string = "Starting headless Neovim",
		color = COLORS.muted,
	},
})

widget:subscribe({
	easybar.events.system_woke,
	easybar.events.forced,
}, function()
	refresh(true)
end)

widget:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		refresh(false)
	end
end)

widget:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh(false)
	elseif event.action_id == "update_all" then
		run_update_all()
	elseif event.action_id == "toggle_automatic_updates" then
		set_automatic_updates(not automatic_updates)
	end
end)

refresh(true)
