#!/usr/bin/env bash
# Guide maintainers through package releases.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
cd "$repo_root"

prompt_input="${RELEASE_WIZARD_INPUT:-/dev/tty}"
exec 3<"$prompt_input"

WIDGETS_REPOSITORY="easybar-app/widgets"
REGISTRY_REPOSITORY="easybar-app/registry"
RELEASE_WORKFLOW="release.yml"
REGISTRY_WORKFLOW="sync.yml"
DOCS_WORKFLOW="docs.yml"
WORKFLOW_DISCOVERY_ATTEMPTS=60
WORKFLOW_DISCOVERY_DELAY_SECONDS=2

# Exit unless a required command is available.
require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

# Require a clean main branch synchronized with its remote.
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

# Require an authenticated GitHub CLI session.
require_gh_authentication() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI authentication is required. Run: gh auth login" >&2
    exit 1
  fi
}

# Return whether a release tag exists on the remote.
tag_exists_on_origin() {
  local tag="$1"
  local status

  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    return 0
  else
    status=$?
  fi

  if [ "$status" -eq 2 ]; then
    return 1
  fi

  echo "Could not inspect remote tag: $tag" >&2
  exit 1
}

# Read a package version from its manifest.
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

# Prompt for the packages to release.
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

# Prompt for a semantic-version bump level.
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
    1 | patch | p)
      printf '%s\n' patch
      return
      ;;
    2 | minor | n)
      printf '%s\n' minor
      return
      ;;
    3 | major | m)
      printf '%s\n' major
      return
      ;;
    s | skip)
      printf '%s\n' skip
      return
      ;;
    *)
      echo "Choose 1, 2, 3, or s." >&2
      ;;
    esac
  done
}

# Find the latest matching workflow run.
latest_workflow_run_id() {
  local repository="$1"
  local workflow="$2"
  local event="${3:-}"

  local arguments=(
    run list
    --repo "$repository"
    --workflow "$workflow"
    --limit 1
    --json databaseId
    --jq '.[0].databaseId // empty'
  )

  if [ -n "$event" ]; then
    arguments+=(--event "$event")
  fi

  gh "${arguments[@]}"
}

# Wait for a package release workflow to finish.
wait_for_release_workflow() {
  local package="$1"
  local tag="$2"
  local attempt
  local run_id=""

  printf '\n==> Waiting for release workflow: %s\n' "$tag"

  for ((attempt = 1; attempt <= WORKFLOW_DISCOVERY_ATTEMPTS; attempt++)); do
    run_id="$(
      gh run list \
        --repo "$WIDGETS_REPOSITORY" \
        --workflow "$RELEASE_WORKFLOW" \
        --event push \
        --limit 100 \
        --json databaseId,headBranch \
        --jq ".[] | select(.headBranch == \"$tag\") | .databaseId" |
        head -n 1
    )"

    if [ -n "$run_id" ]; then
      gh run watch "$run_id" \
        --repo "$WIDGETS_REPOSITORY" \
        --exit-status
      return
    fi

    sleep "$WORKFLOW_DISCOVERY_DELAY_SECONDS"
  done

  echo "Could not find the release workflow for $package tag $tag." >&2
  exit 1
}

# Start a workflow and wait for completion.
trigger_and_wait_for_workflow() {
  local repository="$1"
  local workflow="$2"
  local label="$3"
  local previous_run_id
  local run_id=""
  local attempt

  previous_run_id="$(
    latest_workflow_run_id \
      "$repository" \
      "$workflow" \
      workflow_dispatch
  )"

  printf '\n==> Triggering %s\n' "$label"

  gh workflow run "$workflow" \
    --repo "$repository" \
    --ref main

  for ((attempt = 1; attempt <= WORKFLOW_DISCOVERY_ATTEMPTS; attempt++)); do
    run_id="$(
      latest_workflow_run_id \
        "$repository" \
        "$workflow" \
        workflow_dispatch
    )"

    if [ -n "$run_id" ] && [ "$run_id" != "$previous_run_id" ]; then
      gh run watch "$run_id" \
        --repo "$repository" \
        --exit-status
      return
    fi

    sleep "$WORKFLOW_DISCOVERY_DELAY_SECONDS"
  done

  echo "Could not find the newly dispatched $label workflow run." >&2
  exit 1
}

bumped_manifests=()

# Restore version manifests left uncommitted by a failed release preparation.
restore_uncommitted_manifests() {
  local status=$?
  local manifest

  if [ "$status" -ne 0 ]; then
    for manifest in "${bumped_manifests[@]}"; do
      if [ -n "$(git status --porcelain=v1 -- "$manifest")" ]; then
        git restore --staged --worktree -- "$manifest" >/dev/null 2>&1 || true
        echo "Restored uncommitted manifest after failure: $manifest" >&2
      fi
    done
  fi

  exit "$status"
}

trap restore_uncommitted_manifests EXIT

# Require that validation changed only the manifests intentionally bumped by the wizard.
require_expected_release_changes() {
  local changed_paths
  local expected_paths=""
  local manifest

  changed_paths="$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort)"

  if [ "${#bumped_manifests[@]}" -gt 0 ]; then
    expected_paths="$(
      for manifest in "${bumped_manifests[@]}"; do
        printf ' M %s\n' "$manifest"
      done | LC_ALL=C sort
    )"
  fi

  if [ "$changed_paths" != "$expected_paths" ]; then
    echo "Release checks changed unexpected files:" >&2
    printf '%s\n' "$changed_paths" >&2
    exit 1
  fi
}

# Commit every requested manifest bump together and push main once.
commit_release_bumps() {
  local commit_message="chore(release): bump package versions"
  local manifest
  local package
  local version

  if [ "${#bumped_manifests[@]}" -eq 0 ]; then
    return
  fi

  if [ "${#bumped_manifests[@]}" -eq 1 ]; then
    manifest="${bumped_manifests[0]}"
    package="$(basename -- "$(dirname -- "$manifest")")"
    version="$(manifest_version "$manifest")"
    commit_message="chore(release): bump $package to $version"
  fi

  git add -- "${bumped_manifests[@]}"

  git commit \
    -m "$commit_message" \
    -- "${bumped_manifests[@]}"

  git push origin main
}

require_command fzf
require_command gh
require_command git
require_command make
require_command scripts/support/python.sh

require_gh_authentication
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
  *)
    exit "$selection_status"
    ;;
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

  tag="$package-v$version"

  if tag_exists_on_origin "$tag"; then
    level="$(choose_level "$package" "$version")"

    if [ "$level" = skip ]; then
      continue
    fi
  else
    level="current"
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
  if [ "${levels[$index]}" = current ]; then
    printf '  %-28s release %s\n' \
      "${packages[$index]}" \
      "${versions[$index]}"
  else
    printf '  %-28s %-5s from %s\n' \
      "${packages[$index]}" \
      "${levels[$index]}" \
      "${versions[$index]}"
  fi
done

echo
printf 'Proceed with version bumps, one validation/commit/push, releases, registry sync, and docs rebuild? [y/N] '

if ! IFS= read -r confirmation <&3; then
  echo "Release wizard input closed before confirmation." >&2
  exit 1
fi

case "$confirmation" in
y | Y | yes | YES)
  ;;
*)
  echo "Release cancelled."
  exit 0
  ;;
esac

for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  level="${levels[$index]}"

  if [ "$level" = current ]; then
    continue
  fi

  manifest="packages/$package/package.toml"
  bumped_manifests+=("$manifest")

  printf '\n==> Bumping %s (%s)\n' \
    "$package" \
    "$level"

  scripts/support/python.sh scripts/release/bump.py \
    --package "$package" \
    --level "$level"
done

printf '\n==> Validating release plan\n'

make check

require_expected_release_changes
commit_release_bumps

release_tags=()

for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  manifest="packages/$package/package.toml"
  version="$(manifest_version "$manifest")"
  tag="$package-v$version"

  printf '\n==> Publishing %s\n' "$tag"

  scripts/support/python.sh scripts/release/release.py \
    --package "$package" \
    --publish

  release_tags+=("$tag")
done

for index in "${!packages[@]}"; do
  wait_for_release_workflow \
    "${packages[$index]}" \
    "${release_tags[$index]}"
done

trigger_and_wait_for_workflow \
  "$REGISTRY_REPOSITORY" \
  "$REGISTRY_WORKFLOW" \
  "widget registry synchronization"

trigger_and_wait_for_workflow \
  "$WIDGETS_REPOSITORY" \
  "$DOCS_WORKFLOW" \
  "documentation rebuild"

trap - EXIT

echo
echo "Released ${#packages[@]} package(s)."
echo "All package release workflows completed successfully."
echo "The widget registry is synchronized and the documentation trigger workflow completed successfully."
