--- Shows the number of available lazy.nvim plugin updates.
---
--- Left-click or use the context menu to check again. `NVIM` may point to
--- an executable name or absolute path, but must not contain shell arguments.

local text = require("text")

local STORAGE_WIDGET = "nvim-lazy"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
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
	timeout_seconds = 300,
	max_output_bytes = 1024 * 1024,
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
local refresh_running = false
local refresh_pending = false

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
	return {
		{
			id = "refresh",
			title = refresh_running and "Checking…" or "Refresh",
			enabled = not refresh_running,
		},
	}
end

--- Returns a human-readable status for the popup.
local function status_label()
	if state.phase == "checking" then
		return "Lazy · Checking for updates…"
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

	if state.phase == "checking" then
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
		COMMAND_OPTIONS,
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

--- Checks for updates while coalescing refresh requests during an active check.
refresh = function()
	if refresh_running then
		refresh_pending = true
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

		if refresh_pending then
			refresh_pending = false
			refresh()
		end
	end)
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
		refresh()
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
	refresh()
end)

widget:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		refresh()
	end
end)

widget:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh()
	end
end)

refresh()
