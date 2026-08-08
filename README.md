# Official EasyBar Widgets

This repository contains the official installable Lua widgets and reusable Lua libraries for [EasyBar](https://github.com/easybar-app/easybar). The app repository keeps only small examples; installable integrations live here and are listed by the [widget registry](https://github.com/easybar-app/widget-registry).

## Packages

| Package        | Kind    | Purpose                                    |
| -------------- | ------- | ------------------------------------------ |
| `brew`         | widget  | Homebrew popup and upgrade controls        |
| `caffeinate`   | widget  | Timed or indefinite macOS sleep prevention |
| `github`       | widget  | GitHub notifications popup                 |
| `gitlab`       | widget  | GitLab issues and merge requests popup     |
| `inbox-brew`   | widget  | Homebrew native-inbox publisher            |
| `inbox-github` | widget  | GitHub native-inbox publisher              |
| `inbox-gitlab` | widget  | GitLab native-inbox publisher              |
| `shared`       | library | `text`, `retry`, and `inbox` Lua modules   |
| `tailscale`    | widget  | Tailscale state and exit-node controls     |
| `wireguard`    | widget  | Network Extension VPN controls             |

Each directory below `packages/` is an independently versioned package with a `package.toml` manifest. Widget packages declare one entrypoint. Library packages declare exported module names. Dependencies are resolved from manifests and do not implicitly activate dependency entrypoints.

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

## Releases

Packages are versioned and released independently from this monorepo. First bump one package's
stable semantic version:

```sh
make bump PACKAGE=wireguard LEVEL=patch
```

`LEVEL` must be `patch`, `minor`, or `major`. The command updates the version in
`packages/wireguard/package.toml` and runs all package checks. Review and commit that change, then
push `main`:

```sh
git add packages/wireguard/package.toml
git commit -m "chore(wireguard): prepare 0.1.1"
git push origin main
```

Create the release only after the version commit is on `main`:

```sh
make release PACKAGE=wireguard
```

The release command requires a clean `main` branch that exactly matches `origin/main`, reruns all
checks, creates the annotated `wireguard-v0.1.1` tag, and pushes only that tag. The GitHub release
workflow then creates the deterministic `wireguard-0.1.1.tar.gz` archive and its SHA-256 checksum.
Released archives contain only that package, with `package.toml` at their root.

The [widget registry](https://github.com/easybar-app/widget-registry) periodically discovers new
published releases and updates its immutable version metadata automatically.

Build the same archive locally with:

```sh
make package PACKAGE=caffeinate OUTPUT_DIR=dist
```
