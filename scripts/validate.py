#!/usr/bin/env python3
"""Validate EasyBar package manifests and their declared file graph."""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ROOT / "packages"
SEMVER = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")
PACKAGE_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
ASSET_LITERAL = re.compile(r'easybar\.asset\("([^"@][^"]*)"\)')


def fail(message: str) -> None:
    raise ValueError(message)


def safe_file(package_dir: Path, relative: object, label: str) -> Path:
    if not isinstance(relative, str) or not relative:
        fail(f"{package_dir.name}: {label} must be a non-empty string")
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        fail(f"{package_dir.name}: unsafe {label}: {relative}")
    resolved = package_dir / path
    if not resolved.is_file():
        fail(f"{package_dir.name}: missing {label}: {relative}")
    return resolved


def load_manifests() -> dict[str, tuple[Path, dict]]:
    manifests: dict[str, tuple[Path, dict]] = {}
    for manifest_path in sorted(PACKAGES.glob("*/package.toml")):
        package_dir = manifest_path.parent
        with manifest_path.open("rb") as handle:
            manifest = tomllib.load(handle)

        name = manifest.get("name")
        if not isinstance(name, str) or not PACKAGE_NAME.fullmatch(name):
            fail(f"{package_dir.name}: invalid package name: {name!r}")
        if name != package_dir.name:
            fail(f"{name}: package directory must match its name")
        if name in manifests:
            fail(f"duplicate package name: {name}")
        manifests[name] = (package_dir, manifest)
    if not manifests:
        fail("no package manifests found")
    return manifests


def validate_manifest(name: str, package_dir: Path, manifest: dict, names: set[str]) -> None:
    if manifest.get("manifest_version") != 1:
        fail(f"{name}: manifest_version must be 1")
    if manifest.get("kind") not in {"widget", "library"}:
        fail(f"{name}: kind must be widget or library")
    for field in ("version", "minimum_easybar_version"):
        value = manifest.get(field)
        if not isinstance(value, str) or not SEMVER.fullmatch(value):
            fail(f"{name}: invalid {field}: {value!r}")
    for field in ("description", "license", "readme"):
        if not isinstance(manifest.get(field), str) or not manifest[field]:
            fail(f"{name}: missing {field}")

    safe_file(package_dir, manifest["readme"], "readme")
    declared_lua: set[Path] = set()
    if manifest["kind"] == "widget":
        entrypoint = safe_file(package_dir, manifest.get("entrypoint"), "entrypoint")
        if entrypoint.suffix.lower() != ".lua":
            fail(f"{name}: entrypoint must be Lua")
        declared_lua.add(entrypoint)
    elif "entrypoint" in manifest:
        fail(f"{name}: library packages cannot declare an entrypoint")

    exports = manifest.get("exports", {})
    if not isinstance(exports, dict):
        fail(f"{name}: exports must be a table")
    for module, relative in exports.items():
        if not isinstance(module, str) or not module:
            fail(f"{name}: invalid exported module")
        exported = safe_file(package_dir, relative, f"export {module}")
        if exported.suffix.lower() != ".lua":
            fail(f"{name}: export {module} must be Lua")
        declared_lua.add(exported)

    actual_lua = {
        path
        for path in package_dir.rglob("*.lua")
        if path.relative_to(package_dir).parts[0] != "tests"
    }
    undeclared = sorted(path.relative_to(package_dir) for path in actual_lua - declared_lua)
    if undeclared:
        fail(f"{name}: undeclared Lua files: {', '.join(map(str, undeclared))}")

    dependencies = manifest.get("dependencies", {})
    if not isinstance(dependencies, dict):
        fail(f"{name}: dependencies must be a table")
    for dependency, constraint in dependencies.items():
        if dependency not in names:
            fail(f"{name}: unknown dependency: {dependency}")
        if dependency == name:
            fail(f"{name}: package cannot depend on itself")
        if not isinstance(constraint, str) or not constraint:
            fail(f"{name}: dependency {dependency} needs a version constraint")

    repository = manifest.get("repository", {})
    expected_path = f"packages/{name}"
    if repository.get("url") != "https://github.com/easybar-app/widgets":
        fail(f"{name}: unexpected repository URL")
    if repository.get("path") != expected_path:
        fail(f"{name}: repository path must be {expected_path}")

    for lua_path in actual_lua:
        source = lua_path.read_text(encoding="utf-8")
        for asset in ASSET_LITERAL.findall(source):
            safe_file(package_dir, asset, f"asset referenced by {lua_path.name}")


def validate_cycles(manifests: dict[str, tuple[Path, dict]]) -> None:
    visited: set[str] = set()
    active: list[str] = []

    def visit(name: str) -> None:
        if name in active:
            fail("dependency cycle: " + " -> ".join(active + [name]))
        if name in visited:
            return
        active.append(name)
        for dependency in manifests[name][1].get("dependencies", {}):
            visit(dependency)
        active.pop()
        visited.add(name)

    for name in manifests:
        visit(name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--print-widgets", action="store_true")
    args = parser.parse_args()
    try:
        manifests = load_manifests()
        names = set(manifests)
        for name, (package_dir, manifest) in manifests.items():
            validate_manifest(name, package_dir, manifest, names)
        validate_cycles(manifests)
    except (OSError, tomllib.TOMLDecodeError, ValueError) as error:
        print(f"Package validation failed: {error}", file=sys.stderr)
        return 1

    if args.print_widgets:
        for name, (_, manifest) in manifests.items():
            if manifest["kind"] == "widget":
                print(f"{name}\t{manifest['entrypoint']}")
    else:
        print(f"Validated {len(manifests)} EasyBar packages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
