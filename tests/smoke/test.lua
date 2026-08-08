local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local package_name = assert(arg[3], "package name argument is required")
local entrypoint = assert(arg[4], "entrypoint argument is required")

local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)
local easybar = host.new(root)
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local path = root .. "/packages/" .. package_name .. "/" .. entrypoint
local chunk, load_error = loadfile(path, "t", environment)
assert(chunk, package_name .. " failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, package_name .. " failed during startup: " .. tostring(runtime_error))

print(package_name .. " package smoke check passed")
