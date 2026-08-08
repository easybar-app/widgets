# Official EasyBar Widgets

This repository contains the official installable Lua widgets and reusable Lua libraries for [EasyBar](https://github.com/easybar-app/easybar). The app repository keeps only small examples; installable integrations live here and are listed by the [widget registry](https://github.com/easybar-app/widget-registry).

## Packages

Browse [`packages/`](packages/) for the current package source and package-specific documentation,
or run `easybar widgets search` to discover published packages. Each package is independently
versioned and has a `package.toml` manifest. Widget packages declare one entrypoint. Library
packages declare exported module names. Dependencies are resolved from manifests and do not
implicitly activate dependency entrypoints.

## Development

The package tests use the EasyBar Lua API and JSON implementation from a sibling EasyBar checkout by default:

```sh
make check
```

Override its location when needed:

```sh
make check EASYBAR_ROOT=/path/to/easybar
```

The metadata validator checks package identity, versions, compatibility, entrypoints, exported modules, dependency cycles, repository paths, and static asset references.

Focused tests live beside their package under `packages/<name>/tests/`. Shared test hosts and the cross-package smoke test remain under `tests/`. Package-local test directories are validated and executed by `make check`, but are excluded from release archives.

## Releases

Packages are versioned and released independently from this monorepo. First bump one package's
stable semantic version:

```sh
make bump PACKAGE=package-name LEVEL=patch
```

`LEVEL` must be `patch`, `minor`, or `major`. The command updates the version in
`packages/package-name/package.toml` and runs all package checks. Review and commit that change, then
push `main`:

```sh
git add packages/package-name/package.toml
git commit -m "chore(package-name): prepare 0.1.1"
git push origin main
```

Create the release only after the version commit is on `main`:

```sh
make release PACKAGE=package-name
```

The release command requires a clean `main` branch that exactly matches `origin/main`, reruns all
checks, creates the annotated `package-name-v0.1.1` tag, and pushes only that tag. The GitHub release
workflow then creates the deterministic `package-name-0.1.1.tar.gz` archive and its SHA-256 checksum.
Released archives contain only that package, with `package.toml` at their root.

The [widget registry](https://github.com/easybar-app/widget-registry) periodically discovers new
published releases and updates its immutable version metadata automatically.

Build the same archive locally with:

```sh
make package PACKAGE=package-name OUTPUT_DIR=dist
```

## Contributing a widget

Add new integrations below `packages/<name>/`, including their manifest, package README, source,
assets, and focused tests. Run `make check` before opening a pull request. The complete package
layout, metadata rules, testing guidance, and registry follow-up are documented in
[the EasyBar documentation](https://easybar.dev/lua/guides/contributing-widget/).
