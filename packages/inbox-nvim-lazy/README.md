# lazy.nvim Inbox Widget

`widget.lua` checks [lazy.nvim](https://lazy.folke.io/) for available plugin updates and publishes one item per outdated plugin to EasyBar's native inbox.

Each item has an **Update** action. The source context menu can refresh the snapshot or update every outdated plugin. Refreshing only fetches and compares plugin revisions; update actions intentionally update plugins and the Lazy lockfile through Lazy's normal update API.

## Requirements

The native inbox must be enabled. Neovim must be available through `[app.env].PATH`, and its normal configuration must set up lazy.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

The standalone menu-bar presentation is the `nvim-lazy` package. Install only one presentation unless duplicate update checks are intentional.

## Configuration

Automatic checks run every 60 minutes by default. Configure an interval from 5 minutes to 7 days and optional Inbox ordering, then reload EasyBar:

```toml
[widgets.nvim-lazy-inbox]
refresh_interval_minutes = 60
source_order = 35
context_order = 35
```

`source_order` controls the group when the Inbox is grouped by source. `context_order` controls its position in the Inbox source menu; lower values appear first.
