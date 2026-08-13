-- Shared host and fixtures for native-inbox widget regression tests.

local M = {}
local configured_root
local json
local inbox_module

local function configure(root, easybar_kit_root)
	local configuration_key = root .. "\0" .. easybar_kit_root
	if configured_root == configuration_key then
		return
	end

	package.path = table.concat({
		root .. "/packages/brew-policy/?.lua",
		root .. "/packages/shared/?.lua",
		root .. "/packages/shared/?/init.lua",
		root .. "/packages/?.lua",
		easybar_kit_root .. "/Sources/EasyBarKit/Lua/?.lua",
		easybar_kit_root .. "/Sources/EasyBarKit/Lua/?/init.lua",
		package.path,
	}, ";")

	json = require("easybar.json")
	inbox_module = require("inbox")
	configured_root = configuration_key
end

local function github_notification(id, title, updated_at)
	return json.object({
		id = id,
		reason = "mention",
		updated_at = updated_at,
		repository = json.object({
			full_name = "easybar/easybar",
			html_url = "https://github.com/easybar/easybar",
		}),
		subject = json.object({
			title = title,
			type = "PullRequest",
			url = "https://api.github.com/repos/easybar/easybar/pulls/1",
		}),
	})
end

local function gitlab_issue(id)
	return json.object({
		id = id,
		iid = id,
		title = "Assigned issue " .. tostring(id),
		updated_at = "2026-08-03T09:45:00.123+00:00",
		references = json.object({ full = "easybar/easybar#" .. tostring(id) }),
		web_url = "https://gitlab.com/easybar/easybar/-/issues/" .. tostring(id),
	})
end

local function gitlab_merge_request(id)
	return json.object({
		id = id,
		iid = id,
		project_id = 123,
		title = "Assigned merge request " .. tostring(id),
		updated_at = "2026-08-03T09:46:00Z",
		references = json.object({ full = "easybar/easybar!" .. tostring(id) }),
		web_url = "https://gitlab.com/easybar/easybar/-/merge_requests/" .. tostring(id),
	})
end

local function callable_noop()
	return setmetatable({}, { __call = function() end })
end

local function installed_package(name, version, kind, source)
	return json.object({
		name = name,
		version = version,
		kind = kind,
		entrypoint = kind == "widget" and "widget.lua" or json.null,
		dependencies = json.object({}),
		exports = json.object({}),
		source = source,
	})
end

local function registry_package(name, latest, releases)
	local versions = json.array({})
	for _, release in ipairs(releases) do
		versions[#versions + 1] = json.object({
			version = release.version,
			archive = release.archive,
			sha256 = string.rep("a", 64),
		})
	end
	return json.object({
		name = name,
		latest = latest,
		kind = name == "shared" and "library" or "widget",
		description = name,
		categories = json.array({}),
		versions = versions,
	})
end

local function widget_release(name, version)
	return "https://github.com/easybar-app/widgets/releases/download/"
		.. name
		.. "-v"
		.. version
		.. "/"
		.. name
		.. ".tar.gz"
end

local function decoded_fixture(value)
	if value == "github-one" then
		return json.array({ json.array({ github_notification("thread-1", "Review requested", "2026-08-03T09:45:00Z") }) })
	elseif value == "github-two" then
		return json.array({
			json.array({
				github_notification("thread-1", "First review", "2026-08-03T09:45:00Z"),
				github_notification("thread-2", "Second review", "2026-08-03T09:46:00Z"),
			}),
		})
	elseif value == "github-second" then
		return json.array({ json.array({ github_notification("thread-2", "Second review", "2026-08-03T09:46:00Z") }) })
	elseif value == "github-empty" then
		return json.array({ json.array({}) })
	elseif value == "github-object" then
		return json.object({ message = "not an array" })
	elseif value == "github-pr-ready" then
		return json.object({
			state = "OPEN",
			isDraft = false,
			mergeable = "MERGEABLE",
			mergeStateStatus = "CLEAN",
			reviewDecision = "APPROVED",
			headRefOid = "0123456789abcdef",
		})
	elseif value == "gitlab-issues" then
		return json.array({ gitlab_issue(1) })
	elseif value == "gitlab-merge-requests" then
		return json.array({ gitlab_merge_request(2) })
	elseif value == "gitlab-mr-ready" then
		return json.object({
			state = "opened",
			draft = false,
			detailed_merge_status = "mergeable",
			sha = "fedcba9876543210",
		})
	elseif value == "gitlab-empty" then
		return json.array({})
	elseif value == "gitlab-object" then
		return json.object({ message = "not an array" })
	elseif value:find("brew%-one", 1, false) ~= nil then
		return json.object({
			formulae = json.array({
				json.object({
					name = "easybar",
					installed_versions = json.array({ "1.0.0" }),
					current_version = "1.1.0",
					pinned = false,
				}),
			}),
			casks = json.array({}),
		})
	elseif value:find("brew%-empty", 1, false) ~= nil then
		return json.object({ formulae = json.array({}), casks = json.array({}) })
	elseif value:find("brew%-malformed", 1, false) ~= nil then
		return json.object({ formulae = json.object({}) })
	elseif value == "inbox-widgets-installed" or value == "inbox-widgets-current" then
		local brew_version = value == "inbox-widgets-current" and "0.2.0" or "0.1.0"
		return json.object({
			layout_version = 2,
			packages = json.array({
				installed_package("brew", brew_version, "widget", widget_release("brew", brew_version)),
				installed_package("shared", "0.1.0", "library", widget_release("shared", "0.1.0")),
				installed_package("local-tool", "0.1.0", "widget", "/tmp/local-tool"),
			}),
		})
	elseif value == "inbox-widgets-registry" then
		return json.object({
			registry_version = 1,
			packages = json.array({
				registry_package("brew", "0.2.0", {
					{ version = "0.1.0", archive = widget_release("brew", "0.1.0") },
					{ version = "0.2.0", archive = widget_release("brew", "0.2.0") },
				}),
				registry_package("shared", "0.1.0", {
					{ version = "0.1.0", archive = widget_release("shared", "0.1.0") },
				}),
				registry_package("local-tool", "9.0.0", {
					{ version = "0.1.0", archive = widget_release("local-tool", "0.1.0") },
					{ version = "9.0.0", archive = widget_release("local-tool", "9.0.0") },
				}),
			}),
		})
	elseif value == "inbox-widgets-malformed" then
		return json.object({ registry_version = 1, packages = json.object({}) })
	elseif value == "lazy-updates-two" then
		return json.array({
			json.object({
				name = "lazy.nvim",
				from = "0123456789abcdef",
				to = "fedcba9876543210",
				url = "https://github.com/folke/lazy.nvim.git",
			}),
			json.object({
				name = "plenary.nvim",
				from = "1111111111111111",
				to = "2222222222222222",
				url = "https://github.com/nvim-lua/plenary.nvim.git",
			}),
		})
	elseif value == "lazy-updates-empty" then
		return json.array({})
	end

	error("unexpected JSON fixture: " .. tostring(value))
end

local function make_host(root, package_name, initial_storage_values)
	local state = {
		configuration = nil,
		items = {},
		action_handler = nil,
		context_action_handler = nil,
		commands = {},
		timers = {},
		storage_values = initial_storage_values or {},
		added_items = {},
		next_token = 0,
	}

	local inbox = {}
	function inbox.configure(_, configuration)
		state.configuration = configuration
	end
	function inbox.replace(_, items)
		state.items = items
	end
	function inbox.clear()
		state.items = {}
	end
	function inbox.on_action(_, handler)
		state.action_handler = handler
	end
	function inbox.on_context_action(_, handler)
		state.context_action_handler = handler
	end

	local easybar = {
		kind = { item = "item" },
		level = { trace = "trace", debug = "debug", info = "info", warn = "warn", error = "error" },
		events = {
			forced = "forced",
			system_woke = "system_woke",
			session_active = "session_active",
		},
		json = { decode = decoded_fixture, is_array = json.is_array, null = json.null },
		log = callable_noop(),
		inbox = inbox,
		storage = {
			get = function(widget, key, default)
				local value = state.storage_values[widget .. ":" .. key]
				return value == nil and default or value
			end,
			set = function(widget, key, value)
				state.storage_values[widget .. ":" .. key] = value
				return true, nil
			end,
		},
	}

	function easybar.asset(path)
		path = tostring(path)
		if path:sub(1, 2) == "@/" then
			path = path:sub(3)
		end
		return root .. "/packages/" .. package_name .. "/" .. path
	end

	function easybar.add(_, name, props)
		state.added_items[name] = props
		return { subscribe = function() end }
	end

	function easybar.after(delay, callback)
		local timer = { delay = delay, callback = callback, cancelled = false }
		function timer:cancel()
			self.cancelled = true
		end
		state.timers[#state.timers + 1] = timer
		return timer
	end

	function easybar.spawn_async(command, options, callback)
		state.next_token = state.next_token + 1
		local token = "command-" .. tostring(state.next_token)
		state.commands[#state.commands + 1] = {
			token = token,
			command = command,
			options = options,
			callback = callback,
		}
		return token
	end

	function easybar.cancel_async()
		return true
	end

	function state:run_next_timer()
		while #self.timers > 0 do
			local timer = table.remove(self.timers, 1)
			if not timer.cancelled then
				timer.callback()
				return
			end
		end
		error("expected a pending timer")
	end

	function state:complete_next_command(output, code)
		return self:complete_command(1, output, code)
	end

	function state:complete_command(index, output, code)
		local command = table.remove(self.commands, index)
		assert(command ~= nil, "expected a pending command")
		command.callback(output, code, { duration_ms = 1 })
		return command
	end

	function state:has_busy_source_action()
		for _, action in ipairs((self.configuration or {}).actions or {}) do
			if action.busy == true then
				return true
			end
		end
		return false
	end

	function state:item(id)
		for _, item in ipairs(self.items) do
			if item.id == id then
				return item
			end
		end
		return nil
	end

	function state:item_action_is_busy(item_id, action_id)
		local item = self:item(item_id)
		if item == nil then
			return false
		end
		for _, action in ipairs(item.actions or {}) do
			if action.id == action_id then
				return action.busy == true
			end
		end
		return false
	end

	function state:item_has_action(item_id, action_id)
		local item = self:item(item_id)
		for _, action in ipairs(item and item.actions or {}) do
			if action.id == action_id then
				return true
			end
		end
		return false
	end

	function state:source_action(action_id)
		local function find(actions)
			for _, action in ipairs(actions or {}) do
				if action.id == action_id then
					return action
				end
				local nested = find(action.children)
				if nested ~= nil then
					return nested
				end
			end
			return nil
		end
		return find((self.configuration or {}).actions)
	end

	return easybar, state
end

--- Loads one widget with isolated host state and optional process-environment overrides.
function M.load(root, easybar_kit_root, package_name, initial_storage_values, environment_values)
	configure(root, easybar_kit_root)
	local easybar, state = make_host(root, package_name, initial_storage_values)
	local path = root .. "/packages/" .. package_name .. "/widget.lua"
	local runtime_os = setmetatable({
		getenv = function(name)
			if environment_values ~= nil and environment_values[name] ~= nil then
				return environment_values[name]
			end
			return os.getenv(name)
		end,
	}, { __index = os })
	local environment = setmetatable({ easybar = easybar, os = runtime_os }, { __index = _G })
	local chunk, load_error = loadfile(path, "t", environment)
	assert(chunk, package_name .. " failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, package_name .. " failed during startup: " .. tostring(runtime_error))
	return state
end

function M.modules(root, easybar_kit_root)
	configure(root, easybar_kit_root)
	return json, inbox_module
end

return M
