# Tailscale Widget

`widget.lua` shows whether Tailscale is active and whether an exit node is selected. Left click starts or stops Tailscale. The context menu refreshes state and selects or disables an advertised exit node.

## States

| Connected                                                                                                                            | Disconnected                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| <img src="https://easybar.dev/assets/tailscale_enabled.png" width="482" alt="Tailscale widget connected with an exit node selected"> | <img src="https://easybar.dev/assets/tailscale_disabled.png" width="482" alt="Tailscale widget disconnected with exit-node choices"> |

## Requirements

The Tailscale CLI must be available through `[app.env].PATH`. An optional executable override may be supplied through `[app.env]`:

```toml
[app.env]
TAILSCALE = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
```

When `TAILSCALE` is omitted, the widget executes `tailscale` through `PATH`.
