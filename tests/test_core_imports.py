"""Enforce ADR-001: ridestream_core must not import any cloud code.

The check reads each source file as text and inspects its import
statements. It never runs the code, so it works even when the forbidden
package isn't installed.
"""

import ast
from pathlib import Path

CORE_DIR = Path(__file__).parent.parent / "src" / "ridestream_core"

# Top-level package names the core must never import.
FORBIDDEN = {
    "boto3",
    "botocore",
    "aws_lambda_powertools",
    "awslambdaric",
    "azure",
    "ridestream_aws",
}


def forbidden_imports(source: str) -> set[str]:
    """Return the forbidden top-level packages imported by `source`."""
    found = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            # `import boto3.session` -> "boto3.session"
            names = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.level == 0:
            # `from botocore.exceptions import ClientError` -> "botocore.exceptions"
            # level > 0 is a relative import (`from . import x`): always allowed.
            names = [node.module]
        else:
            continue
        for name in names:
            top_level = name.split(".")[0]
            if top_level in FORBIDDEN:
                found.add(top_level)
    return found


def test_checker_finds_every_import_form():
    source = (
        "import boto3\n"
        "import botocore.exceptions as exc\n"
        "from aws_lambda_powertools import Logger\n"
        "def late():\n"
        "    from ridestream_aws.taxis import DynamoTaxiRepository\n"
    )
    assert forbidden_imports(source) == {
        "boto3",
        "botocore",
        "aws_lambda_powertools",
        "ridestream_aws",
    }


def test_checker_allows_ordinary_imports():
    source = (
        "import json\n"
        "from dataclasses import dataclass\n"
        "from . import geohash\n"
        "from ridestream_core.trips import Trip\n"
        "import boto3_lookalike\n"
    )
    assert forbidden_imports(source) == set()


def test_core_has_no_cloud_imports():
    files = sorted(CORE_DIR.rglob("*.py"))
    assert files, f"no Python files found in {CORE_DIR}"

    violations = {}
    for path in files:
        found = forbidden_imports(path.read_text(encoding="utf-8"))
        if found:
            violations[str(path.relative_to(CORE_DIR))] = sorted(found)

    assert not violations, f"cloud imports in ridestream_core: {violations}"
