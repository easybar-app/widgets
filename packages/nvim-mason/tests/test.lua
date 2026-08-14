local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local widget_path = root .. "/packages/nvim-mason/widget.lua"

--- Loads the standalone Mason widget with controlled persisted settings.
local function load_widget(storage)
	storage = storage or {}
	local easybar, state = host.new(root, { storage = storage })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(widget_path, "t", environment)
	assert(chunk, "nvim-mason/widget.lua failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, "nvim-mason/widget.lua failed during startup: " .. tostring(runtime_error))
	return easybar, state, storage
end

--- Finds one current widget context-menu action.
local function context_action(widget, id)
	for _, action in ipairs(widget.props.context_menu or {}) do
		if action.id == id then
			return action
		end
	end
	return nil
end

--- Verifies disabled automatic updates retain check-only behavior and manual updating.
local function test_disabled_automatic_updates_keep_manual_control()
	local easybar, state = load_widget({ ["nvim-mason:automatic_updates"] = false })
	local widget = assert(state:node("nvim_mason_updates"), "Mason widget must create nvim_mason_updates")
	local popup = assert(state:node("nvim_mason_updates_popup_status"), "Mason widget must create its popup")

	assert(#state.commands == 1, "Mason widget must start one initial update check")
	assert(state:command_contains(1, "nvim"), "Mason widget must invoke Neovim")
	local check_script = assert(state.commands[1].command[4]):match("^lua%s+(.+)$")
	assert(load(check_script), "Mason widget must pass valid check Lua to Neovim")

	state:complete_command(1, "EASYBAR_NVIM_MASON_UPDATES=2\n", 0)
	assert(#state.commands == 1, "disabled automatic updates must not install Mason tools")
	assert(widget.props.label.string == "2", "Mason widget must render the update count")
	assert(popup.props.label.string == "Mason · 2 updates available")
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: Off")
	assert(assert(context_action(widget, "update_all")).title == "Update all (2)")

	state:emit("nvim_mason_updates", easybar.events.context_menu.clicked, { action_id = "update_all" })
	assert(#state.commands == 2, "manual Update all must start one Mason update")
	local update_script = assert(state.commands[2].command[4]):match("^lua%s+(.+)$")
	assert(load(update_script), "Mason widget must pass valid update Lua to Neovim")
	state:complete_command(2, "EASYBAR_NVIM_MASON_UPDATED=2\n", 0)
	assert(#state.commands == 3, "a Mason update must trigger one reconciliation check")
end

--- Verifies automatic updates default on and install discovered tool updates.
local function test_automatic_updates_default_on()
	local _, state = load_widget()
	local widget = assert(state:node("nvim_mason_updates"))
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: On")

	state:complete_command(1, "EASYBAR_NVIM_MASON_UPDATES=2\n", 0)
	assert(#state.commands == 2, "default automatic updates must install discovered Mason tools")
	assert(state:command_contains(2, "nvim"), "automatic Mason updates must run through Neovim")
	state:complete_command(2, "EASYBAR_NVIM_MASON_UPDATED=2\n", 0)
	assert(#state.commands == 3, "automatic Mason updates must reconcile the update count")
	state:complete_command(3, "EASYBAR_NVIM_MASON_UPDATES=0\n", 0)
	assert(widget.props.label.string == "", "reconciliation must clear the completed update count")
end

--- Verifies the context toggle persists and starts an automatic cycle when enabled.
local function test_automatic_updates_toggle_persists()
	local storage = { ["nvim-mason:automatic_updates"] = false }
	local easybar, state = load_widget(storage)
	local widget = assert(state:node("nvim_mason_updates"))
	state:complete_command(1, "EASYBAR_NVIM_MASON_UPDATES=0\n", 0)

	state:emit("nvim_mason_updates", easybar.events.context_menu.clicked, { action_id = "toggle_automatic_updates" })
	assert(storage["nvim-mason:automatic_updates"] == true, "Mason widget must persist automatic updates")
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: On")
	assert(#state.commands == 2, "enabling automatic updates must start a fresh check")
end

--- Verifies overlapping manual checks still coalesce.
local function test_manual_refreshes_coalesce()
	local easybar, state = load_widget({ ["nvim-mason:automatic_updates"] = false })
	local widget = assert(state:node("nvim_mason_updates"))
	state:complete_command(1, "EASYBAR_NVIM_MASON_UPDATES=1\n", 0)

	state:emit("nvim_mason_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
	state:emit("nvim_mason_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
	assert(#state.commands == 2, "Mason widget must coalesce overlapping checks")
	state:complete_command(2, "EASYBAR_NVIM_MASON_UPDATES=0\n", 0)
	assert(#state.commands == 3, "Mason widget must run one coalesced follow-up check")
	state:complete_command(3, "EASYBAR_NVIM_MASON_ERROR=registry unavailable\n", 1)
	assert(widget.props.label.string == "!", "Mason widget must expose check failures")
end

test_disabled_automatic_updates_keep_manual_control()
test_automatic_updates_default_on()
test_automatic_updates_toggle_persists()
test_manual_refreshes_coalesce()

print("mason.nvim widget regression checks passed")
