# GitHub Status Widget

`widget.lua` uses GitHub's live Statuspage API to show the current service state, active incident
count, and number of degraded components.

The icon color and label represent the live state. Click the widget to show details. Its context
menu can refresh the data or open GitHub Status.

The native-inbox presentation is available as `inbox-github-status`. Install both if you want the
compact menu-bar overview and native incident notifications.

## Configuration

Checks run every 15 minutes by default. Configure an interval from 5 minutes to 24 hours and reload
the frontend:

```toml
[widgets.github-status]
refresh_interval_minutes = 15
```

## Requirements

`curl` must be available. Authentication is not required.
