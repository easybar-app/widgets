# mason.nvim Updates Widget

`widget.lua` refreshes the [mason.nvim](https://github.com/mason-org/mason.nvim) registry and shows how many installed tools have updates. Left-click the widget or choose **Refresh** from its context menu to check again; **Update all** installs every available tool update.

Scheduled checks can also install updates automatically through Mason's normal package installer. Mason updates may invoke external package managers required by individual tools.

## Requirements

Neovim must be available through `[app.env].PATH`, and its normal configuration must set up mason.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

## Configuration

Automatic updates are enabled by default. Every configured interval, the widget refreshes Mason's registry, checks installed tools, and installs every available update. Set `automatic_updates = false` to keep scheduled checks and the update count without changing installed tools automatically. Manual **Update all** remains available.

The interval accepts values from 5 minutes to 24 hours:

```toml
[widgets.nvim-mason]
automatic_updates = true
refresh_interval_minutes = 30
```

The context menu shows and persists the automatic-update toggle.

The native Inbox presentation is available separately as `inbox-nvim-mason`. Install only one presentation unless duplicate registry refreshes are intentional.
