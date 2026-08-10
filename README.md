# Official EasyBar Widgets

Official installable Lua widgets and reusable Lua libraries for the EasyBar frontends, powered by
[EasyBarKit](https://github.com/easybar-app/easybar-kit).

## Packages

Browse `packages/` for package source and documentation, or use:

```sh
easybar widgets search
```

Each package is independently versioned and contains a manifest-version-2 `package.toml`. Packages
declare `minimum_easybar_kit_version`; manifest version 1 is not accepted. The clean split starts at EasyBarKit `0.54.0`, so current official package releases require at least that version.

Widget packages declare one entrypoint. Library packages declare exported module names. Dependencies are resolved from package manifests.

## Development

Run all checks with:

```sh
make check
```

The package validator rejects invalid dependency constraints and requires all official consumers of a
library to have a jointly satisfiable version range. This matches EasyBar's one active version per
library dependency model and catches incompatible shared-library requirements before merge or release.

By default, tests use the Lua API and JSON implementation from a sibling EasyBarKit checkout.
Override its location with:

```sh
make check EASYBAR_KIT_ROOT=/path/to/easybar-kit
```

Focused package tests live under:

```text
packages/<name>/tests/
```

Shared test infrastructure and cross-package smoke tests live under `tests/`.

Package-local tests are executed by `make check` but excluded from release archives.

## Releases

Packages are versioned and released independently.

Bump a package version with:

```sh
make bump PACKAGE=package-name LEVEL=patch
```

`LEVEL` must be `patch`, `minor`, or `major`.

Commit and push the version change:

```sh
git add packages/package-name/package.toml
git commit -m "chore(package-name): prepare 0.1.1"
git push origin main
```

Then create the release:

```sh
make release PACKAGE=package-name
```

The release command requires a clean `main` branch matching `origin/main`, runs all checks, creates an annotated `package-name-v0.1.1` tag, and pushes the tag.

The GitHub release workflow creates:

```text
package-name-0.1.1.tar.gz
package-name-0.1.1.tar.gz.sha256
```

Release archives contain only the package contents, with `package.toml` at the archive root.

Build an archive locally with:

```sh
make package PACKAGE=package-name OUTPUT_DIR=dist
```

Published releases are discovered automatically by the [widget registry](https://github.com/easybar-app/registry).

## Contributing

Add new packages under `packages/<name>/` with their manifest, README, source, assets, and tests.

Run:

```sh
make check
```

before opening a pull request.

See the [Widget Store contribution guide](https://easybar.dev/widget-store/create-and-contribute/) for package layout, metadata, testing, and publishing requirements.
