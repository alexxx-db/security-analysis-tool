"""Every review query must parse in the Databricks dialect."""
import re
from pathlib import Path

import pytest
import sqlglot

QUERIES = sorted((Path(__file__).resolve().parents[1] / "queries").glob("q*.sql"))

NAMED_PARAM = re.compile(r":[a-zA-Z_][a-zA-Z0-9_]*")


@pytest.mark.parametrize("path", QUERIES, ids=lambda p: p.name)
def test_query_parses(path):
    sql = path.read_text()
    # strip comment lines, then substitute named params with literals
    sql = "\n".join(
        line for line in sql.splitlines() if not line.strip().startswith("--")
    )
    sql = NAMED_PARAM.sub("'__param__'", sql)
    parsed = sqlglot.parse(sql, read="databricks")
    assert parsed, f"{path.name} produced no statements"
    assert all(stmt is not None for stmt in parsed), (
        f"{path.name} has a statement that failed to parse"
    )


def test_all_expected_queries_present():
    names = {p.name for p in QUERIES}
    expected = {
        "q01_manage_on_production.sql",
        "q02_external_use.sql",
        "q03_external_members.sql",
        "q04_admin_paths.sql",
        "q05_person_owned_production.sql",
        "q06_service_principal_users.sql",
    }
    assert names == expected
