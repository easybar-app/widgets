#!/usr/bin/env bash
set -euo pipefail

while IFS=$'\t' read -r package _; do
  echo "Releasing ${package}..."
  make release PACKAGE="$package"
done < <(
  scripts/support/python.sh scripts/ci/validate.py --print-widgets
)
