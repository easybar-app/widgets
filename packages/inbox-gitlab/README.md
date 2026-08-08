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
merge_method = "merge"
confirm_merge = false
```

Automatic checks run every 5 minutes by default; `refresh_interval_minutes` accepts values from 5 minutes to 7 days. Supported merge methods are `merge`, `squash`, and `rebase`. `merge` uses the project's configured strategy. Set `confirm_merge = true` to require a second action after the readiness check. The merge settings can also be changed from the inbox source menu.

The source context menu shows the active refresh interval.

The standalone popup presentation is the `gitlab` package.
