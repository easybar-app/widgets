local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local widget_path = root .. "/packages/nvim-lazy/widget.lua"

--- Loads the standalone Lazy widget with controlled persisted settings.
local function load_widget(storage)
	storage = storage or {}
	local easybar, state = host.new(root, { storage = storage })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(widget_path, "t", environment)
	assert(chunk, "nvim-lazy/widget.lua failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, "nvim-lazy/widget.lua failed during startup: " .. tostring(runtime_error))
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
	local easybar, state = load_widget({ ["nvim-lazy:automatic_updates"] = false })
	local widget = assert(state:node("nvim_lazy_updates"), "Lazy widget must create nvim_lazy_updates")
	local popup_status = assert(state:node("nvim_lazy_updates_popup_status"), "Lazy widget must create a popup status")

	assert(#state.commands == 1, "Lazy widget must start one initial update check")
	assert(state:command_contains(1, "nvim"), "Lazy widget must invoke Neovim")
	local lua_command = assert(state.commands[1].command[4], "Lazy widget must pass a Lua check command to Neovim")
	assert(load(lua_command:match("^lua%s+(.+)$") or ""), "Lazy widget must pass syntactically valid check Lua")

	state:complete_command(1, "EASYBAR_LAZY_UPDATES=3\n", 0)
	assert(#state.commands == 1, "disabled automatic updates must not install plugins")
	assert(widget.props.label.string == "3", "Lazy widget must render the available update count")
	assert(popup_status.props.label.string == "Lazy · 3 updates available")
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: Off")
	assert(assert(context_action(widget, "update_all")).title == "Update all (3)")

	state:emit("nvim_lazy_updates", easybar.events.context_menu.clicked, { action_id = "update_all" })
	assert(#state.commands == 2, "manual Update all must start one Lazy update")
	local update_script = assert(state.commands[2].command[4]):match("^lua%s+(.+)$")
	assert(load(update_script), "Lazy widget must pass syntactically valid update Lua")
	state:complete_command(2, "EASYBAR_LAZY_UPDATED=1\n", 0)
	assert(#state.commands == 3, "a Lazy update must trigger one reconciliation check")
end

--- Verifies automatic updates default on and install discovered plugin updates.
local function test_automatic_updates_default_on()
	local _, state = load_widget()
	local widget = assert(state:node("nvim_lazy_updates"))
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: On")

	state:complete_command(1, "EASYBAR_LAZY_UPDATES=2\n", 0)
	assert(#state.commands == 2, "default automatic updates must install discovered plugins")
	assert(state:command_contains(2, "nvim"), "automatic Lazy updates must run through Neovim")
	state:complete_command(2, "EASYBAR_LAZY_UPDATED=1\n", 0)
	assert(#state.commands == 3, "automatic Lazy updates must reconcile the update count")
	state:complete_command(3, "EASYBAR_LAZY_UPDATES=0\n", 0)
	assert(widget.props.label.string == "", "reconciliation must clear the completed update count")
end

--- Verifies the context toggle persists and starts an automatic cycle when enabled.
local function test_automatic_updates_toggle_persists()
	local storage = { ["nvim-lazy:automatic_updates"] = false }
	local easybar, state = load_widget(storage)
	local widget = assert(state:node("nvim_lazy_updates"))
	state:complete_command(1, "EASYBAR_LAZY_UPDATES=0\n", 0)

	state:emit("nvim_lazy_updates", easybar.events.context_menu.clicked, { action_id = "toggle_automatic_updates" })
	assert(storage["nvim-lazy:automatic_updates"] == true, "Lazy widget must persist automatic updates")
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: On")
	assert(#state.commands == 2, "enabling automatic updates must start a fresh check")
end

--- Verifies overlapping manual checks still coalesce.
local function test_manual_refreshes_coalesce()
	local easybar, state = load_widget({ ["nvim-lazy:automatic_updates"] = false })
	local widget = assert(state:node("nvim_lazy_updates"))
	state:complete_command(1, "EASYBAR_LAZY_UPDATES=1\n", 0)

	state:emit("nvim_lazy_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
	state:emit("nvim_lazy_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
	assert(#state.commands == 2, "Lazy widget must coalesce overlapping update checks")
	state:complete_command(2, "EASYBAR_LAZY_UPDATES=0\n", 0)
	assert(#state.commands == 3, "Lazy widget must run one coalesced follow-up check")
	state:complete_command(3, "EASYBAR_LAZY_ERROR=module 'lazy' not found\n", 1)
	assert(widget.props.label.string == "!", "Lazy widget must expose check failures")
end

test_disabled_automatic_updates_keep_manual_control()
test_automatic_updates_default_on()
test_automatic_updates_toggle_persists()
test_manual_refreshes_coalesce()

print("Lazy widget regression checks passed")
