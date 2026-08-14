local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()
local registry_url = "https://raw.githubusercontent.com/easybar-app/registry/main/index.json"

--- Loads the widget with controlled storage values and returns its test state.
local function load_widget(storage_values, cli_name)
	return host.load(root, easybar_root, "inbox-widgets", storage_values, {
		EASYBAR_INTERNAL_CLI_NAME = cli_name or "easybar",
		EASYBAR_INTERNAL_WIDGET_PACKAGES_DIRECTORY = "/tmp/easybar/packages/active",
	})
end

--- Completes both asynchronous data reads for one widget refresh.
local function complete_refresh(state, installed_fixture, registry_fixture)
	state:complete_next_command(installed_fixture, 0)
	assert(
		state.commands[1].command[#state.commands[1].command] == registry_url,
		"the official registry URL must be used"
	)
	state:complete_next_command(registry_fixture, 0)
	state:run_next_timer()
end

--- Verifies EasyBar Native package checks and updates use its isolated CLI.
local function test_native_frontend_uses_native_package_runtime()
	local state = load_widget(nil, "easybar-native")
	state:run_next_timer()
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar-native widgets installed --json",
		"Native package checks must use the easybar-native CLI"
	)
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.action_handler({ action_id = "update", target_widget_id = "package:brew" })
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar-native widgets update brew",
		"Native update actions must use the easybar-native CLI"
	)
end

--- Verifies registry updates are found while local-only packages are ignored.
local function test_finds_registry_updates_and_ignores_local_packages()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "the startup check must show source activity")
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar widgets installed --json",
		"installed package state must include CLI pin information"
	)
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	local brew = assert(state:item("package:brew"), "an outdated registry package must be published")
	assert(brew.body == "0.1.0 → 0.2.0", "the installed and latest versions must be shown")
	assert(state:item_has_action("package:brew", "update"), "an update item must provide an update action")
	assert(not state:item_has_action(brew.id, "open"), "Widgets must not duplicate the native Open action")
	assert(not state:item_has_action(brew.id, "mark_read"), "Widgets must not duplicate the native read action")
	assert(not state:item_has_action(brew.id, "dismiss"), "Widgets must not duplicate the native Dismiss action")
	assert(state:item("package:local-tool") == nil, "a locally installed package must not be replaced from the registry")
	assert(state:item("package:shared") == nil, "a current package must not be published")
	assert(not state:has_busy_source_action(), "the completed check must clear source activity")
	assert(assert(state:source_action("update_all")).title == "Update all (1)", "the source must offer all updates")
end

--- Verifies pinned package updates remain visible but cannot be started from the inbox.
local function test_pinned_update_is_visible_but_not_actionable()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed-pinned", "inbox-widgets-registry")

	local brew = assert(state:item("package:brew"), "a pinned outdated package must remain visible")
	assert(brew.body == "0.1.0 → 0.2.0 · pinned", "pinned update state must be shown")
	assert(not state:item_has_action("package:brew", "update"), "a pinned package must not offer Update")
	local update_all = assert(state:source_action("update_all"), "the source must report pinned update state")
	assert(update_all.title == "All updates pinned", "bulk update state must explain why no updates are actionable")
	assert(update_all.enabled == false, "bulk update must be disabled when every update is pinned")

	state.action_handler({ action_id = "update", target_widget_id = "package:brew" })
	assert(#state.commands == 0, "a synthetic pinned update action must not invoke the CLI")
	state.context_action_handler({ action_id = "update_all" })
	assert(#state.commands == 0, "bulk update must not run when every update is pinned")
end

--- Verifies a package update invokes the CLI and refreshes update state.
local function test_update_runs_the_package_updater_and_rechecks()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.action_handler({ action_id = "update", target_widget_id = "package:brew" })
	assert(state:item_action_is_busy("package:brew", "update"), "the package update must show inline activity")
	assert(state:has_busy_source_action(), "the package update must show source activity")
	local command = state.commands[1].command
	assert(
		table.concat(command, " ") == "/usr/bin/env easybar widgets update brew",
		"the update action must update the selected registry package"
	)

	state:complete_next_command("Installed brew 0.2.0", 0)
	state:run_next_timer()
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar widgets installed --json",
		"a successful update must recheck installed state"
	)
	complete_refresh(state, "inbox-widgets-current", "inbox-widgets-registry")
	assert(state:item("package:brew") == nil, "the updated package must disappear from the inbox")
end

--- Verifies updating all packages invokes the aggregate CLI update command.
local function test_update_all_uses_the_cli_update_command()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.context_action_handler({ action_id = "update_all" })
	assert(state:has_busy_source_action(), "updating all packages must show source activity")
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar widgets update --all",
		"the source action must use the CLI all-packages update"
	)
end

--- Verifies invalid registry data preserves the last valid update snapshot.
local function test_invalid_registry_retains_the_last_snapshot()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")

	state.context_action_handler({ action_id = "refresh" })
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-malformed")
	assert(state:item("package:brew") ~= nil, "a failed check must retain the last good update snapshot")
	assert(state:item("error") ~= nil, "a failed check must publish an error")
end

--- Verifies manual refresh participates in the native inbox refresh action.
local function test_manual_refresh_rechecks_packages()
	local state = load_widget()
	state:run_next_timer()
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")
	local refresh = assert(state:source_action("refresh"), "Widgets must provide a manual refresh action")
	assert(refresh.title == "Refresh", "the Widgets context menu must label the manual refresh action")
	assert(refresh.include_in_refresh_all == true, "the inbox refresh button must include Widgets")

	state.context_action_handler({ action_id = "refresh" })
	assert(state:has_busy_source_action(), "manual refresh must show source activity")
	assert(
		table.concat(state.commands[1].command, " ") == "/usr/bin/env easybar widgets installed --json",
		"manual refresh must recheck installed packages"
	)
end

--- Verifies that the configured refresh interval controls source metadata and timers.
local function test_configures_the_refresh_interval()
	local state = load_widget({
		["inbox-widgets:refresh_interval_minutes"] = 15,
		["inbox-widgets:source_order"] = 37,
		["inbox-widgets:context_order"] = 38,
	})
	local timer = assert(state.added_items.easybar_package_updates_timer, "the package update timer must exist")
	assert(timer.interval == 15 * 60, "the timer must use the configured refresh interval")
	state:run_next_timer()
	assert(
		type(state.configuration.presentation.icon) == "string",
		"Widgets refresh activity must retain its source icon"
	)
	assert(state.configuration.order == 38, "the Widgets context must use the configured order")
	assert(state:source_action("settings") == nil, "Widgets settings must not add an outer submenu")
	assert(
		assert(state:source_action("refresh_interval")).title == "Refresh every 15 minutes",
		"the Widgets context menu must show the refresh interval"
	)
	complete_refresh(state, "inbox-widgets-installed", "inbox-widgets-registry")
	local refresh = assert(state:source_action("refresh"), "Widgets must provide a manual refresh action")
	assert(refresh.title == "Refresh", "the Widgets context menu must label the manual refresh action")
	assert(refresh.include_in_refresh_all == true, "the inbox refresh button must include Widgets")
	assert(state.configuration.actions[1].id == "refresh", "Widgets manual refresh must be first")
	assert(state.configuration.actions[2].id == "update_all", "Widgets update status must follow refresh")
	assert(state.configuration.actions[3].id == "refresh_interval", "Widgets refresh interval must be top-level")
	assert(assert(state:item("package:brew")).source.order == 37, "the Widgets source must use the configured order")
end

test_finds_registry_updates_and_ignores_local_packages()
test_native_frontend_uses_native_package_runtime()
test_pinned_update_is_visible_but_not_actionable()
test_update_runs_the_package_updater_and_rechecks()
test_update_all_uses_the_cli_update_command()
test_invalid_registry_retains_the_last_snapshot()
test_manual_refresh_rechecks_packages()
test_configures_the_refresh_interval()

print("Widgets inbox regression checks passed")
