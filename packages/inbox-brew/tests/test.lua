local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

--- Loads the widget with controlled storage values and returns its test state.
local function load_widget(storage_values)
	storage_values = storage_values or {}
	if storage_values["brew-inbox:automatic_updates"] == nil then
		storage_values["brew-inbox:automatic_updates"] = false
	end
	return host.load(root, easybar_root, "inbox-brew", storage_values)
end

--- Loads the widget using its default persisted settings.
local function load_widget_with_defaults()
	return host.load(root, easybar_root, "inbox-brew")
end

--- Verifies that the configured refresh interval controls source metadata and timers.
local function test_configures_the_refresh_interval()
	local state = load_widget({
		["brew-inbox:refresh_interval_minutes"] = 15,
		["brew-inbox:source_order"] = 7,
		["brew-inbox:context_order"] = 8,
	})
	local timer = assert(state.added_items.brew_inbox_timer, "the Homebrew inbox timer must exist")
	assert(timer.interval == 15 * 60, "the Homebrew timer must use the configured refresh interval")
	state:run_next_timer()
	assert(
		type(state.configuration.presentation.icon) == "string",
		"Homebrew refresh activity must retain its source icon"
	)
	assert(state.configuration.order == 8, "the Homebrew context must use the configured order")
	assert(state:source_action("settings") == nil, "Homebrew settings must not add an outer submenu")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: Off",
		"the Homebrew context menu must show automatic-update state"
	)
	assert(
		assert(state:source_action("refresh_interval")).title == "Refresh every 15 minutes",
		"the Homebrew context menu must show the refresh interval"
	)
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	local item = assert(state:item("formula:easybar"))
	assert(item.source.order == 7, "the Homebrew source must use the configured order")
	assert(not state:item_has_action(item.id, "open"), "Homebrew must not duplicate the native Open action")
	assert(not state:item_has_action(item.id, "mark_read"), "Homebrew must not duplicate the native read action")
	assert(not state:item_has_action(item.id, "dismiss"), "Homebrew must not duplicate the native Dismiss action")
end

--- Verifies that automatic updates default on and respect upgrade policy.
local function test_automatic_updates_default_on_and_upgrade_eligible_packages()
	local state = load_widget_with_defaults()
	state:run_next_timer()
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"Homebrew automatic updates must default to on"
	)
	assert(table.concat(state.commands[1].command, " ") == "brew update", "the automatic cycle must update Homebrew")
	state:complete_next_command("", 0)
	state:run_next_timer()
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --json=v2",
		"the automatic cycle must check outdated packages after updating Homebrew"
	)
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(
		table.concat(state.commands[1].command, " ")
			== "/usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 brew upgrade --formula --yes easybar",
		"the automatic cycle must upgrade eligible packages"
	)
end

--- Verifies that enabling automatic updates persists and starts an update cycle.
local function test_automatic_updates_toggle_persists_and_starts_a_cycle()
	local state = load_widget({ ["brew-inbox:automatic_updates"] = false })
	state:run_next_timer()
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: Off",
		"Homebrew must show the disabled automatic-update state"
	)
	state:complete_next_command('{"scenario":"brew-empty"}', 0)
	state:run_next_timer()
	state.context_action_handler({ action_id = "toggle_automatic_updates" })
	assert(state.storage_values["brew-inbox:automatic_updates"] == true, "Homebrew must persist automatic updates")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"Homebrew must show the enabled automatic-update state"
	)
	assert(table.concat(state.commands[1].command, " ") == "brew update", "enabling automatic updates must start a cycle")
end

--- Verifies that item-triggered refresh activity remains on that inbox item.
local function test_item_refresh_stays_inline()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Homebrew startup refresh must show source activity")
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(not state:has_busy_source_action(), "Homebrew source activity must end after refresh")

	state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew upgrade must show inline activity")
	assert(not state:has_busy_source_action(), "Homebrew item mutation must not show source activity")

	state:complete_next_command("", 0)
	state:run_next_timer()
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew post-mutation refresh must stay inline")
	assert(not state:has_busy_source_action(), "Homebrew post-mutation refresh must not show source activity")

	state:complete_next_command('{"scenario":"brew-empty"}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") == nil, "Homebrew refreshed package must disappear")
	assert(not state:has_busy_source_action(), "Homebrew item completion must remain source-idle")
end

--- Verifies mixed warning output is parsed without discarding the last valid snapshot.
local function test_parser_retains_snapshot_and_handles_warning_braces()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command('{"scenario":"brew-malformed"}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") ~= nil, "Homebrew malformed responses must retain the last good snapshot")
	assert(state:item("error") ~= nil, "Homebrew malformed responses must publish an error")
	assert(state.items[1].id == "error", "Homebrew errors must be published before capped snapshot items")

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command('Warning {details}\n{"scenario":"brew-one"}\nTrailing {hint}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") ~= nil, "Homebrew must decode JSON surrounded by brace-containing warnings")
	assert(state:item("warning") ~= nil, "Homebrew must retain surrounding warning output")
	assert(state:item("error") == nil, "a valid Homebrew snapshot must clear the prior error")
end

--- Verifies that cancelling a refresh clears its busy state.
local function test_refresh_cancellation_clears_activity()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Homebrew refresh must start with source activity")
	state.context_action_handler({ action_id = "cancel" })
	assert(state:has_busy_source_action(), "Homebrew cancellation must retain activity during its completion delay")
	state:run_next_timer()
	assert(not state:has_busy_source_action(), "Homebrew cancellation must clear source activity")
end

--- Verifies that cancelling a mutation refreshes the retained package snapshot.
local function test_mutation_cancellation_reconciles_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()

	state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
	state.context_action_handler({ action_id = "cancel" })
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew cancellation must stay inline")
	assert(not state:has_busy_source_action(), "Homebrew item cancellation must not show source activity")

	state:complete_next_command("", 130)
	state:run_next_timer()
	assert(#state.commands == 1, "Homebrew cancellation must reconcile package state")
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew reconciliation must stay inline")
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(
		not state:item_action_is_busy("formula:easybar", "upgrade"),
		"Homebrew reconciliation must finish inline activity"
	)
end

test_item_refresh_stays_inline()
test_parser_retains_snapshot_and_handles_warning_braces()
test_refresh_cancellation_clears_activity()
test_mutation_cancellation_reconciles_snapshot()
test_configures_the_refresh_interval()
test_automatic_updates_default_on_and_upgrade_eligible_packages()
test_automatic_updates_toggle_persists_and_starts_a_cycle()

print("Homebrew inbox widget regression checks passed")
