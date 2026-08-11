# EasyBar Widgets Inbox

`widget.lua` checks the official widget registry and publishes available package updates to the native inbox in EasyBar or EasyBar Native.

Use **Update** on an inbox item to install that package's latest registry release. Use **Refresh**
from the Widgets source menu—or the inbox refresh button—to check immediately. The source menu
also provides **Update all** when updates are available; checks run every six hours and after wake
or session activation. Update actions use the CLI for the active frontend, so the same behavior is
available from the terminal with `easybar widgets update` or `easybar-native widgets update`.

## Configuration

The automatic check interval defaults to six hours and can be set from 5 minutes to 7 days:

```toml
[widgets.inbox-widgets]
refresh_interval_minutes = 360
source_order = 40
context_order = 40
```

Reload the frontend after changing it:

```sh
# EasyBar
easybar config reload

# EasyBar Native
easybar-native config reload
```

`source_order` controls the Widgets group when the inbox is grouped by source. `context_order`
independently controls its position in the inbox source menu. Lower values appear first. The source
context menu shows update availability followed by the active refresh interval, without an extra settings submenu.

Only packages whose recorded installation source matches a release in the official registry are checked. Packages installed from a local directory, custom archive, or another registry are left untouched.

## Requirements

The widget requires EasyBarKit 0.3.2 or newer and `curl`. The active frontend CLI must be available in `[app.env].PATH` so inbox actions can install updates.
