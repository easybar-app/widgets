# Homebrew Widget

`widget.lua` renders a compact Homebrew status item and a popup for outdated formulae and casks. It supports refresh, update, upgrade, cancellation, warnings, automatic updates, and a conservative manual-upgrade policy.

## Requirements

Homebrew must be available through `[app.env].PATH`.

## Configuration

Automatic updates are enabled by default. Every 30 minutes, the widget updates Homebrew metadata, checks for outdated packages, and upgrades packages allowed by `brew-policy`. Set `automatic_updates = false` to keep scheduled outdated-package checks without running automatic `brew update` or package upgrades. Manual **Update** and **Upgrade** actions remain available.

```toml
[widgets.brew]
automatic_updates = true
```

The widget context menu shows and persists the automatic-update toggle.

## Files

- `widget.lua`: standalone bar and popup implementation

The shared manual-upgrade rules come from the `brew-policy` library dependency.

The alternative native-inbox presentation is the `inbox-brew` package. Install only one Homebrew presentation unless duplicate polling is intentional.
