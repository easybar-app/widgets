#!/usr/bin/env python3
"""Regression tests for package dependency compatibility validation."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATE_PATH = ROOT / "scripts" / "ci" / "validate.py"
SPEC = importlib.util.spec_from_file_location("easybar_widgets_validate", VALIDATE_PATH)
assert SPEC is not None and SPEC.loader is not None
validate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate
SPEC.loader.exec_module(validate)


def constraint(value: str):
    parsed = validate.VersionConstraint.parse(value)
    assert parsed is not None
    return parsed


def manifests(requirements: dict[str, str]):
    result = {
        "shared": (Path("packages/shared"), {"kind": "library", "dependencies": {}}),
    }
    for package, package_constraint in requirements.items():
        result[package] = (
            Path(f"packages/{package}"),
            {"kind": "widget", "dependencies": {"shared": package_constraint}},
        )
    return result


class VersionConstraintTests(unittest.TestCase):
    def test_caret_boundaries_match_easybar(self) -> None:
        cases = (
            ("^1.2.3", "1.9.9", True),
            ("^1.2.3", "2.0.0", False),
            ("^0.2.3", "0.2.9", True),
            ("^0.2.3", "0.3.0", False),
            ("^0.0.3", "0.0.3", True),
            ("^0.0.3", "0.0.4", False),
        )
        for raw_constraint, raw_version, expected in cases:
            with self.subTest(constraint=raw_constraint, version=raw_version):
                version = validate.SemanticVersion.parse(raw_version)
                assert version is not None
                self.assertEqual(constraint(raw_constraint).contains(version), expected)

    def test_exact_constraints_accept_equal_prefix(self) -> None:
        parsed = validate.VersionConstraint.parse("=1.2.3")
        self.assertIsNotNone(parsed)
        assert parsed is not None
        version = validate.SemanticVersion.parse("1.2.3")
        assert version is not None
        self.assertTrue(parsed.contains(version))

    def test_unsupported_constraint_is_rejected(self) -> None:
        self.assertIsNone(validate.VersionConstraint.parse(">=1.0.0"))
        self.assertIsNone(validate.VersionConstraint.parse("~1.0.0"))


class DependencyCompatibilityTests(unittest.TestCase):
    def test_overlapping_caret_constraints_are_compatible(self) -> None:
        constraints = [constraint("^0.1.0"), constraint("^0.1.5")]
        self.assertTrue(validate.constraints_are_compatible(constraints))

    def test_exact_version_inside_caret_is_compatible(self) -> None:
        constraints = [constraint("^1.2.0"), constraint("1.4.3")]
        self.assertTrue(validate.constraints_are_compatible(constraints))

    def test_incompatible_caret_constraints_fail_with_consumers(self) -> None:
        package_manifests = manifests({"github": "^0.1.0", "new-widget": "^0.2.0"})
        with self.assertRaisesRegex(
            ValueError,
            r"(?s)library 'shared'.*github requires \^0\.1\.0.*new-widget requires \^0\.2\.0",
        ):
            validate.validate_dependency_compatibility(package_manifests)

    def test_incompatible_exact_versions_are_rejected(self) -> None:
        constraints = [constraint("1.2.3"), constraint("1.2.4")]
        self.assertFalse(validate.constraints_are_compatible(constraints))


if __name__ == "__main__":
    unittest.main()
