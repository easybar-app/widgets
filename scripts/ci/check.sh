#!/usr/bin/env bash
# Validate the widget package and its Lua sources.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
easybar_kit_root="${EASYBAR_KIT_ROOT:-${repo_root}/../easybar-kit}"
lua_bin="${LUA:-lua}"

command -v "${lua_bin}" >/dev/null 2>&1 || {
  echo "Lua 5.5 is required: ${lua_bin}" >&2
  exit 1
}
"${lua_bin}" -e 'assert(_VERSION == "Lua 5.5", "expected Lua 5.5, got " .. tostring(_VERSION))'
[ -f "${easybar_kit_root}/Sources/EasyBarKit/Lua/easybar/json.lua" ] || {
  echo "EasyBarKit source checkout not found: ${easybar_kit_root}" >&2
  exit 1
}

while IFS= read -r file; do
  LUA_CHECK_FILE="${file}" "${lua_bin}" -e \
    'local path = assert(os.getenv("LUA_CHECK_FILE")); assert(loadfile(path, "t", {}))'
done < <(find "${repo_root}/packages" "${repo_root}/tests" -type f -name '*.lua' -print | LC_ALL=C sort)

test_count=0
while IFS= read -r test_file; do
  test_count=$((test_count + 1))
  "${lua_bin}" "${test_file}" "${repo_root}" "${easybar_kit_root}"
done < <(find "${repo_root}/packages" -path '*/tests/*' -type f -name '*.lua' -print | LC_ALL=C sort)

while IFS=$'\t' read -r package entrypoint; do
  test_count=$((test_count + 1))
  "${lua_bin}" "${repo_root}/tests/smoke/test.lua" \
    "${repo_root}" "${easybar_kit_root}" "${package}" "${entrypoint}"
done < <("${repo_root}/scripts/support/python.sh" "${repo_root}/scripts/ci/validate.py" --print-widgets)

printf 'Lua package checks passed (%d tests).\n' "${test_count}"
