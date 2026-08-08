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
merge_method = "squash"
confirm_merge = false
```

Automatic checks run every 5 minutes by default; `refresh_interval_minutes` accepts values from 5 minutes to 7 days. Supported merge methods are `merge`, `squash`, and `rebase`. `confirm_merge = false` performs the merge after the readiness check; set it to `true` to require a second action. The merge settings can also be changed from the inbox source menu.

The source context menu shows the active refresh interval.

The standalone popup presentation is the `github` package.
