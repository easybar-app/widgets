# Inbox Demo Widget

`widget.lua` publishes representative GitHub, GitLab, and Homebrew messages to EasyBar's native
Inbox without requiring external services, authentication, or network access.

## Requirements

The native Inbox must be enabled. No external commands or credentials are required.

## Behavior

The package starts with an empty demo source. Use the **Add demo** source action to publish a fresh
snapshot containing representative informational, success, warning, error, read, unread, and
Markdown-formatted items. Use **Clear demo** to remove the snapshot again.

The simulated GitHub, GitLab, and Homebrew source groups use order `10000`, and the Inbox Demo source
uses the same context-menu order, so real installed Inbox widgets appear before the demo content.
