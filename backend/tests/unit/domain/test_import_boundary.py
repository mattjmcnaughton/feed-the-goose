"""The domain is pure: it imports only the standard library and itself (TDD §5.1)."""

import ast
import sys
from pathlib import Path

import feed_the_goose.domain

DOMAIN = Path(feed_the_goose.domain.__file__).parent


def imported_modules(path: Path) -> set[str]:
    names: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(), filename=str(path))):
        if isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module)
    return names


def test_the_domain_imports_only_the_standard_library_and_itself() -> None:
    files = sorted(DOMAIN.rglob("*.py"))
    assert len(files) > 1

    outside = {
        f"{path.name}: {name}"
        for path in files
        for name in imported_modules(path)
        if not name.startswith("feed_the_goose.domain")
        and name.split(".")[0] not in sys.stdlib_module_names
    }

    assert outside == set()


def test_the_boundary_check_catches_a_forbidden_import(tmp_path: Path) -> None:
    bad = tmp_path / "bad.py"
    bad.write_text("import sqlalchemy\nfrom feed_the_goose import config\n")

    assert imported_modules(bad) == {"sqlalchemy", "feed_the_goose"}
