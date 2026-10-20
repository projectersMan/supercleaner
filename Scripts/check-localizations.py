#!/usr/bin/env python3
"""Check translated message coverage and placeholder parity without running the app."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_ROOT = ROOT / "Sources/CleanerCore/Resources"


def catalog(language):
    path = RESOURCE_ROOT / (language + ".lproj") / "Localizable.strings"
    values = json.loads(subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)]))
    # plist parsing accepts duplicates; reject them explicitly before they can hide translations.
    keys = re.findall(r'^("(?:[^"\\]|\\.)*")\s*=', path.read_text(), re.MULTILINE)
    assert len(keys) == len(set(keys)) == len(values), f"duplicate key in {path}"
    return values


english, chinese = catalog("en"), catalog("zh-Hans")
assert english.keys() == chinese.keys(), "language catalogs have different keys"
for key in english:
    expected = sorted(re.findall(r"\{\d+\}", key))
    for value in [english[key], chinese[key]]:
        assert value.strip(), f"empty translation: {key}"
        assert sorted(re.findall(r"\{\d+\}", value)) == expected, f"placeholder mismatch: {key}"
    assert not re.search(r"[\u4e00-\u9fff]", english[key]), f"untranslated English message: {key}"

for directory in ["CleanerApp", "CleanerCore"]:
    for path in (ROOT / "Sources" / directory).glob("*.swift"):
        for match in re.finditer(r'L10n\.text\(("(?:[^"\\]|\\.)*")', path.read_text()):
            key = json.loads(match[1])
            assert key in english, f"missing translation in {path.name}: {key}"

# Localize known bundled evidence at presentation time, without changing signed rule bytes.
rules = json.loads((RESOURCE_ROOT / "base-rules.json").read_text())
for rule in rules["rules"]:
    for field in ["ownershipEvidence", "regenerationEvidence"]:
        if field in rule:
            assert rule[field] in english, f"missing rule evidence translation: {rule[field]}"
print(f"PASS: {len(english)} bilingual messages, source coverage, rule evidence, and placeholder parity")
