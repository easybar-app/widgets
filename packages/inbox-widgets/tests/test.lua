local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

local function load_widget(storage_values)
	return host.load(root, easybar_root, "inbox-widgets", storage_values)
end

local function complete_refresh(state, installed_fixture, registry_fixture)
	state:complete_next_command(installed_fixture, 0)
	state:complete_next_command(registry_fixture, 0)
	state:run_next_timer()
end

local function test_finds_registry_updates_and_ignores_local_packages()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "the startup check must show source activity")
	assert(state.commands[1].command[1] == "/bin/cat", "the installed database must be read directly")
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	local brew = assert(state:item("package:brew"), "an outdated registry package must be published")
	assert(brew.body == "0.1.0 → 0.2.0", "the installed and latest versions must be shown")
	assert(state:item_has_action("package:brew", "update"), "an update item must provide an update action")
	assert(state:item("package:local-tool") == nil, "a locally installed package must not be replaced from the registry")
	assert(state:item("package:shared") == nil, "a current package must not be published")
	assert(not state:has_busy_source_action(), "the completed check must clear source activity")
end

local function test_update_runs_the_package_installer_and_rechecks()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.action_handler({ action_id = "update", target_widget_id = "package:brew" })
	assert(state:item_action_is_busy("package:brew", "update"), "the package update must show inline activity")
	local command = state.commands[1].command
	assert(
		table.concat(command, " ") == "/usr/bin/env easybar widgets install brew",
		"the update action must reinstall the selected registry package"
	)

	state:complete_next_command("Installed brew 0.2.0", 0)
	state:run_next_timer()
	assert(state.commands[1].command[1] == "/bin/cat", "a successful update must recheck installed state")
	complete_refresh(state, "inbox-widgets-current", "inbox-widgets-registry")
	assert(state:item("package:brew") == nil, "the updated package must disappear from the inbox")
end

local function test_invalid_registry_retains_the_last_snapshot()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.context_action_handler({ action_id = "refresh" })
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-malformed")
	assert(state:item("package:brew") ~= nil, "a failed check must retain the last good update snapshot")
	assert(state:item("error") ~= nil, "a failed check must publish an error")
end

local function test_configures_the_refresh_interval()
	local state = load_widget({ ["inbox-widgets:refresh_interval_minutes"] = 15 })
	local timer = assert(state.added_items.easybar_package_updates_timer, "the package update timer must exist")
	assert(timer.interval == 15 * 60, "the timer must use the configured refresh interval")
end

test_finds_registry_updates_and_ignores_local_packages()
test_update_runs_the_package_installer_and_rechecks()
test_invalid_registry_retains_the_last_snapshot()
test_configures_the_refresh_interval()

print("Widgets inbox regression checks passed")
