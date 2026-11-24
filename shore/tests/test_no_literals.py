"""No personal data, endpoints, or secret-looking strings under shore/."""
import re
from pathlib import Path

SHORE = Path(__file__).resolve().parents[1]

PATTERNS = {
    "email address": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "IPv4 address": re.compile(r"\b\d{1,3}(\.\d{1,3}){3}\b"),
    "tenant/account GUID": re.compile(
        r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
    ),
    "secret-looking token": re.compile(r"\b[A-Za-z0-9+/\-_]{32,}={0,2}\b"),
    "databricks workspace URL": re.compile(r"adb-\d+\.\d+\.azuredatabricks\.net"),
    "databricks account URL": re.compile(r"accounts\.azuredatabricks\.net"),
}

# Required bundle input documented in the task; not a secret.
# sat@databricks.com is upstream's public support contact, not a Shore person.
ALLOWLIST = {"eda6b2cb326f8e46", "sat@databricks.com"}


def _secret_like(token):
    """Long token must mix upper, lower and digits to look secret-ish."""
    return (
        any(c.isdigit() for c in token)
        and any(c.isupper() for c in token)
        and any(c.islower() for c in token)
        and "/" not in token
    )


TEXT_EXT = {".md", ".json", ".sql", ".py", ".txt", ".yml", ".yaml"}


def _files():
    return [
        p for p in SHORE.rglob("*")
        if p.is_file() and p.suffix in TEXT_EXT
    ]


def test_files_exist():
    names = {p.name for p in _files()}
    assert {"README.md", "RUNBOOK.md", "THIRD_PARTY.md",
            "template_answers.json", "review_checklist.md"} <= names


def test_no_forbidden_literals():
    hits = []
    for path in _files():
        if path.name == Path(__file__).name:
            continue  # the regexes themselves live in this file
        text = path.read_text()
        for label, rx in PATTERNS.items():
            for m in rx.finditer(text):
                token = m.group(0)
                if token in ALLOWLIST:
                    continue
                if label == "secret-looking token" and not _secret_like(token):
                    continue
                hits.append(f"{path.relative_to(SHORE)}: {label}: {token}")
    assert not hits, "forbidden literals found:\n" + "\n".join(hits)
