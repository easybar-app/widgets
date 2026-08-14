# lazy.nvim Inbox Widget

`widget.lua` checks [lazy.nvim](https://lazy.folke.io/) for available plugin updates and publishes one item per outdated plugin to EasyBar's native inbox.

Each item has an **Update** action. The source context menu can refresh the snapshot, update every outdated plugin, and enable or disable automatic updates. Update actions use Lazy's normal update API and update the Lazy lockfile.

## Requirements

The native inbox must be enabled. Neovim must be available through `[app.env].PATH`, and its normal configuration must set up lazy.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

The standalone menu-bar presentation is the `nvim-lazy` package. Install only one presentation unless duplicate update checks are intentional.

## Configuration

Automatic updates are enabled by default. Every configured interval, the widget checks for plugin updates and installs all available updates. Set `automatic_updates = false` to keep scheduled checks and Inbox notifications without changing installed plugins automatically. Manual item and **Update all** actions remain available.

Configure an interval from 5 minutes to 7 days and optional Inbox ordering, then reload EasyBar:

```toml
[widgets.nvim-lazy-inbox]
automatic_updates = true
refresh_interval_minutes = 60
source_order = 35
context_order = 35
```

`source_order` controls the group when the Inbox is grouped by source. `context_order` controls its position in the Inbox source menu; lower values appear first. The source menu shows and persists the automatic-update toggle.
