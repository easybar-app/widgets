# GitHub Inbox Widget

`widget.lua` publishes GitHub notifications to the native inbox and supports marking notifications read, refreshing, and guarded pull-request merging.

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

Automatic checks run every 5 minutes by default; `refresh_interval_minutes` accepts values from 5 minutes to 7 days. Supported merge methods are `merge`, `squash`, and `rebase`. `confirm_merge = false` performs the merge after the readiness check; set it to `true` to require a second action. The active interval and merge settings appear in the source menu's **Settings** submenu.

`source_order` controls the GitHub group when the inbox is grouped by source. `context_order`
independently controls its position in the inbox source menu. Lower values appear first. The source
context menu groups the active refresh interval and merge settings under **Settings**.

The standalone popup presentation is the `github` package.
