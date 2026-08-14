#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
cd "$repo_root"

prompt_input="${RELEASE_WIZARD_INPUT:-/dev/tty}"
exec 3<"$prompt_input"

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_clean_main() {
  local branch
  local head
  local remote_head
  local status

  status="$(git status --porcelain=v1 --untracked-files=all)"
  if [ -n "$status" ]; then
    echo "Release wizard requires a clean worktree." >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi

  branch="$(git branch --show-current)"
  if [ "$branch" != main ]; then
    echo "Release wizard must run from main, not ${branch:-detached HEAD}." >&2
    exit 1
  fi

  git fetch origin main
  head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse origin/main)"
  if [ "$head" != "$remote_head" ]; then
    echo "Local main must exactly match origin/main before starting the release wizard." >&2
    exit 1
  fi
}

manifest_version() {
  local manifest="$1"

  scripts/support/python.sh - "$manifest" <<'PY'
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as handle:
    manifest = tomllib.load(handle)
version = manifest.get("version")
if not isinstance(version, str) or not version:
    raise SystemExit(f"missing package version: {path}")
print(version)
PY
}

select_packages() {
  local manifests
  local manifest
  local package
  local version

  manifests="$(ls -1 packages/*/package.toml)"
  if [ -z "$manifests" ]; then
    echo "No package manifests found below packages/." >&2
    return 1
  fi

  while IFS= read -r manifest; do
    package="$(basename -- "$(dirname -- "$manifest")")"
    if ! version="$(manifest_version "$manifest")"; then
      return 2
    fi
    printf '%s\t%s\n' "$package" "$version"
  done <<<"$manifests" |
    fzf \
      --multi \
      --delimiter=$'\t' \
      --with-nth=1,2 \
      --header='Select packages to release (Tab to toggle, Enter to confirm)' \
      --prompt='Packages> '
}

choose_level() {
  local package="$1"
  local current_version="$2"
  local answer

  while true; do
    printf '\n%s %s bump level:\n' "$package" "$current_version" >&2
    printf '  1) patch\n' >&2
    printf '  2) minor\n' >&2
    printf '  3) major\n' >&2
    printf '  s) skip\n' >&2
    printf '> ' >&2

    if ! IFS= read -r answer <&3; then
      echo "Release wizard input closed while choosing a bump level." >&2
      return 1
    fi
    case "$answer" in
    1 | patch | p) printf '%s\n' patch; return ;;
    2 | minor | n) printf '%s\n' minor; return ;;
    3 | major | m) printf '%s\n' major; return ;;
    s | skip) printf '%s\n' skip; return ;;
    *) echo "Choose 1, 2, 3, or s." >&2 ;;
    esac
  done
}

current_manifest=""
restore_uncommitted_manifest() {
  local status=$?

  if [ "$status" -ne 0 ] && [ -n "$current_manifest" ] && ! git diff --quiet -- "$current_manifest"; then
    git restore -- "$current_manifest"
    echo "Restored uncommitted manifest after failure: $current_manifest" >&2
  fi

  exit "$status"
}
trap restore_uncommitted_manifest EXIT

require_command fzf
require_command git
require_command make
require_command scripts/support/python.sh
require_clean_main

if selection="$(select_packages)"; then
  :
else
  selection_status=$?
  case "$selection_status" in
  1 | 130)
    echo "No packages selected."
    exit 0
    ;;
  *) exit "$selection_status" ;;
  esac
fi

if [ -z "$selection" ]; then
  echo "No packages selected."
  exit 0
fi

packages=()
levels=()
versions=()

while IFS=$'\t' read -r package version; do
  [ -n "$package" ] || continue
  level="$(choose_level "$package" "$version")"
  if [ "$level" = skip ]; then
    continue
  fi

  packages+=("$package")
  levels+=("$level")
  versions+=("$version")
done <<<"$selection"

if [ "${#packages[@]}" -eq 0 ]; then
  echo "No packages selected for release."
  exit 0
fi

echo
echo "Release plan:"
for index in "${!packages[@]}"; do
  printf '  %-28s %-5s from %s\n' "${packages[$index]}" "${levels[$index]}" "${versions[$index]}"
done

echo
printf 'Proceed with commits, pushes, and release tags? [y/N] '
if ! IFS= read -r confirmation <&3; then
  echo "Release wizard input closed before confirmation." >&2
  exit 1
fi
case "$confirmation" in
y | Y | yes | YES) ;;
*)
  echo "Release cancelled."
  exit 0
  ;;
esac

for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  level="${levels[$index]}"
  manifest="packages/$package/package.toml"
  current_manifest="$manifest"

  printf '\n==> Releasing %s (%s)\n' "$package" "$level"

  scripts/support/python.sh scripts/release/bump.py \
    --package "$package" \
    --level "$level"

  new_version="$(manifest_version "$manifest")"

  make check

  changed_paths="$(git status --porcelain=v1 --untracked-files=all)"
  expected_line=" M $manifest"
  if [ "$changed_paths" != "$expected_line" ]; then
    echo "Release checks changed unexpected files before committing $package:" >&2
    printf '%s\n' "$changed_paths" >&2
    exit 1
  fi

  git add -- "$manifest"
  git commit --only -m "chore(release): bump $package to $new_version" -- "$manifest"
  current_manifest=""

  git push origin main

  scripts/support/python.sh scripts/release/release.py \
    --package "$package" \
    --publish
done

trap - EXIT

echo
echo "Released ${#packages[@]} package(s)."
echo "GitHub Actions will build each package archive and create its GitHub release from the pushed tag."
