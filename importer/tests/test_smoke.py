"""Smoke test — proves the package is importable and the CLI entrypoint exists."""

import importlib


def test_package_imports() -> None:
    mod = importlib.import_module("importer")
    assert mod is not None


def test_cli_module_exists() -> None:
    mod = importlib.import_module("importer.cli")
    assert hasattr(mod, "main"), "importer.cli must expose a main() callable"
