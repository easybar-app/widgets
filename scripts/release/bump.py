#!/usr/bin/env python3
"""Bump the stable semantic version of one EasyBar package."""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ROOT / "packages"
STABLE_SEMVER = re.compile(
    r"(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)"
)
VERSION_LINE = re.compile(r'(?m)^version = "([^"]+)"$')


def bump_version(version: str, level: str) -> str:
    match = STABLE_SEMVER.fullmatch(version)
    if match is None:
        raise ValueError(f"version must be stable semantic version: {version}")

    major = int(match.group("major"))
    minor = int(match.group("minor"))
    patch = int(match.group("patch"))
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    if level == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ValueError(f"unsupported bump level: {level}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--level", required=True, choices=("major", "minor", "patch"))
    args = parser.parse_args()

    try:
        manifest_path = PACKAGES / args.package / "package.toml"
        with manifest_path.open("rb") as handle:
            manifest = tomllib.load(handle)
        if manifest.get("name") != args.package:
            raise ValueError(f"unknown package: {args.package}")

        current = manifest.get("version")
        if not isinstance(current, str):
            raise ValueError(f"{args.package}: manifest version is missing")
        updated = bump_version(current, args.level)

        source = manifest_path.read_text(encoding="utf-8")
        matches = VERSION_LINE.findall(source)
        if matches != [current]:
            raise ValueError(f"{args.package}: expected one canonical version field")
        rendered = VERSION_LINE.sub(f'version = "{updated}"', source, count=1)
        manifest_path.write_text(rendered, encoding="utf-8")
    except (OSError, tomllib.TOMLDecodeError, ValueError) as error:
        print(f"Package version bump failed: {error}", file=sys.stderr)
        return 1

    print(f"Bumped {args.package} from {current} to {updated} ({args.level}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
