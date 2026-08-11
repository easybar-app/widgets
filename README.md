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

Run the complete validation suite before opening a pull request:

```sh
make check
```

## Documentation

- [Widget Store](https://easybar.dev/widget-store/overview/)
- [Create and contribute a package](https://easybar.dev/widget-store/create-and-contribute/)
- [Lua widget guides](https://easybar.dev/lua/overview/)
- [Package management](https://easybar.dev/widget-store/manage/)

## License

Licensed under the [Apache License 2.0](./LICENSE).
