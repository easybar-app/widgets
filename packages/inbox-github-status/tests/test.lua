local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

--- Verifies active incidents are published with native URLs and severity.
local function test_publishes_active_incidents()
	local state = host.load(root, easybar_root, "inbox-github-status")
	local refresh = assert(state:source_action("refresh"), "GitHub Status must provide manual refresh")
	assert(refresh.include_in_refresh_all == true, "the native Inbox refresh button must include GitHub Status")

	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitHub Status refresh must show source activity")
	assert(state.commands[1].command[#state.commands[1].command] == "https://www.githubstatus.com/api/v2/summary.json")
	state:complete_next_command("github-status-active", 0)

	local incident = assert(state:item("incident:incident-1"), "an active GitHub incident must be published")
	assert(incident.title == "Incident with GitHub.com")
	assert(incident.body == "Actions is experiencing degraded performance.")
	assert(incident.category == "Actions, API Requests")
	assert(incident.severity == "error", "critical GitHub incidents must use error severity")
	assert(incident.url == "https://stspg.io/example")
	assert(assert(state:source_action("status")).title == "1 active event")
	assert(not state:has_busy_source_action(), "completed GitHub status checks must clear source activity")

	state.context_action_handler({ action_id = "refresh" })
	assert(state:has_busy_source_action(), "manual GitHub status refresh must show source activity")
	state:complete_next_command("github-status-operational", 0)
	assert(state:item("incident:incident-1") == nil, "resolved incidents must leave the active snapshot")
	assert(assert(state:source_action("status")).title == "All Systems Operational")
end

--- Verifies invalid responses preserve incidents and expose a retryable error.
local function test_invalid_response_retains_snapshot()
	local state = host.load(root, easybar_root, "inbox-github-status")
	state:run_next_timer()
	state:complete_next_command("github-status-active", 0)
	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("github-status-malformed", 0)
	assert(state:item("incident:incident-1") ~= nil, "a failed refresh must retain the last valid incident snapshot")
	assert(state:item("error") ~= nil, "a failed refresh must publish a retryable error")
	assert(state:item_has_action("error", "refresh"), "the GitHub status error must offer Refresh")
end

--- Verifies interval and ordering settings are reflected in source metadata.
local function test_configures_interval_and_order()
	local state = host.load(root, easybar_root, "inbox-github-status", {
		["github-status-inbox:refresh_interval_minutes"] = 20,
		["github-status-inbox:source_order"] = 16,
		["github-status-inbox:context_order"] = 17,
	})
	local timer = assert(state.added_items.github_status_inbox_timer)
	assert(timer.interval == 20 * 60)
	assert(type(timer.on_interval) == "function", "the polling interval must provide its required callback")
	assert(state.configuration.order == 17)
	assert(assert(state:source_action("refresh_interval")).title == "Refresh every 20 minutes")
	state:run_next_timer()
	state:complete_next_command("github-status-active", 0)
	assert(assert(state:item("incident:incident-1")).source.order == 16)
	timer.on_interval()
	assert(state:has_busy_source_action(), "the polling callback must start a GitHub status refresh")
	state:complete_next_command("github-status-operational", 0)
end

test_publishes_active_incidents()
test_invalid_response_retains_snapshot()
test_configures_interval_and_order()

print("GitHub Status inbox regression checks passed")
