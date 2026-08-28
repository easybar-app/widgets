# Official EasyBar Widgets

Official installable Lua widgets and reusable Lua libraries for EasyBar and EasyBar Native.

## Features

- Independently versioned widget and library packages
- Popups, Inbox publishers, system utilities, and developer-tool integrations
- Package manifests with EasyBarKit compatibility and external requirements
- Focused Lua tests and cross-package validation
- Automatic publication to the official EasyBar Widget Registry

## Installation

Browse packages on [easybar.dev](https://easybar.dev/widget-store/catalog/) or search from either
frontend:

```sh
easybar widgets search
easybar-native widgets search
```

Install a compatible package into the frontend where it should run:

```sh
easybar widgets install PACKAGE
easybar-native widgets install PACKAGE
```

Check the package page for required commands, authentication, permissions, and frontend-specific
behavior.

## Requirements for contributors

- Lua 5.5
- Python 3.11 or newer
- A sibling EasyBarKit checkout, or `EASYBAR_KIT_ROOT` pointing to one
- `fzf` for the interactive multi-package release wizard
- GitHub CLI (`gh`) authenticated with access to the widgets and registry repositories

Run the complete validation suite before opening a pull request:

```sh
make check
```

To release one or more packages interactively, run:

```sh
make release-wizard
```

The wizard discovers `packages/*/package.toml` and lets you select packages with `fzf`. If a
manifest's current version has never been released, the wizard publishes that version directly. If a
current version already has a release tag, it asks for a patch, minor, or major bump.

For a multi-package release, the wizard applies all requested version bumps first, validates the
repository once, commits all bumped manifests together, and pushes `main` once. It then publishes the
selected package tags and waits for every package release workflow to finish successfully. After all
package releases have completed, it synchronizes `easybar-app/registry` once, waits for that sync, and
finally triggers one documentation rebuild.

## Documentation

- [Widget Store](https://easybar.dev/widget-store/overview/)
- [Create and contribute a package](https://easybar.dev/widget-store/create-and-contribute/)
- [Lua widget guides](https://easybar.dev/lua/overview/)
- [Package management](https://easybar.dev/widget-store/manage/)

## License

Licensed under the [Apache License 2.0](./LICENSE).
