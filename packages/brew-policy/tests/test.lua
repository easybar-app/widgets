local root = assert(arg[1], "repository root argument is required")

package.path = table.concat({
	root .. "/packages/brew-policy/?.lua",
	package.path,
}, ";")

local policy = require("brew_policy")

assert(not policy.is_upgradeable("cask", "docker"), "Docker must require a manual upgrade")
assert(
	policy.reason("cask", "docker") == "Update through Docker Desktop",
	"Docker must retain its manual-upgrade reason"
)
assert(not policy.is_upgradeable("cask", "orbstack@beta"), "versioned OrbStack casks must match")
assert(policy.is_upgradeable("cask", "firefox"), "unlisted casks must remain upgradeable")
assert(policy.is_upgradeable("formula", "lua"), "unlisted formulae must remain upgradeable")
assert(policy.rule("unknown", "docker") == nil, "unknown package kinds must have no policy")

print("Homebrew policy library checks passed")
