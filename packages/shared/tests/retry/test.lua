local root = assert(arg[1], "repository root argument is required")
local easybar_root = assert(arg[2], "EasyBar repository root argument is required")
local host = assert(loadfile(root .. "/tests/support/widget_host.lua"))()
host.configure(root, easybar_root)

local retry = require("retry")

local network_backoff = retry.network_backoff_delays()
assert(#network_backoff == 3, "network backoff must provide three retry delays")
assert(
	network_backoff[1] == 2 and network_backoff[2] == 5 and network_backoff[3] == 10,
	"network backoff must use 2/5/10 seconds"
)
network_backoff[1] = 99
assert(retry.network_backoff_delays()[1] == 2, "network backoff callers must receive independent copies")

local transient_errors = {
	"dial tcp 10.0.1.201:443: connect: no route to host",
	"connect: network is unreachable",
	"connection refused",
	"connection reset by peer",
	"could not resolve host",
	"i/o timeout",
	"TLS handshake timeout",
	"unexpected EOF",
}
for _, message in ipairs(transient_errors) do
	assert(retry.is_transient_network_error(message, 1), "expected transient network error: " .. message)
end
assert(not retry.is_transient_network_error("authentication failed", 1), "authentication failures must not be retried")
assert(not retry.is_transient_network_error("success mentions timeout", 0), "successful commands must never be retried")
assert(not retry.is_transient_network_error("no route to host", 130), "cancelled commands must never be retried")

local easybar, state = host.new(root)
local completed
local attempts = 0

local operation = retry.run(easybar, {
	delays = { 2 },
	--- Simulates a transient failure followed by a successful retry.
	attempt = function(done)
		attempts = attempts + 1
		return easybar.spawn_async({ "probe" }, {}, done)
	end,
	should_retry = retry.is_transient_network_error,
	--- Captures the completed retry result for assertions.
	on_complete = function(output, code, count, metadata)
		completed = { output = output, code = code, count = count, duration_ms = metadata.duration_ms }
	end,
})

assert(operation:is_active(), "retry operation must start active")
assert(attempts == 1, "retry operation must start immediately")
state:complete_command(1, "i/o timeout", 1)
assert(#state.timers == 1, "transient failure must schedule one backoff timer")
assert(state.timers[1].delay == 2, "retry operation must use the declared delay")
state.timers[1].callback()
assert(attempts == 2, "backoff timer must start the second attempt")
state:complete_command(2, "success mentions timeout", 0)

assert(not operation:is_active(), "successful retry operation must complete")
assert(completed.output == "success mentions timeout", "completion must receive final output")
assert(completed.code == 0 and completed.count == 2, "completion must report status and attempt count")
assert(completed.duration_ms == 2002, "completion must include command and backoff duration")

print("Shared retry regression checks passed")
