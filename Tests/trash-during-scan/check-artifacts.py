from pathlib import Path
import hashlib
import json
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QA = Path(__file__).resolve().parent
BUILT = ROOT / 'build/SuperCleaner.app'
INSTALLED = Path('/Applications/SuperCleaner.app')
MOUNT = QA / 'dmg-mount'
VERSION = json.loads((ROOT / 'Version.json').read_text())
DMG = ROOT / f"build/SuperCleaner-{VERSION['version']}.dmg"
EXECUTABLES = ['Contents/MacOS/CleanerApp', 'Contents/MacOS/AgentInference',
               'Contents/Library/LaunchServices/com.example.SuperCleaner.helper']


def inspect_bundle(app: Path) -> dict:
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    helper = plistlib.loads((app / 'Contents/Resources/HelperInfo.plist').read_bytes())
    for info in [metadata, helper]:
        assert info['CFBundleShortVersionString'] == VERSION['version'], info
        assert str(info['CFBundleVersion']) == str(VERSION['build']), info
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], check=True)
    result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], check=True, capture_output=True)
    assert plistlib.loads(result.stdout) == {'com.apple.security.automation.apple-events': True}
    return {name: hashlib.sha256((app / name).read_bytes()).hexdigest() for name in EXECUTABLES}


assert not BUILT.is_symlink() and BUILT.is_dir()
assert not MOUNT.exists()
expected = inspect_bundle(BUILT)
MOUNT.mkdir()
subprocess.run(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(MOUNT), str(DMG)], check=True)
try:
    assert inspect_bundle(MOUNT / 'SuperCleaner.app') == expected
finally:
    subprocess.run(['/usr/bin/hdiutil', 'detach', str(MOUNT)], check=True)
    MOUNT.rmdir()
report = {'version': VERSION, 'dmg_bytes': DMG.stat().st_size,
          'dmg_sha256': hashlib.sha256(DMG.read_bytes()).hexdigest(), 'executable_sha256': expected,
          'installed_version': plistlib.loads((INSTALLED / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString'],
          'installation_replaced': False}
(QA / 'artifact-check.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
print('PASS: built and mounted DMG metadata, strict signatures, entitlement, and three executable hashes match; existing installation is unchanged')
