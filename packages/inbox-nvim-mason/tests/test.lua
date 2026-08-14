local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/inbox_host.lua"))()

local function load_widget(storage, environment)
	storage = storage or {}
	if storage["nvim-mason-inbox:automatic_updates"] == nil then
		storage["nvim-mason-inbox:automatic_updates"] = false
	end
	return host.load(root, easybar_root, "inbox-nvim-mason", storage, environment)
end

--- Loads the widget with manifest defaults, including automatic updates enabled.
local function load_widget_with_defaults(environment)
	return host.load(root, easybar_root, "inbox-nvim-mason", nil, environment)
end

local function test_refresh_publishes_tool_updates()
	local state = load_widget({
		["nvim-mason-inbox:refresh_interval_minutes"] = 30,
		["nvim-mason-inbox:source_order"] = 7,
		["nvim-mason-inbox:context_order"] = 8,
	}, { NVIM = "/opt/homebrew/bin/nvim" })
	local timer = assert(state.added_items.nvim_mason_inbox_timer, "the Mason Inbox timer must exist")
	assert(timer.interval == 30 * 60, "the Mason timer must use the configured interval")
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Mason startup refresh must show activity")
	assert(state.configuration.order == 8, "the Mason context must use the configured order")
	assert(state.commands[1].command[1] == "/opt/homebrew/bin/nvim", "the widget must honor NVIM")
	local check_script = assert(state.commands[1].command[4]):match("^lua%s+(.+)$")
	assert(load(check_script), "the embedded Mason check must be valid Lua")

	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-two\n", 0)
	state:run_next_timer()
	local first = assert(state:item("package:lua-language-server"), "the Mason update must be published")
	assert(first.body == "3.18.2 → 3.19.0", "the Mason item must show versions")
	assert(first.category == "LSP", "the Mason item must retain its category")
	assert(first.source.order == 7, "the Mason item must use source order")
	assert(first.url == "https://github.com/LuaLS/lua-language-server", "the Mason item must link its homepage")
	assert(state:item_has_action(first.id, "update"), "the Mason item must offer Update")
	assert(assert(state:source_action("update_all")).title == "Update all (2)")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: Off",
		"the Mason source must expose automatic-update state"
	)
	assert(assert(state:source_action("refresh_interval")).title == "Refresh every 30 minutes")

	state.context_action_handler({ action_id = "update_all" })
	assert(state:has_busy_source_action(), "Mason Update all must show source activity")
	assert(state.commands[1].command[1] == "/usr/bin/env", "Mason Update all must invoke Neovim without a shell")
	assert(state.commands[1].command[2] == "EASYBAR_NVIM_MASON_PACKAGE=", "Mason Update all must select every update")
end

local function test_item_update_and_reconciliation()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-two\n", 0)
	state:run_next_timer()
	state.action_handler({ action_id = "update", target_widget_id = "package:lua-language-server" })
	assert(state:item_action_is_busy("package:lua-language-server", "update"), "Mason update must stay inline")
	assert(state.commands[1].command[1] == "/usr/bin/env", "Mason update must pass its target without a shell")
	assert(state.commands[1].command[2] == "EASYBAR_NVIM_MASON_PACKAGE=lua-language-server")
	local update_script = assert(state.commands[1].command[6]):match("^lua%s+(.+)$")
	assert(load(update_script), "the embedded Mason update must be valid Lua")
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATED=1\n", 0)
	state:run_next_timer()
	assert(#state.commands == 1, "a Mason update must trigger reconciliation")
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-empty\n", 0)
	state:run_next_timer()
	assert(state:item("package:lua-language-server") == nil, "updated Mason tools must disappear")
end

local function test_failure_retains_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-two\n", 0)
	state:run_next_timer()
	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("EASYBAR_NVIM_MASON_ERROR=registry unavailable\n", 1)
	state:run_next_timer()
	assert(state:item("error") ~= nil, "Mason failures must publish an error")
	assert(state:item("package:lua-language-server") ~= nil, "Mason failures must retain the last snapshot")
end

local function test_automatic_updates_default_on_and_update_all()
	local state = load_widget_with_defaults()
	state:run_next_timer()
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"Mason automatic updates must default to on"
	)
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-two\n", 0)
	state:run_next_timer()
	assert(#state.commands == 1, "an automatic check with updates must start Update all")
	assert(state.commands[1].command[1] == "/usr/bin/env", "automatic updates must invoke Neovim without a shell")
	assert(state.commands[1].command[2] == "EASYBAR_NVIM_MASON_PACKAGE=", "automatic updates must select all tools")
end

local function test_automatic_updates_toggle_persists_and_starts_cycle()
	local state = load_widget({ ["nvim-mason-inbox:automatic_updates"] = false })
	state:run_next_timer()
	state:complete_next_command("EASYBAR_NVIM_MASON_UPDATES=mason-updates-empty\n", 0)
	state:run_next_timer()

	state.context_action_handler({ action_id = "toggle_automatic_updates" })
	assert(state.storage_values["nvim-mason-inbox:automatic_updates"] == true, "Mason must persist automatic updates")
	assert(
		assert(state:source_action("toggle_automatic_updates")).title == "Automatic updates: On",
		"the Mason source menu must show enabled automatic updates"
	)
	assert(#state.commands == 1, "enabling automatic updates must start a fresh check")
end

test_refresh_publishes_tool_updates()
test_item_update_and_reconciliation()
test_failure_retains_snapshot()
test_automatic_updates_default_on_and_update_all()
test_automatic_updates_toggle_persists_and_starts_cycle()

print("mason.nvim inbox widget regression checks passed")
