local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local widget_path = root .. "/packages/brew/widget.lua"

--- Loads the standalone Homebrew widget with controlled persisted settings.
local function load_widget(storage)
	storage = storage or {}
	local easybar, state = host.new(root, { storage = storage })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(widget_path, "t", environment)
	assert(chunk, "brew/widget.lua failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, "brew/widget.lua failed during startup: " .. tostring(runtime_error))
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

--- Verifies disabling automatic updates keeps scheduled checks but skips mutations.
local function test_disabled_automatic_updates_check_only()
	local easybar, state, storage = load_widget({ ["brew:automatic_updates"] = false })
	local widget = assert(state:node("brew_outdated"), "Homebrew widget must create its root node")
	assert(#state.commands == 1, "Homebrew must start one initial check")
	assert(state:command_contains(1, "outdated"), "disabled automatic updates must check outdated packages")
	assert(not state:command_contains(1, "update"), "disabled automatic updates must not run brew update")

	state:complete_command(1, '{"formulae":[],"casks":[]}', 0)
	assert(assert(context_action(widget, "toggle_automatic_updates")).title == "Automatic updates: Off")
	assert(storage["brew:automatic_updates"] == false, "Homebrew must retain the disabled automatic-update setting")
end

--- Verifies automatic Homebrew updates default to enabled.
local function test_automatic_updates_default_on()
	local _, state = load_widget()
	assert(#state.commands == 1, "Homebrew must start one automatic cycle")
	assert(state:command_contains(1, "update"), "default automatic updates must start with brew update")
end

test_disabled_automatic_updates_check_only()
test_automatic_updates_default_on()

print("Homebrew widget regression checks passed")
