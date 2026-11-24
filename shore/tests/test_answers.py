"""template_answers.json must match the v0.8.0 bundle template schema."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads(
    (ROOT / "dabs/dabs_template/databricks_template_schema.json").read_text()
)
ANSWERS = json.loads((ROOT / "shore/template_answers.json").read_text())

QUARTZ_FIELD = re.compile(r"^[A-Za-z0-9*/?,\-#]+$")


def test_answer_keys_match_schema_properties():
    schema_keys = set(SCHEMA["properties"])
    assert set(ANSWERS) == schema_keys, (
        f"extra={set(ANSWERS) - schema_keys} missing={schema_keys - set(ANSWERS)}"
    )


def test_answer_types_match_schema():
    for key, spec in SCHEMA["properties"].items():
        val = ANSWERS[key]
        if spec["type"] == "boolean":
            assert isinstance(val, bool), f"{key} must be boolean"
        else:
            assert isinstance(val, str) and val, f"{key} must be a non-empty string"


def test_schedules_are_valid_quartz_cron():
    """Six fields: sec min hour dom mon dow (optional 7th year field)."""
    for key in ("driver_schedule", "secrets_scanner_schedule", "brickhound_schedule"):
        fields = ANSWERS[key].split()
        assert len(fields) in (6, 7), f"{key}: {len(fields)} fields"
        for f in fields:
            assert QUARTZ_FIELD.match(f), f"{key}: bad field {f!r}"
        assert fields[3] == "?" or fields[5] == "?", (
            f"{key}: Quartz requires ? in day-of-month or day-of-week"
        )


def test_timezone_is_iana():
    import zoneinfo

    zoneinfo.ZoneInfo(ANSWERS["job_timezone"])
