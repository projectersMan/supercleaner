"""Local ad-hoc signing stays portable; certificate-only checks are explicit."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SigningTests(unittest.TestCase):
    def environment(self, **overrides):
        environment = dict(os.environ)
        for name in ['SUPERCLEANER_SIGN_IDENTITY', 'SUPERCLEANER_SIGN_IDENTITY_FILE',
                     'SUPERCLEANER_REQUIRE_STABLE_SIGNING']:
            environment.pop(name, None)
        environment.update(overrides)
        return environment

    def test_default_local_signing_does_not_require_a_certificate(self):
        result = subprocess.run(['zsh', str(ROOT / 'Scripts/signing-identity.sh')],
                                env=self.environment(), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '-')

    def test_default_local_mode_is_ad_hoc(self):
        result = subprocess.run(['zsh', str(ROOT / 'Scripts/signing-identity.sh'), '--mode'],
                                env=self.environment(), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'ad-hoc')

    def test_strict_mode_rejects_explicit_ad_hoc_identity(self):
        result = subprocess.run(['zsh', str(ROOT / 'Scripts/signing-identity.sh')],
                                env=self.environment(SUPERCLEANER_SIGN_IDENTITY='-',
                                                     SUPERCLEANER_REQUIRE_STABLE_SIGNING='1'),
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_missing_pinned_identity_in_strict_mode_does_not_switch_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            pin = Path(temporary) / 'identity.sha1'
            pin.write_text('0' * 40 + '\n')
            result = subprocess.run(['zsh', str(ROOT / 'Scripts/signing-identity.sh')],
                env=self.environment(SUPERCLEANER_SIGN_IDENTITY_FILE=str(pin),
                                     SUPERCLEANER_REQUIRE_STABLE_SIGNING='1'),
                text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('unavailable', result.stderr)
            self.assertEqual(result.stdout.strip(), '')

    def test_strict_disk_image_creation_rejects_ad_hoc_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Probe.app'
            executable = app / 'Contents/MacOS/Probe'
            executable.parent.mkdir(parents=True)
            shutil.copyfile('/usr/bin/true', executable)
            executable.chmod(0o755)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'com.example.SuperCleaner.SigningRegression',
                'CFBundleExecutable': 'Probe', 'CFBundlePackageType': 'APPL',
            }))
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            output = Path(temporary) / 'Probe.dmg'
            result = subprocess.run(['zsh', str(ROOT / 'Scripts/create-dmg.sh'), str(app), str(output)],
                env=self.environment(SUPERCLEANER_REQUIRE_STABLE_SIGNING='1'), text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('certificate-bound signing is required', result.stderr)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
