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

Run the complete validation suite before opening a pull request:

```sh
make check
```

To release one or more packages interactively, run:

```sh
make release-wizard
```

The wizard discovers `packages/*/package.toml`, lets you select packages with `fzf`, asks for a patch,
minor, or major bump for each selection, validates the repository, commits and pushes each manifest
bump independently, and publishes the corresponding package tag. The existing tag workflow creates
the GitHub release and deterministic archive.

## Documentation

- [Widget Store](https://easybar.dev/widget-store/overview/)
- [Create and contribute a package](https://easybar.dev/widget-store/create-and-contribute/)
- [Lua widget guides](https://easybar.dev/lua/overview/)
- [Package management](https://easybar.dev/widget-store/manage/)

## License

Licensed under the [Apache License 2.0](./LICENSE).
