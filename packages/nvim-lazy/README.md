# lazy.nvim Updates Widget

`widget.lua` checks for available [lazy.nvim](https://lazy.folke.io/) plugin updates and shows their count in the menu bar. Left-click the widget or choose **Refresh** from its context menu to check again; **Update all** installs every available plugin update.

Scheduled checks can also install updates automatically. Updates run through `require("lazy").update({ wait = true, show = false })`, so Lazy updates the plugins and lockfile through its normal API.

## Requirements

Neovim must be available through `[app.env].PATH`, and its normal configuration must set up lazy.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

## Configuration

Automatic updates are enabled by default. Every configured interval, the widget checks for updates and installs all available plugins. Set `automatic_updates = false` to keep scheduled checks and the update count without changing installed plugins automatically. Manual **Update all** remains available.

The interval accepts values from 1 minute to 24 hours:

```toml
[widgets.nvim-lazy]
automatic_updates = true
refresh_interval_minutes = 30
```

The context menu shows and persists the automatic-update toggle.
