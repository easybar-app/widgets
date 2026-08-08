# Shared Lua Libraries

This library package exports the reusable modules used by the official EasyBar widgets:

- `text` for trimming and bounded display text
- `retry` for cancellable asynchronous retry with backoff
- `inbox` for inbox JSON boundaries, bounded errors, and timestamps

These modules are dependencies, not widget entrypoints. The package manager should install them only as part of a resolved dependency graph.
