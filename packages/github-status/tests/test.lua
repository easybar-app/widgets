local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local json = require("easybar.json")

local function decode_fixture(value)
	if value == "github-status-active" then
		return json.object({
			status = json.object({ indicator = "minor", description = "Partially Degraded Service" }),
			incidents = json.array({ json.object({ id = "incident-1", impact = "critical" }) }),
			components = json.array({
				json.object({ name = "Actions", status = "degraded_performance" }),
				json.object({ name = "Packages", status = "operational" }),
			}),
		})
	end
	error("unexpected JSON fixture: " .. tostring(value))
end

local easybar, state = host.new(root, { json_decode = decode_fixture })
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local widget_path = root .. "/packages/github-status/widget.lua"
local chunk, load_error = loadfile(widget_path, "t", environment)
assert(chunk, "github-status/widget.lua failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, "github-status/widget.lua failed during startup: " .. tostring(runtime_error))

local widget = assert(state:node("github_status"), "GitHub Status must create its menu-bar item")
local popup_status = assert(state:node("github_status_popup_status"), "GitHub Status must create status details")

assert(#state.commands == 1, "GitHub Status must begin one live status request")
assert(state:command_contains(1, "https://www.githubstatus.com/api/v2/summary.json"))
state:complete_command(1, "github-status-active", 0)
assert(#state.commands == 1, "GitHub Status must only request the live status feed")
assert(widget.props.label.string == "Critical", "GitHub Status must render the current live state")
assert(widget.props.label.color == "theme.error", "critical incidents must override a less severe summary indicator")
assert(popup_status.props.label.string == "GitHub · Partially Degraded Service")

state:emit("github_status", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
assert(widget.props.popup.drawing == true, "left-click must open GitHub status details")
state:emit("github_status", easybar.events.mouse.clicked, { button = easybar.events.mouse.left_button })
assert(widget.props.popup.drawing == false, "a second left-click must close GitHub status details")

state:emit("github_status", easybar.events.context_menu.clicked, { action_id = "refresh" })
state:emit("github_status", easybar.events.context_menu.clicked, { action_id = "refresh" })
assert(#state.commands == 2, "overlapping GitHub status refreshes must coalesce")
state:complete_command(2, "github-status-active", 0)
assert(#state.commands == 3, "one coalesced GitHub status refresh must run after completion")

print("GitHub Status widget regression checks passed")
