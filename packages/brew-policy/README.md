# Homebrew Policy Library

This library contains the conservative manual-upgrade policy shared by the standalone `brew` widget
and the `inbox-brew` widget. It keeps packages that require interactive or vendor-specific updates
visible without allowing EasyBar to upgrade them automatically.

The package exports the `brew_policy` Lua module. It is installed automatically as a dependency and
does not create a status-bar widget of its own.
