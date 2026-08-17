# GitHub Status Inbox Widget

`widget.lua` publishes active GitHub incidents and scheduled maintenance to the native Inbox in
EasyBar or EasyBar Native. Incident items link to their detailed status pages and retain stable IDs
so native read and dismiss state can be preserved between checks.

The current incident feed comes from GitHub's live Statuspage API.

The source menu supports manual refresh, participates in the Inbox refresh button, displays current
health, and shows a spinner while checking. No authentication is required.

The standalone menu-bar presentation is available as `github-status`. Install both if you want the
compact live indicator and native incident notifications.

## Configuration

Checks run every five minutes by default. Configure an interval from 5 minutes to 7 days and
optional Inbox ordering, then reload the frontend:

```toml
[widgets.github-status-inbox]
refresh_interval_minutes = 5
source_order = 15
context_order = 15
```

`source_order` controls the group position when the Inbox is grouped by source. `context_order`
controls its source-menu position; lower values appear first.

## Requirements

The native Inbox must be enabled and `curl` must be available.
