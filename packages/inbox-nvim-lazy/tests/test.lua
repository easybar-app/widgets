local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

local function load_widget(storage, environment)
	storage = storage or {}
	if storage["nvim-lazy-inbox:automatic_updates"] == nil then
		storage["nvim-lazy-inbox:automatic_updates"] = false
	end
	return host.load(root, easybar_root, "inbox-nvim-lazy", storage, environment)
end

--- Loads the widget with manifest defaults, including automatic updates enabled.
local function load_widget_with_defaults(environment)
	return host.load(root, easybar_root, "inbox-nvim-lazy", nil, environment)
end

local function test_refresh_publishes_plugin_updates()
	local state = load_widget({
		["nvim-lazy-inbox:refresh_interval_minutes"] = 30,
		["nvim-lazy-inbox:source_order"] = 7,
		["nvim-lazy-inbox:context_order"] = 8,
	}, { NVIM = "/opt/homebrew/bin/nvim" })
	local timer = assert(state.added_items.nvim_lazy_inbox_timer, "the lazy.nvim Inbox timer must exist")
	assert(timer.interval == 30 * 60, "the timer must use the configured refresh interval")

	state:run_next_timer()
	assert(state:has_busy_source_action(), "startup refresh must show source activity")
	assert(state.configuration.order == 8, "the source context must use the configured order")
	assert(state.commands[1].command[1] == "/opt/homebrew/bin/nvim", "the widget must honor NVIM")
	assert(state.commands[1].command[2] == "--headless", "the widget must run Neovim headlessly")
	local check_script = assert(state.commands[1].command[4]):match("^lua%s+(.+)$")
	assert(load(check_script), "the embedded Lazy check must be valid Lua")

	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-two\n", 0)
	state:run_next_timer()
	local first = assert(state:item("plugin:lazy.nvim"), "the first plugin update must be published")
	assert(first.body == "0123456 → fedcba9", "plugin items must show abbreviated revisions")
	assert(first.source.order == 7, "plugin items must use the configured source order")
	assert(first.url == "https://github.com/folke/lazy.nvim", "plugin items must link to their repository")
	assert(state:item_has_action(first.id, "update"), "plugin items must offer an update action")
	assert(assert(state:source_action("update_all")).title == "Update all (2)", "the source must offer Update all")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: Off",
		"the source must expose automatic-update state"
	)
	assert(assert(state:source_action("refresh_interval")).title == "Refresh every 30 minutes")

	state.context_action_handler({ action_id = "update_all" })
	assert(state:has_busy_source_action(), "Update all must show source activity")
	assert(state.commands[1].command[1] == "/usr/bin/env", "Update all must invoke Neovim without a shell")
	assert(state.commands[1].command[2] == "EASYBAR_NVIM_LAZY_PLUGIN=", "Update all must not select one plugin")
end

local function test_item_update_runs_lazy_and_reconciles()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-two\n", 0)
	state:run_next_timer()

	state.action_handler({ action_id = "update", target_widget_id = "plugin:lazy.nvim" })
	assert(state:item_action_is_busy("plugin:lazy.nvim", "update"), "plugin update activity must stay inline")
	assert(state.commands[1].command[1] == "/usr/bin/env", "plugin updates must pass the target without a shell")
	assert(
		state.commands[1].command[2] == "EASYBAR_NVIM_LAZY_PLUGIN=lazy.nvim",
		"plugin updates must target the selected Lazy plugin"
	)
	local update_script = assert(state.commands[1].command[6]):match("^lua%s+(.+)$")
	assert(load(update_script), "the embedded Lazy update must be valid Lua")

	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATED=1\n", 0)
	state:run_next_timer()
	assert(#state.commands == 1, "a successful update must start a reconciliation check")
	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-empty\n", 0)
	state:run_next_timer()
	assert(state:item("plugin:lazy.nvim") == nil, "updated plugins must disappear after reconciliation")
end

local function test_failures_retain_the_last_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-two\n", 0)
	state:run_next_timer()

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("EASYBAR_NVIM_LAZY_ERROR=module 'lazy' not found\n", 1)
	state:run_next_timer()
	assert(state:item("error") ~= nil, "check failures must publish an Inbox error")
	assert(state:item("plugin:lazy.nvim") ~= nil, "check failures must retain the last valid snapshot")
end

local function test_automatic_updates_default_on_and_update_all()
	local state = load_widget_with_defaults()
	state:run_next_timer()
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"lazy.nvim automatic updates must default to on"
	)
	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-two\n", 0)
	state:run_next_timer()
	assert(#state.commands == 1, "an automatic check with updates must start Update all")
	assert(state.commands[1].command[1] == "/usr/bin/env", "automatic updates must invoke Neovim without a shell")
	assert(state.commands[1].command[2] == "EASYBAR_NVIM_LAZY_PLUGIN=", "automatic updates must select all plugins")
end

local function test_automatic_updates_toggle_persists_and_starts_cycle()
	local state = load_widget({ ["nvim-lazy-inbox:automatic_updates"] = false })
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_LAZY_UPDATES=lazy-updates-empty\n", 0)
	state:run_next_timer()

	state.context_action_handler({ action_id = "toggle_automatic_updates" })
	assert(state.storage_values["nvim-lazy-inbox:automatic_updates"] == true, "lazy.nvim must persist automatic updates")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"the source menu must show enabled automatic updates"
	)
	assert(#state.commands == 1, "enabling automatic updates must start a fresh check")
end

test_refresh_publishes_plugin_updates()
test_item_update_runs_lazy_and_reconciles()
test_failures_retain_the_last_snapshot()
test_automatic_updates_default_on_and_update_all()
test_automatic_updates_toggle_persists_and_starts_cycle()

print("lazy.nvim inbox widget regression checks passed")
