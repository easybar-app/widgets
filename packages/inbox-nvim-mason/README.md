# mason.nvim Inbox Widget

`widget.lua` refreshes the [mason.nvim](https://github.com/mason-org/mason.nvim) registry and publishes one native Inbox item per installed tool with an available update.

Each item has an **Update** action. The source menu can refresh the snapshot or update all outdated tools. Update actions use Mason's normal package installer and may invoke external package managers required by those tools.

## Requirements

The native Inbox must be enabled. Neovim must be available through `[app.env].PATH`, and its normal configuration must set up mason.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

The standalone menu-bar presentation is the `nvim-mason` package. Install only one presentation unless duplicate registry refreshes are intentional.

## Configuration

Automatic checks run every 60 minutes by default. Configure an interval from 5 minutes to 7 days and optional Inbox ordering, then reload EasyBar:

```toml
[widgets.nvim-mason-inbox]
refresh_interval_minutes = 60
source_order = 36
context_order = 36
```
