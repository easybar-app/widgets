local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local easybar, state = host.new(root)
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local path = root .. "/packages/nvim-lazy/widget.lua"
local chunk, load_error = loadfile(path, "t", environment)
assert(chunk, "nvim-lazy/widget.lua failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, "nvim-lazy/widget.lua failed during startup: " .. tostring(runtime_error))

local widget = assert(state:node("nvim_lazy_updates"), "Lazy widget must create nvim_lazy_updates")
local popup_status = assert(state:node("nvim_lazy_updates_popup_status"), "Lazy widget must create a popup status")

assert(#state.commands == 1, "Lazy widget must start one initial update check")
assert(state:command_contains(1, "nvim"), "Lazy widget must invoke Neovim")
assert(state:command_contains(1, "--headless"), "Lazy widget must run Neovim headlessly")
local lua_command = assert(state.commands[1].command[4], "Lazy widget must pass a Lua check command to Neovim")
local check_chunk, check_syntax_error = load(lua_command:match("^lua%s+(.+)$") or "")
assert(check_chunk, "Lazy widget must pass syntactically valid Lua to Neovim: " .. tostring(check_syntax_error))
assert(widget.props.icon.string == "󰑐", "Lazy widget must show a refresh icon while checking")

state:complete_command(1, "EASYBAR_LAZY_UPDATES=3\n", 0)
assert(widget.props.icon.string == "󰒲", "Lazy widget must restore its Lazy icon after checking")
assert(widget.props.label.string == "3", "Lazy widget must render the available update count")
assert(
	popup_status.props.label.string == "Lazy · 3 updates available",
	"Lazy widget must describe available updates in its popup"
)

state:emit("nvim_lazy_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
assert(widget.props.icon.string == "󰑐", "Lazy widget must show its refresh icon during manual checks")
state:emit("nvim_lazy_updates", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
assert(#state.commands == 2, "Lazy widget must coalesce overlapping update checks")

state:complete_command(2, "EASYBAR_LAZY_UPDATES=0\n", 0)
assert(#state.commands == 3, "Lazy widget must run one coalesced follow-up check")
state:complete_command(3, "EASYBAR_LAZY_ERROR=module 'lazy' not found\n", 1)
assert(widget.props.label.string == "!", "Lazy widget must expose check failures in the menu bar")
assert(popup_status.props.label.string == "Lazy · Check failed", "Lazy widget must expose check failures in its popup")

print("Lazy widget regression checks passed")
