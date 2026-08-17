#!/usr/bin/env python3
"""Create a deterministic release archive for one EasyBar package."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import sys
import tarfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ROOT / "packages"
LICENSE = ROOT / "LICENSE"


def fail(message: str) -> None:
    """Exit with a validation error."""
    raise ValueError(message)


def archive_info(name: str, size: int, mode: int) -> tarfile.TarInfo:
    """Create normalized metadata for an archive entry."""
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = mode
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    return info


def package_files(package_dir: Path) -> list[tuple[str, Path]]:
    """Collect files included in a release archive."""
    files: list[tuple[str, Path]] = []
    for path in sorted(package_dir.rglob("*")):
        relative_path = path.relative_to(package_dir)
        if relative_path.parts[0] == "tests":
            continue
        if path.is_symlink():
            fail(f"{package_dir.name}: symbolic links are not allowed: {path.name}")
        if path.is_dir():
            continue
        if not path.is_file():
            fail(f"{package_dir.name}: unsupported package entry: {path.name}")
        files.append((relative_path.as_posix(), path))

    if not any(relative == "LICENSE" for relative, _ in files):
        files.append(("LICENSE", LICENSE))
    return sorted(files)


def write_archive(package_dir: Path, archive_path: Path) -> str:
    """Write a deterministic package archive."""
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with archive_path.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                for relative, path in package_files(package_dir):
                    data = path.read_bytes()
                    info = archive_info(relative, len(data), 0o644)
                    archive.addfile(info, io.BytesIO(data))

    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    checksum_path = archive_path.with_suffix(archive_path.suffix + ".sha256")
    checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    return digest


def main() -> int:
    """Run the command-line entry point."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--version")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    args = parser.parse_args()

    try:
        package_dir = PACKAGES / args.package
        manifest_path = package_dir / "package.toml"
        if not manifest_path.is_file():
            fail(f"unknown package: {args.package}")
        with manifest_path.open("rb") as handle:
            manifest = tomllib.load(handle)
        if manifest.get("name") != args.package:
            fail(f"{args.package}: manifest name does not match package directory")
        version = manifest.get("version")
        if not isinstance(version, str) or not version:
            fail(f"{args.package}: manifest version is missing")
        if args.version is not None and args.version != version:
            fail(
                f"{args.package}: requested version {args.version} does not match manifest {version}"
            )

        archive_path = args.output_dir / f"{args.package}-{version}.tar.gz"
        digest = write_archive(package_dir, archive_path)
    except (OSError, tarfile.TarError, tomllib.TOMLDecodeError, ValueError) as error:
        print(f"Package archive failed: {error}", file=sys.stderr)
        return 1

    print(f"archive={archive_path.resolve()}")
    print(f"sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
