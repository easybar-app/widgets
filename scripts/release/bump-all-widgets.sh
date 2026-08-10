#!/usr/bin/env bash
set -euo pipefail

level="${1:-patch}"

case "$level" in
patch | minor | major) ;;
*)
  echo "usage: $0 [patch|minor|major]" >&2
  exit 2
  ;;
esac

while IFS=$'\t' read -r package _; do
  scripts/support/python.sh scripts/release/bump.py \
    --package "$package" \
    --level "$level"
done < <(
  scripts/support/python.sh scripts/ci/validate.py --print-widgets
)

make check
