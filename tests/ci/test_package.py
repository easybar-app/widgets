#!/usr/bin/env python3
"""Regression tests for release archive file selection."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE_SCRIPT = ROOT / "scripts" / "release" / "package.py"
SPEC = importlib.util.spec_from_file_location("easybar_widgets_package", PACKAGE_SCRIPT)
assert SPEC is not None and SPEC.loader is not None
package = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = package
SPEC.loader.exec_module(package)


class PackageFilesTests(unittest.TestCase):
    def test_includes_only_declared_files_and_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            package_dir = Path(temporary_directory)
            (package_dir / "package.toml").write_text("name = 'demo'\n", encoding="utf-8")
            (package_dir / "README.md").write_text("# Demo\n", encoding="utf-8")
            (package_dir / "widget.lua").write_text("return {}\n", encoding="utf-8")
            (package_dir / "module.lua").write_text("return {}\n", encoding="utf-8")
            assets = package_dir / "assets"
            assets.mkdir()
            (assets / "icon.svg").write_text("<svg/>\n", encoding="utf-8")
            (package_dir / ".env").write_text("TOKEN=secret\n", encoding="utf-8")
            (package_dir / "notes.md").write_text("do not ship\n", encoding="utf-8")

            files = package.package_files(
                package_dir,
                {
                    "kind": "widget",
                    "readme": "README.md",
                    "entrypoint": "widget.lua",
                    "exports": {"demo.module": "module.lua"},
                },
            )

        self.assertEqual(
            [relative for relative, _ in files],
            ["LICENSE", "README.md", "assets/icon.svg", "module.lua", "package.toml", "widget.lua"],
        )


if __name__ == "__main__":
    unittest.main()
