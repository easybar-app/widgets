# Homebrew Inbox Widget

`widget.lua` publishes outdated Homebrew formulae and casks to the native inbox. Source actions support refresh, `brew update`, automatic updates, and cancellation. Package actions can upgrade one eligible item.

## Requirements

Homebrew must be available through `[app.env].PATH`, and the native inbox must be enabled.

The widget depends on the small `brew-policy` library so packages requiring manual handling remain
visible but are not upgraded automatically. It does not depend on or activate the standalone `brew`
widget.

The standalone popup presentation is the `brew` package. Install only one Homebrew presentation unless duplicate polling is intentional.

## Configuration

Automatic updates are enabled by default. Every 30 minutes, the widget updates Homebrew metadata,
checks for outdated packages, and upgrades packages allowed by `brew-policy`. Set an interval from
5 minutes to 7 days, or disable automatic updates, and reload EasyBar:

```toml
[widgets.brew-inbox]
automatic_updates = true
refresh_interval_minutes = 30
source_order = 30
context_order = 30
```

When `automatic_updates = false`, scheduled outdated-package checks still run so the Inbox remains current, but automatic `brew update` and package upgrades are skipped. Manual source and package actions remain available.

`source_order` controls the Homebrew group when the inbox is grouped by source.
`context_order` independently controls its position in the inbox source menu. Lower values appear
first. The source context menu shows the automatic-update toggle and active refresh interval directly.
