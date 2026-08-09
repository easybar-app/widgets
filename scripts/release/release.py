#!/usr/bin/env python3
"""Validate and publish the release tag for one EasyBar package."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ROOT / "packages"
SEMVER = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")
PACKAGE_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
REMOTE = "origin"
BRANCH = "main"


def git(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=check,
        capture_output=True,
        text=True,
    )


def load_release(package: str) -> tuple[str, str]:
    if not PACKAGE_NAME.fullmatch(package):
        raise ValueError(f"invalid package name: {package}")
    manifest_path = PACKAGES / package / "package.toml"
    with manifest_path.open("rb") as handle:
        manifest = tomllib.load(handle)
    if manifest.get("name") != package:
        raise ValueError(f"unknown package: {package}")
    version = manifest.get("version")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        raise ValueError(f"{package}: invalid manifest version: {version!r}")
    return version, f"{package}-v{version}"


def preflight(tag: str) -> str:
    status = git("status", "--porcelain=v1", "--untracked-files=all").stdout.strip()
    if status:
        raise ValueError("worktree must be clean before creating a release")

    branch = git("branch", "--show-current").stdout.strip()
    if branch != BRANCH:
        raise ValueError(f"release must be created from {BRANCH}, not {branch or 'detached HEAD'}")

    git("fetch", REMOTE, BRANCH)
    head = git("rev-parse", "HEAD").stdout.strip()
    remote_head = git("rev-parse", f"{REMOTE}/{BRANCH}").stdout.strip()
    if head != remote_head:
        raise ValueError(f"local {BRANCH} must exactly match {REMOTE}/{BRANCH}")

    local_tag = git("show-ref", "--verify", "--quiet", f"refs/tags/{tag}", check=False)
    if local_tag.returncode == 0:
        raise ValueError(f"tag already exists locally: {tag}")

    remote_tag = git(
        "ls-remote",
        "--exit-code",
        "--tags",
        REMOTE,
        f"refs/tags/{tag}",
        check=False,
    )
    if remote_tag.returncode == 0:
        raise ValueError(f"tag already exists on {REMOTE}: {tag}")
    if remote_tag.returncode != 2:
        message = remote_tag.stderr.strip() or "unable to inspect remote tags"
        raise ValueError(message)
    return head


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()

    try:
        version, tag = load_release(args.package)
        head = preflight(tag)
        if args.publish:
            git("tag", "-a", tag, "-m", f"Release {args.package} {version}")
            try:
                git("push", REMOTE, f"refs/tags/{tag}")
            except subprocess.CalledProcessError:
                git("tag", "--delete", tag, check=False)
                raise
            print(f"Published {tag} from {head[:12]}.")
        else:
            print(f"Ready to release {tag} from {head[:12]}.")
    except (
        OSError,
        subprocess.CalledProcessError,
        tomllib.TOMLDecodeError,
        ValueError,
    ) as error:
        if isinstance(error, subprocess.CalledProcessError):
            detail = error.stderr.strip() or error.stdout.strip() or str(error)
        else:
            detail = str(error)
        print(f"Package release failed: {detail}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
