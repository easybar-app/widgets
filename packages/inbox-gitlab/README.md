# GitLab Inbox Widget

`widget.lua` publishes assigned GitLab issues and merge requests to the native inbox and supports local read state, refresh, and guarded merge-request merging.

## Requirements

Authenticate the GitLab CLI and make `glab` available through `[app.env].PATH`:

```sh
glab auth login
```

Set `GITLAB_HOST` in `[app.env]` for a self-managed or dedicated instance.

## Merge settings

```toml
[widgets.gitlab-inbox]
refresh_interval_minutes = 5
source_order = 20
context_order = 20
merge_method = "merge"
confirm_merge = false
```

Automatic checks run every 5 minutes by default; `refresh_interval_minutes` accepts values from 5 minutes to 7 days. Supported merge methods are `merge`, `squash`, and `rebase`. `merge` uses the project's configured strategy. Set `confirm_merge = true` to require a second action after the readiness check. The active interval and merge settings appear in the source menu's **Settings** submenu.

`source_order` controls the GitLab group when the inbox is grouped by source. `context_order`
independently controls its position in the inbox source menu. Lower values appear first. The source
context menu groups the active refresh interval and merge settings under **Settings**.

The standalone popup presentation is the `gitlab` package.
