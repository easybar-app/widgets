#!/usr/bin/env python3
"""Validate EasyBar package manifests and their declared file graph."""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from dataclasses import dataclass
from functools import total_ordering
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ROOT / "packages"
SEMVER = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")
PACKAGE_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
ASSET_LITERAL = re.compile(r'easybar\.asset\("([^"@][^"]*)"\)')
MANIFEST_KEYS = {
    "manifest_version",
    "name",
    "version",
    "minimum_easybar_kit_version",
    "kind",
    "description",
    "license",
    "readme",
    "categories",
    "entrypoint",
    "repository",
    "dependencies",
    "exports",
    "requirements",
    "settings",
}


def fail(message: str) -> None:
    """Exit with a validation error."""
    raise ValueError(message)


@total_ordering
@dataclass(frozen=True)
class SemanticVersion:
    """Semantic version ordering matching EasyBar's package resolver."""

    major: int
    minor: int
    patch: int
    prerelease: tuple[str, ...] = ()

    @classmethod
    def parse(cls, value: str) -> SemanticVersion | None:
        """Parse a semantic version when the value is valid."""
        version = value.split("+", 1)[0]
        core_and_prerelease = version.split("-", 1)
        core = core_and_prerelease[0].split(".")
        if len(core) != 3:
            return None

        try:
            major, minor, patch = (int(part) for part in core)
        except ValueError:
            return None
        if min(major, minor, patch) < 0:
            return None

        prerelease: tuple[str, ...] = ()
        if len(core_and_prerelease) == 2:
            prerelease = tuple(core_and_prerelease[1].split("."))
            if not prerelease or any(not part for part in prerelease):
                return None

        return cls(major, minor, patch, prerelease)

    def __lt__(self, other: object) -> bool:
        """Compare versions using semantic-version precedence."""
        if not isinstance(other, SemanticVersion):
            return NotImplemented

        left_core = (self.major, self.minor, self.patch)
        right_core = (other.major, other.minor, other.patch)
        if left_core != right_core:
            return left_core < right_core
        if not self.prerelease:
            return False
        if not other.prerelease:
            return True

        for left, right in zip(self.prerelease, other.prerelease):
            if left == right:
                continue
            left_number = int(left) if left.isdigit() else None
            right_number = int(right) if right.isdigit() else None
            if left_number is not None and right_number is not None:
                return left_number < right_number
            if left_number is not None:
                return True
            if right_number is not None:
                return False
            return left < right

        return len(self.prerelease) < len(other.prerelease)

    def __str__(self) -> str:
        """Return the normalized semantic version."""
        core = f"{self.major}.{self.minor}.{self.patch}"
        return core if not self.prerelease else core + "-" + ".".join(self.prerelease)


@dataclass(frozen=True)
class VersionConstraint:
    """Exact or caret dependency constraint matching EasyBar's manifest parser."""

    raw_value: str
    exact: SemanticVersion | None
    minimum: SemanticVersion | None
    maximum: SemanticVersion | None

    @classmethod
    def parse(cls, raw_value: str) -> VersionConstraint | None:
        """Parse an exact or caret version constraint."""
        trimmed = raw_value.strip()
        if not trimmed:
            return None

        if trimmed.startswith("^"):
            minimum = SemanticVersion.parse(trimmed[1:])
            if minimum is None:
                return None
            if minimum.major > 0:
                maximum = SemanticVersion(minimum.major + 1, 0, 0)
            elif minimum.minor > 0:
                maximum = SemanticVersion(0, minimum.minor + 1, 0)
            else:
                maximum = SemanticVersion(0, 0, minimum.patch + 1)
            return cls(trimmed, None, minimum, maximum)

        exact = SemanticVersion.parse(trimmed.lstrip("= "))
        if exact is None:
            return None
        return cls(trimmed, exact, None, None)

    def contains(self, version: SemanticVersion) -> bool:
        """Return whether the constraint accepts a version."""
        if self.exact is not None:
            return self.exact == version
        assert self.minimum is not None
        assert self.maximum is not None
        return self.minimum <= version < self.maximum


def safe_file(package_dir: Path, relative: object, label: str) -> Path:
    """Resolve and validate a package-relative file."""
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
    """Load all package manifests."""
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
    """Validate package metadata and declared files."""
    if manifest.get("manifest_version") != 2:
        fail(f"{name}: manifest_version must be 2")
    unknown_keys = sorted(set(manifest) - MANIFEST_KEYS)
    if unknown_keys:
        fail(f"{name}: unsupported manifest fields: {', '.join(unknown_keys)}")
    if manifest.get("kind") not in {"widget", "library"}:
        fail(f"{name}: kind must be widget or library")
    for field in ("version", "minimum_easybar_kit_version"):
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
        if VersionConstraint.parse(constraint) is None:
            fail(
                f"{name}: invalid dependency constraint for {dependency}: {constraint!r}; "
                "expected an exact version or caret constraint"
            )

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
    """Reject cyclic package dependencies."""
    visited: set[str] = set()
    active: list[str] = []

    def visit(name: str) -> None:
        """Visit one package while detecting dependency cycles."""
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


def validate_dependency_kinds(manifests: dict[str, tuple[Path, dict]]) -> None:
    """Validate dependency package kinds."""
    for name, (_, manifest) in manifests.items():
        for dependency in manifest.get("dependencies", {}):
            dependency_kind = manifests[dependency][1].get("kind")
            if dependency_kind != "library":
                fail(
                    f"{name}: dependency {dependency} must be a library, "
                    f"not {dependency_kind}"
                )


def constraints_are_compatible(constraints: list[VersionConstraint]) -> bool:
    """Return whether one semantic version can satisfy every constraint."""

    exact_versions = [constraint.exact for constraint in constraints if constraint.exact]
    if exact_versions:
        candidate = exact_versions[0]
        return all(version == candidate for version in exact_versions) and all(
            constraint.contains(candidate) for constraint in constraints
        )

    minimum = max(
        constraint.minimum for constraint in constraints if constraint.minimum is not None
    )
    maximum = min(
        constraint.maximum for constraint in constraints if constraint.maximum is not None
    )
    return minimum < maximum


def validate_dependency_compatibility(manifests: dict[str, tuple[Path, dict]]) -> None:
    """Require one satisfiable version range for every shared library dependency."""

    requirements: dict[str, list[tuple[str, VersionConstraint]]] = {}
    for consumer, (_, manifest) in manifests.items():
        for dependency, raw_constraint in manifest.get("dependencies", {}).items():
            constraint = VersionConstraint.parse(raw_constraint)
            assert constraint is not None
            requirements.setdefault(dependency, []).append((consumer, constraint))

    for dependency, consumers in sorted(requirements.items()):
        constraints = [constraint for _, constraint in consumers]
        if constraints_are_compatible(constraints):
            continue

        detail = "\n".join(
            f"  {consumer} requires {constraint.raw_value}"
            for consumer, constraint in sorted(consumers)
        )
        fail(
            f"dependency compatibility conflict for library '{dependency}':\n"
            f"{detail}\n"
            f"no single version of '{dependency}' satisfies all official package requirements"
        )


def main() -> int:
    """Run the command-line entry point."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--print-widgets", action="store_true")
    args = parser.parse_args()
    try:
        manifests = load_manifests()
        names = set(manifests)
        for name, (package_dir, manifest) in manifests.items():
            validate_manifest(name, package_dir, manifest, names)
        validate_dependency_kinds(manifests)
        validate_cycles(manifests)
        validate_dependency_compatibility(manifests)
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
