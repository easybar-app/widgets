--- Shows live GitHub service health.

local text = require("text")

local OFFICIAL_SUMMARY_URL = "https://www.githubstatus.com/api/v2/summary.json"
local OFFICIAL_STATUS_URL = "https://www.githubstatus.com/"
local STORAGE_WIDGET = "github-status"
local STORAGE_REFRESH_INTERVAL_KEY = "refresh_interval_minutes"
local DEFAULT_REFRESH_INTERVAL_MINUTES = 15
local MINIMUM_REFRESH_INTERVAL_MINUTES = 5
local MAXIMUM_REFRESH_INTERVAL_MINUTES = 1440

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
	easybar.log(
		easybar.level.warn,
		"invalid widgets.github-status.refresh_interval_minutes; using " .. tostring(DEFAULT_REFRESH_INTERVAL_MINUTES)
	)
end

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	success = easybar.theme.ref.success,
	accent = easybar.theme.ref.accent,
	warning = easybar.theme.ref.warning,
	error = easybar.theme.ref.error,
	background = easybar.theme.ref.background,
	border = easybar.theme.ref.border_strong,
}

local state = {
	phase = "checking",
	indicator = "none",
	description = "Checking GitHub status…",
	incident_count = 0,
	degraded_component_count = 0,
	error = nil,
	last_checked = nil,
	popup_open = false,
}

local widget
local popup_status
local popup_detail
local refresh
local refresh_running = false
local refresh_pending = false

local INDICATOR_RANK = {
	none = 0,
	maintenance = 1,
	minor = 2,
	major = 3,
	critical = 4,
}

--- Returns the more severe of two Statuspage indicators.
local function more_severe_indicator(left, right)
	local left_rank = INDICATOR_RANK[left] or INDICATOR_RANK.critical
	local right_rank = INDICATOR_RANK[right] or INDICATOR_RANK.critical
	return right_rank > left_rank and right or left
end

--- Returns a compact label for a Statuspage indicator.
local function indicator_label(indicator)
	if indicator == "none" then
		return "Operational"
	elseif indicator == "maintenance" then
		return "Maintenance"
	elseif indicator == "minor" then
		return "Degraded"
	elseif indicator == "major" then
		return "Outage"
	end
	return "Critical"
end

--- Returns the color associated with a Statuspage indicator.
local function indicator_color(indicator)
	if indicator == "none" then
		return COLORS.success
	elseif indicator == "maintenance" then
		return COLORS.accent
	elseif indicator == "minor" then
		return COLORS.warning
	end
	return COLORS.error
end

--- Returns whether a decoded value is a JSON array.
local function is_array(value)
	return type(value) == "table" and easybar.json.is_array(value)
end

--- Decodes the fields needed from GitHub's official status summary.
local function parse_summary(output)
	local ok, payload = pcall(easybar.json.decode, tostring(output or ""))
	if not ok or type(payload) ~= "table" then
		return nil, "GitHub returned invalid status JSON"
	end
	if type(payload.status) ~= "table" or type(payload.status.indicator) ~= "string" then
		return nil, "GitHub returned no current status"
	end
	if type(payload.status.description) ~= "string" then
		return nil, "GitHub returned no status description"
	end
	if not is_array(payload.incidents) or not is_array(payload.components) then
		return nil, "GitHub returned an incomplete status summary"
	end

	local degraded_component_count = 0
	for _, component in ipairs(payload.components) do
		if type(component) == "table" and component.status ~= "operational" then
			degraded_component_count = degraded_component_count + 1
		end
	end
	local indicator = payload.status.indicator
	for _, incident in ipairs(payload.incidents) do
		if type(incident) == "table" and type(incident.impact) == "string" then
			indicator = more_severe_indicator(indicator, incident.impact)
		end
	end

	return {
		indicator = indicator,
		description = text.trim(payload.status.description),
		incident_count = #payload.incidents,
		degraded_component_count = degraded_component_count,
	},
		nil
end

--- Builds the widget's context menu.
local function context_menu()
	return {
		{ id = "refresh", title = refresh_running and "Refreshing…" or "Refresh", enabled = not refresh_running },
		{ id = "open", title = "Open GitHub Status" },
	}
end

--- Opens a status URL with the default macOS browser.
local function open_url(url)
	easybar.spawn_async({ "open", url }, { timeout_seconds = 5, max_output_bytes = 4096 }, function(_, code)
		if code ~= 0 then
			easybar.log(easybar.level.warn, "failed to open GitHub status URL", url)
		end
	end)
end

--- Renders the menu-bar item and its detail popup.
local function render()
	local color = state.error ~= nil and COLORS.error or indicator_color(state.indicator)
	widget:set({
		icon = {
			string = "",
			color = color,
			image = { path = easybar.asset("assets/github.svg"), size = 16 },
		},
		label = {
			string = state.phase == "checking" and "…"
				or (state.error ~= nil and "Unavailable" or indicator_label(state.indicator)),
			color = color,
		},
		popup = {
			drawing = state.popup_open,
			background = { color = COLORS.background, border_color = COLORS.border, border_width = 1, corner_radius = 8 },
			padding_x = 10,
			padding_y = 8,
			spacing = 6,
		},
		context_menu = context_menu(),
	})

	popup_status:set({
		label = {
			string = state.error ~= nil and "GitHub status unavailable" or "GitHub · " .. state.description,
			color = state.error ~= nil and COLORS.error or color,
		},
	})
	local detail
	if state.error ~= nil then
		detail = state.error
	else
		detail = tostring(state.incident_count)
			.. (state.incident_count == 1 and " active incident" or " active incidents")
			.. " · "
			.. tostring(state.degraded_component_count)
			.. " degraded components"
	end
	if state.last_checked ~= nil then
		detail = detail .. " · checked " .. os.date("%H:%M", state.last_checked)
	end
	popup_detail:set({ label = { string = text.truncate(detail, 180), color = COLORS.muted } })
end

--- Completes one refresh and runs a coalesced follow-up when requested.
local function finish_refresh()
	refresh_running = false
	state.phase = state.error ~= nil and "error" or "ready"
	state.last_checked = os.time()
	render()
	if refresh_pending then
		refresh_pending = false
		refresh()
	end
end

--- Fetches the live GitHub status summary.
refresh = function()
	if refresh_running then
		refresh_pending = true
		return
	end
	refresh_running = true
	state.phase = "checking"
	state.error = nil
	render()

	easybar.spawn_async({
		"/usr/bin/curl",
		"--fail",
		"--silent",
		"--show-error",
		"--location",
		OFFICIAL_SUMMARY_URL,
	}, { timeout_seconds = 20, max_output_bytes = 2 * 1024 * 1024 }, function(output, code)
		if code ~= 0 then
			state.error = text.trim(output) ~= "" and text.trim(output) or "Could not load GitHub's live status"
			finish_refresh()
			return
		end

		local summary, summary_error = parse_summary(output)
		if summary == nil then
			state.error = summary_error
			finish_refresh()
			return
		end
		state.indicator = summary.indicator
		state.description = summary.description
		state.incident_count = summary.incident_count
		state.degraded_component_count = summary.degraded_component_count
		finish_refresh()
	end)
end

widget = easybar.add(easybar.kind.item, "github_status", {
	position = "right",
	order = 3,
	interval = refresh_interval_minutes * 60,
	on_interval = refresh,
	icon = { string = "", image = { path = easybar.asset("assets/github.svg"), size = 16 } },
	label = { string = "…" },
})

popup_status = easybar.add(easybar.kind.item, "github_status_popup_status", {
	position = "popup." .. widget.id,
	label = { string = "GitHub · Checking status…", color = COLORS.text },
})
popup_detail = easybar.add(easybar.kind.item, "github_status_popup_detail", {
	position = "popup." .. widget.id,
	label = { string = "", color = COLORS.muted },
})

widget:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		state.popup_open = not state.popup_open
		render()
	end
end)
widget:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh()
	elseif event.action_id == "open" then
		open_url(OFFICIAL_STATUS_URL)
	end
end)
widget:subscribe({ easybar.events.forced, easybar.events.system_woke }, refresh)

render()
refresh()
