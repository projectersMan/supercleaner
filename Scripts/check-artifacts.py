import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='Read-only verification of a built app and matching DMG.')
parser.add_argument('--app', type=Path, default=ROOT / 'build/SuperCleaner.app')
parser.add_argument('--dmg', type=Path)
parser.add_argument('--installed-app', type=Path, help='Also compare an existing installed app; never installs or changes it.')
parser.add_argument('--output', type=Path, default=ROOT / 'Tests/temporary/artifact-verification.json')
args = parser.parse_args()
APP = args.app.resolve()
with (APP / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
DMG = (args.dmg or ROOT / f"build/SuperCleaner-{info['CFBundleShortVersionString']}.dmg").resolve()
configured = json.loads((ROOT / 'Version.json').read_text())
assert info['CFBundleShortVersionString'] == configured['version']
assert str(info['CFBundleVersion']) == str(configured['build'])


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        key = str(path.relative_to(root))
        if path.is_symlink():
            value = ('symlink', str(path.readlink()))
        elif path.is_file():
            value = ('file', path.stat().st_mode & 0o777, digest(path))
        elif path.is_dir():
            value = ('directory', path.stat().st_mode & 0o777)
        else:
            raise RuntimeError(f'Unsupported entry: {path}')
        result[key] = value
    return result


if os.environ.get('SUPERCLEANER_REQUIRE_STABLE_SIGNING', '0') == '1':
    subprocess.run(['zsh', str(ROOT / 'Scripts/check-stable-signing.sh'), str(APP)], check=True)
else:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(APP)], check=True)
if args.installed_app:
    assert inventory(APP) == inventory(args.installed_app.resolve()), 'Installed app differs from build output'
subprocess.run(['hdiutil', 'verify', str(DMG)], check=True)
with tempfile.TemporaryDirectory(prefix='supercleaner-artifact-check-') as mount:
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, str(DMG)], check=True)
    try:
        packaged = Path(mount) / APP.name
        source_inventory = inventory(APP)
        assert source_inventory == inventory(packaged), 'DMG app differs from build output'
        assert (Path(mount) / 'Applications').readlink() == Path('/Applications')
        with (packaged / 'Contents/Resources/HelperInfo.plist').open('rb') as stream:
            helper = plistlib.load(stream)
        for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
            assert helper[key] == info[key], f'Helper {key} mismatch'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(packaged)], check=True)
    finally:
        subprocess.run(['hdiutil', 'detach', mount], check=True)

record = {
    'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'working_tree_modified': subprocess.run(['git', 'diff', '--quiet'], cwd=ROOT).returncode != 0,
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'signature_verified': True,
    'dmg': str(DMG),
    'dmg_bytes': DMG.stat().st_size,
    'dmg_sha256': digest(DMG),
    'app_binary_sha256': digest(APP / 'Contents/MacOS/CleanerApp'),
    'matching_entries': len(source_inventory),
    'app_helper_versions_match': True,
    'disk_image_verified': True,
    'mounted_signature_verified': True,
    'disk_image_detached': True,
}
output = args.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
