--- Publishes active GitHub service incidents to the native inbox.

local inbox = require("inbox")
local text = require("text")

local SOURCE = "GitHub Status"
local SOURCE_PRESENTATION = {
	name = SOURCE,
	icon = easybar.asset("assets/github.svg"),
	color = "#D1242F",
}
local SUMMARY_URL = "https://www.githubstatus.com/api/v2/summary.json"
local OFFICIAL_STATUS_URL = "https://www.githubstatus.com/"
local STORAGE_WIDGET = "github-status-inbox"
local DEFAULT_REFRESH_INTERVAL_MINUTES = 5
local DEFAULT_SOURCE_ORDER = 15
local DEFAULT_CONTEXT_ORDER = 15
local NETWORK_READY_DELAY_SECONDS = 3

--- Reads a bounded integer setting or returns its default.
local function configured_integer(key, default, minimum, maximum)
	local configured = easybar.storage.get(STORAGE_WIDGET, key, default)
	local value = tonumber(configured)
	if value == nil or value ~= math.floor(value) or value < minimum or value > maximum then
		easybar.log(easybar.level.warn, "invalid widgets.github-status-inbox." .. key .. "; using " .. tostring(default))
		return default
	end
	return value
end

local refresh_interval_minutes =
	configured_integer("refresh_interval_minutes", DEFAULT_REFRESH_INTERVAL_MINUTES, 5, 10080)
local source_order = configured_integer("source_order", DEFAULT_SOURCE_ORDER, -10000, 10000)
local context_order = configured_integer("context_order", DEFAULT_CONTEXT_ORDER, -10000, 10000)
SOURCE_PRESENTATION.order = source_order

local state = {
	entries = {},
	status_description = "Status not checked",
	error = nil,
	refreshing = false,
	refresh_pending = false,
}
local pending_refresh
local refresh

--- Returns the severity associated with a Statuspage impact.
local function severity_for_impact(impact)
	if impact == "critical" or impact == "major" then
		return "error"
	elseif impact == "minor" then
		return "warning"
	end
	return "info"
end

--- Returns the newest non-empty update body for an incident or maintenance entry.
local function latest_update_body(entry)
	for _, update in ipairs(type(entry.incident_updates) == "table" and entry.incident_updates or {}) do
		if type(update) == "table" and text.trim(update.body) ~= "" then
			return text.trim(update.body)
		end
	end
	return "Open the GitHub status page for details."
end

--- Returns a concise category from an entry's affected components.
local function entry_category(entry, fallback)
	local names = {}
	for _, component in ipairs(type(entry.components) == "table" and entry.components or {}) do
		if type(component) == "table" and text.trim(component.name) ~= "" then
			names[#names + 1] = text.trim(component.name)
		end
	end
	return #names > 0 and text.truncate(table.concat(names, ", "), 120) or fallback
end

--- Validates and normalizes one incident or maintenance entry.
local function normalize_entry(entry, kind)
	if type(entry) ~= "table" or text.trim(entry.id) == "" or text.trim(entry.name) == "" then
		return nil
	end
	local timestamp = inbox.timestamp(entry.updated_at) or inbox.timestamp(entry.created_at)
	if timestamp == nil then
		return nil
	end
	local url = text.trim(entry.shortlink)
	if url == "" then
		url = OFFICIAL_STATUS_URL
	end
	return {
		id = kind .. ":" .. tostring(entry.id),
		title = text.trim(entry.name),
		body = latest_update_body(entry),
		category = entry_category(entry, kind == "maintenance" and "Maintenance" or "Incident"),
		severity = kind == "maintenance" and "info" or severity_for_impact(entry.impact),
		unread = true,
		timestamp = timestamp,
		url = url,
		source = SOURCE_PRESENTATION,
	}
end

--- Decodes the current GitHub status summary into inbox entries.
local function parse_summary(output)
	local ok, payload = pcall(easybar.json.decode, tostring(output or ""))
	if not ok or type(payload) ~= "table" or easybar.json.is_array(payload) then
		return nil, nil, "GitHub returned invalid status JSON"
	end
	if type(payload.status) ~= "table" or type(payload.status.description) ~= "string" then
		return nil, nil, "GitHub returned no current status"
	end
	if not easybar.json.is_array(payload.incidents) or not easybar.json.is_array(payload.scheduled_maintenances) then
		return nil, nil, "GitHub returned an incomplete status summary"
	end

	local entries = {}
	for _, incident in ipairs(payload.incidents) do
		local normalized = normalize_entry(incident, "incident")
		if normalized == nil then
			return nil, nil, "GitHub returned an invalid incident"
		end
		entries[#entries + 1] = normalized
	end
	for _, maintenance in ipairs(payload.scheduled_maintenances) do
		local normalized = normalize_entry(maintenance, "maintenance")
		if normalized == nil then
			return nil, nil, "GitHub returned invalid maintenance"
		end
		entries[#entries + 1] = normalized
	end
	table.sort(entries, function(left, right)
		return left.timestamp > right.timestamp
	end)
	return entries, text.trim(payload.status.description), nil
end

--- Opens a status URL with the default macOS browser.
local function open_url(url)
	easybar.spawn_async({ "open", url }, { timeout_seconds = 5, max_output_bytes = 4096 }, function(_, code)
		if code ~= 0 then
			easybar.log(easybar.level.warn, "failed to open GitHub status URL", url)
		end
	end)
end

--- Publishes source actions for the current refresh state.
local function configure_source_actions()
	local refresh_action = {
		id = "refresh",
		title = state.refreshing and "Refreshing…" or "Refresh",
		enabled = not state.refreshing,
		busy = state.refreshing or nil,
		include_in_refresh_all = true,
	}
	local entry_count = #state.entries
	local current_status = entry_count == 0 and state.status_description
		or tostring(entry_count) .. (entry_count == 1 and " active event" or " active events")
	easybar.inbox.configure(SOURCE, {
		order = context_order,
		presentation = SOURCE_PRESENTATION,
		actions = {
			refresh_action,
			{ id = "status", title = current_status, enabled = false },
			{
				id = "refresh_interval",
				title = "Refresh every " .. tostring(refresh_interval_minutes) .. " minutes",
				enabled = false,
			},
			{ id = "open", title = "Open GitHub Status" },
		},
	})
end

--- Publishes the retained incident snapshot and any current error.
local function publish()
	local items = {}
	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = "GitHub status unavailable",
			body = state.error,
			severity = "error",
			unread = true,
			timestamp = os.time(),
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end
	for _, entry in ipairs(state.entries) do
		items[#items + 1] = entry
	end
	configure_source_actions()
	easybar.inbox.replace(SOURCE, items)
end

--- Fetches and publishes the latest GitHub status summary.
refresh = function()
	if state.refreshing then
		state.refresh_pending = true
		return
	end
	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end
	state.refreshing = true
	configure_source_actions()

	easybar.spawn_async({
		"/usr/bin/curl",
		"--fail",
		"--silent",
		"--show-error",
		"--location",
		SUMMARY_URL,
	}, { timeout_seconds = 20, max_output_bytes = 2 * 1024 * 1024 }, function(output, code)
		state.refreshing = false
		if code ~= 0 then
			state.error = inbox.error_message(output, "Could not load GitHub status")
		else
			local entries, description, parse_error = parse_summary(output)
			if entries == nil then
				state.error = parse_error
			else
				state.entries = entries
				state.status_description = description
				state.error = nil
			end
		end
		publish()
		if state.refresh_pending then
			state.refresh_pending = false
			refresh()
		end
	end)
end

--- Schedules one delayed refresh, replacing any pending request.
local function schedule_refresh(delay_seconds)
	if pending_refresh ~= nil then
		pending_refresh:cancel()
	end
	pending_refresh = easybar.after(delay_seconds, function()
		pending_refresh = nil
		refresh()
	end)
end

configure_source_actions()
easybar.inbox.on_action(SOURCE, function(event)
	if event.action_id == "refresh" then
		refresh()
	end
end)
easybar.inbox.on_context_action(SOURCE, function(event)
	if event.action_id == "refresh" then
		refresh()
	elseif event.action_id == "open" then
		open_url(OFFICIAL_STATUS_URL)
	end
end)

local timer = easybar.add(easybar.kind.item, "github_status_inbox_timer", {
	drawing = false,
	interval = refresh_interval_minutes * 60,
	on_interval = function()
		refresh()
	end,
})
timer:subscribe(easybar.events.forced, function()
	refresh()
end)
timer:subscribe(easybar.events.system_woke, function()
	schedule_refresh(NETWORK_READY_DELAY_SECONDS)
end)
timer:subscribe(easybar.events.session_active, function()
	schedule_refresh(NETWORK_READY_DELAY_SECONDS)
end)

schedule_refresh(NETWORK_READY_DELAY_SECONDS)
