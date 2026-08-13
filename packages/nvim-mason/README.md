# mason.nvim Updates Widget

`widget.lua` refreshes the [mason.nvim](https://github.com/mason-org/mason.nvim) registry and shows how many installed tools have updates. Left-click the widget or choose **Refresh** from its context menu to check again.

Refreshing updates Mason's registry metadata and compares installed and latest versions. It does not install tool updates.

## Requirements

Neovim must be available through `[app.env].PATH`, and its normal configuration must set up mason.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

## Configuration

Automatic checks run every 60 minutes by default. The interval accepts values from 5 minutes to 24 hours:

```toml
[widgets.nvim-mason]
refresh_interval_minutes = 30
```

The native Inbox presentation is available separately as `inbox-nvim-mason`. Install only one presentation unless duplicate registry refreshes are intentional.
