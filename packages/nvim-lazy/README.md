# lazy.nvim Updates Widget

`widget.lua` checks for available [lazy.nvim](https://lazy.folke.io/) plugin updates and shows their count in the menu bar. Left-click the widget or choose **Refresh** from its context menu to check again.

The check runs `require("lazy").check({ wait = true, show = false })` inside headless Neovim. It only fetches and compares plugin revisions; it does not install updates or change the lockfile.

## Requirements

Neovim must be available through `[app.env].PATH`, and its normal configuration must set up lazy.nvim. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
NVIM = "/opt/homebrew/bin/nvim"
```

`NVIM` may contain an executable name or an absolute path, but not command-line arguments.

## Configuration

Automatic checks run every 60 minutes by default. The interval accepts values from 1 minute to 24 hours:

```toml
[widgets.nvim-lazy]
refresh_interval_minutes = 30
```
