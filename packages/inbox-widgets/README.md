# EasyBar Widgets Inbox

`widget.lua` checks the official EasyBar widget registry and publishes available package updates to EasyBar's native inbox.

Use **Update** on an inbox item to install that package's latest registry release. The source menu provides **Update all** and a manual **Refresh** action; checks otherwise run every six hours and after wake or session activation. These actions use `easybar widgets update`, so the same update behavior is available from the terminal.

## Configuration

The automatic check interval defaults to six hours and can be set from 5 minutes to 7 days:

```toml
[widgets.inbox-widgets]
refresh_interval_minutes = 360
source_order = 40
context_order = 40
```

Reload EasyBar after changing it:

```sh
easybar config reload
```

`source_order` controls the Widgets group when the inbox is grouped by source. `context_order`
independently controls its position in the inbox source menu. Lower values appear first. The source
context menu also shows the active refresh interval.

Only packages whose recorded installation source matches a release in the official registry are checked. Packages installed from a local directory, custom archive, or another registry are left untouched.

If you installed the former `inbox-widget-updates` 0.1.0 package, remove it before installing this renamed package:

```sh
easybar widgets uninstall inbox-widget-updates
```

## Requirements

The widget requires EasyBar 0.45.0 or newer, plus `curl` and the `easybar` CLI in `[app.env].PATH`.
