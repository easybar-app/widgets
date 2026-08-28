# Shared Lua Libraries

This library package exports the reusable modules used by the official EasyBar widgets:

- `text` for trimming and bounded display text
- `retry` for cancellable asynchronous retry, transient-network detection, and a shared 2/5/10-second
  network backoff policy
- `inbox` for inbox JSON boundaries, bounded errors, and timestamps

These modules are dependencies, not widget entrypoints. The package manager should install them only as part of a resolved dependency graph.
