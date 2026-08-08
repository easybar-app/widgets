# EasyBar Widget Updates Inbox

`widget.lua` checks the official EasyBar widget registry and publishes available package updates to EasyBar's native inbox.

Use **Update** on an inbox item to install that package's latest registry release. The source menu also provides a manual **Refresh** action; checks otherwise run every six hours and after wake or session activation.

Only packages whose recorded installation source matches a release in the official registry are checked. Packages installed from a local directory, custom archive, or another registry are left untouched.

## Requirements

The widget requires `curl` and the `easybar` CLI in `[app.env].PATH`.
