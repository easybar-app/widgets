# GitHub Inbox Widget

`widget.lua` publishes GitHub notifications to the native inbox and supports refreshing and guarded pull-request merging. EasyBar's native **Read** and **Mark all read** controls also mark the corresponding notification threads read on GitHub, without adding a duplicate widget action.

## Requirements

Authenticate the GitHub CLI and make `gh` available through `[app.env].PATH`:

```sh
gh auth login
```

## Merge settings

```toml
[widgets.github-inbox]
refresh_interval_minutes = 5
source_order = 10
context_order = 10
merge_method = "squash"
confirm_merge = false
```

Automatic checks run every 5 minutes by default; `refresh_interval_minutes` accepts values from 5 minutes to 7 days. Supported merge methods are `merge`, `squash`, and `rebase`. `confirm_merge = false` performs the merge after the readiness check; set it to `true` to require a second action. The active interval, merge method, and merge configuration appear directly in the source menu.

`source_order` controls the GitHub group when the inbox is grouped by source. `context_order`
independently controls its position in the inbox source menu. Lower values appear first. The source
context menu keeps the active refresh interval and merge settings at the top level.

The standalone popup presentation is the `github` package.

Remote read synchronization requires EasyBar 0.50.0 or newer and an authenticated GitHub CLI token
with notification access.
