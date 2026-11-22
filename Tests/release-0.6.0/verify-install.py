"""Verify the installed release without following framework symlinks."""
import hashlib
import json
import os
from pathlib import Path
import plistlib


def manifest(root):
    entries = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            if path.is_symlink():
                entries[relative] = ["link", os.readlink(path)]
            elif path.is_dir():
                entries[relative] = ["directory"]
            else:
                entries[relative] = ["file", hashlib.sha256(path.read_bytes()).hexdigest()]
    return entries


root = Path(__file__).resolve().parents[2]
built = root / "build/SuperCleaner.app"
installed = Path("/Applications/SuperCleaner.app")
expected = json.loads((root / "Version.json").read_text())
metadata = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
assert metadata["CFBundleShortVersionString"] == expected["version"]
assert metadata["CFBundleVersion"] == str(expected["build"])
built_entries = manifest(built)
assert built_entries == manifest(installed), "Installed app differs from the build"
resources = installed / "Contents/Resources/SuperCleaner_CleanerCore.bundle"
copies = {"en": "Reclaim your Mac. Clear the AI clutter.", "zh-Hans": "释放 Mac 空间，清理 AI 冗余。"}
for language, headline in copies.items():
    matches = list(resources.rglob(f"{language}.lproj/Localizable.strings"))
    assert len(matches) == 1
    assert headline in matches[0].read_text()
result = {
    "version": expected["version"],
    "build": str(expected["build"]),
    "verified_entries": len(built_entries),
    "installed_path": str(installed),
    "identical": True,
    "bilingual_headline": True,
}
(Path(__file__).parent / "install-verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
