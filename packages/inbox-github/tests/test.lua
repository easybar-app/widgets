local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()
local _, inbox = host.modules(root, easybar_root)

local function load_widget(storage_values)
	return host.load(root, easybar_root, "inbox-github", storage_values)
end

local function test_configures_the_refresh_interval()
	local state = load_widget({
		["github-inbox:refresh_interval_minutes"] = 15,
		["github-inbox:source_order"] = 17,
		["github-inbox:context_order"] = 18,
	})
	local timer = assert(state.added_items.github_inbox_timer, "the GitHub inbox timer must exist")
	assert(timer.interval == 15 * 60, "the GitHub timer must use the configured refresh interval")
	assert(
		assert(state:source_action("refresh_interval")).title == "Refresh every 15 minutes",
		"the GitHub context menu must show the refresh interval"
	)
	state:run_next_timer()
	assert(type(state.configuration.presentation.icon) == "string", "GitHub refresh activity must retain its source icon")
	assert(state.configuration.order == 18, "the GitHub context must use the configured order")
	state:complete_next_command("github-one", 0)
	assert(assert(state:item("thread-1")).source.order == 17, "the GitHub source must use the configured order")
end

local function test_item_actions_do_not_duplicate_native_controls()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitHub startup refresh must show source activity")
	state:complete_next_command("github-one", 0)
	assert(not state:has_busy_source_action(), "GitHub source activity must end after refresh")
	local item = assert(state:item("thread-1"), "GitHub notification must be published")
	assert(item.url == "https://github.com/easybar/easybar/pull/1", "GitHub notification must use the native URL field")
	assert(item.timestamp == inbox.timestamp("2026-08-03T09:45:00Z"), "GitHub notification must publish updated_at")
	assert(not state:item_has_action("thread-1", "open"), "GitHub notification must not duplicate the native Open action")
	assert(
		not state:item_has_action("thread-1", "mark_read"),
		"GitHub notification must not duplicate the native read action"
	)
	assert(
		not state:item_has_action("thread-1", "dismiss"),
		"GitHub notification must not duplicate the native Dismiss action"
	)
	assert(state:item_has_action("thread-1", "prepare_merge"), "pull requests must retain their Merge action")
end

local function test_merge_method_setting_persists_and_drives_merge()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_method:squash")).title == "✓ Squash and merge",
		"GitHub must mark the default squash method"
	)
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitHub must merge immediately by default"
	)

	state.context_action_handler({ action_id = "merge_confirmation:required" })
	assert(state.storage_values["github-inbox:confirm_merge"] == true, "GitHub must persist required confirmation")
	assert(
		assert(state:source_action("merge_confirmation:required")).title == "✓ Require confirmation",
		"GitHub must mark required confirmation"
	)

	state.context_action_handler({ action_id = "merge_method:rebase" })
	assert(state.storage_values["github-inbox:merge_method"] == "rebase", "GitHub must persist the selected merge method")
	assert(
		assert(state:source_action("merge_method:rebase")).title == "✓ Rebase and merge",
		"GitHub must mark the persisted merge method"
	)

	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
	state:complete_next_command("github-pr-ready", 0)
	assert(state:item_has_action("thread-1", "confirm_merge"), "ready pull requests must expose merge confirmation")

	state.action_handler({ action_id = "confirm_merge", target_widget_id = "thread-1" })
	local merge_command = assert(state.commands[1], "GitHub must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments["--rebase"], "GitHub merge command must use the persisted rebase method")
	assert(not arguments["--squash"], "GitHub merge command must not retain the previous squash method")
end

local function test_merge_confirmation_defaults_to_immediate()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitHub must mark immediate confirmation"
	)

	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
	state:complete_next_command("github-pr-ready", 0)
	assert(
		state:item_action_is_busy("thread-1", "confirm_merge"),
		"GitHub immediate mode must start merging without confirmation"
	)

	local merge_command = assert(state.commands[1], "GitHub immediate mode must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments.merge, "GitHub immediate mode must execute gh pr merge")
	assert(arguments["--match-head-commit"], "GitHub immediate mode must retain the inspected head guard")
	assert(arguments["0123456789abcdef"], "GitHub immediate mode must merge the inspected head commit")
end

local function test_errors_retain_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command(string.rep("x", 20000), 1)
	assert(state:item("thread-1") ~= nil, "GitHub refresh errors must retain the last good snapshot")
	assert(state.items[1].id == "error", "GitHub errors must be published before capped snapshot items")
	assert(utf8.len(assert(state:item("error")).body) <= inbox.maximum_error_length, "GitHub errors must be bounded")

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("github-object", 0)
	assert(state:item("thread-1") ~= nil, "GitHub malformed responses must retain the last good snapshot")
	assert(state:item("error") ~= nil, "GitHub malformed responses must publish an error")
end

test_item_actions_do_not_duplicate_native_controls()
test_merge_method_setting_persists_and_drives_merge()
test_merge_confirmation_defaults_to_immediate()
test_errors_retain_snapshot()
test_configures_the_refresh_interval()

print("GitHub inbox widget regression checks passed")
