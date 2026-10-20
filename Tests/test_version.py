import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("version", Path(__file__).resolve().parents[1] / "Scripts/version.py")
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def test_bumps_keep_build_monotonic(self):
        original = {"version": "2.3.4", "build": 99}
        self.assertEqual(version.increment(original), {"version": "2.3.5", "build": 100})
        self.assertEqual(version.increment(original, "patch"), {"version": "2.3.5", "build": 100})
        self.assertEqual(original["build"], 99)

    def test_initial_version_and_repeated_changes_only_increment_last_component(self):
        current = {"version": "0.0.0", "build": 1}
        for patch in range(1, 12):
            current = version.increment(current)
            self.assertEqual(current, {"version": f"0.0.{patch}", "build": patch + 1})
        # No decimal carry into the human-controlled components.
        self.assertEqual(version.increment({"version": "2.3.99", "build": 100}),
                         {"version": "2.3.100", "build": 101})

    def test_routine_changes_cannot_change_major_or_minor_or_only_build(self):
        for part in ["major", "minor", "build"]:
            with self.assertRaises(ValueError):
                version.increment({"version": "0.0.0", "build": 1}, part)

    def test_release_overrides_are_validated(self):
        original = {"version": "0.0.1", "build": 2}
        self.assertEqual(version.resolve(original, {"SUPERCLEANER_VERSION": "0.0.1", "SUPERCLEANER_BUILD_NUMBER": "42"}),
                         {"version": "0.0.1", "build": 42})
        self.assertEqual(version.resolve(original, {}), original)
        for value in ["0", "-1", "01", "", "1.2", "1\n2", "1" * 19]:
            with self.assertRaises(ValueError):
                version.resolve(original, {"SUPERCLEANER_BUILD_NUMBER": value})
        for value in ["1.0", "01.0.0", "v1.0.0", "1.0.0-beta", "", "1.0.0\n"]:
            with self.assertRaises(ValueError):
                version.resolve(original, {"SUPERCLEANER_VERSION": value})
        for value in ["1.0.1", "0.1.1", "0.0.2"]:
            with self.assertRaises(ValueError):
                version.resolve(original, {"SUPERCLEANER_VERSION": value})

    def test_default_bump_command_changes_the_checked_in_source_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Scripts").mkdir()
            script = root / "Scripts/version.py"
            script.write_text(Path(version.__file__).read_text())
            path = root / "Version.json"
            version.save({"version": "0.0.0", "build": 1}, path)
            result = subprocess.run([sys.executable, str(script), "bump"], capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout.strip(), "0.0.1 (2)")
            self.assertEqual(version.read_version(path), {"version": "0.0.1", "build": 2})
            for part in ["major", "minor", "build"]:
                result = subprocess.run([sys.executable, str(script), "bump", part], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(version.read_version(path), {"version": "0.0.1", "build": 2})

    def test_round_trip_and_invalid_writes_preserve_previous_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Version.json"
            original = {"version": "1.2.3", "build": 8}
            version.save(original, path)
            self.assertEqual(version.read_version(path), original)
            with self.assertRaises(ValueError):
                version.save({"version": "bad", "build": 9}, path)
            self.assertEqual(version.read_version(path), original)
            version.save(version.increment(original, "patch"), path)
            self.assertEqual(version.read_version(path), {"version": "1.2.4", "build": 9})

    def test_build_overflow_is_rejected(self):
        with self.assertRaises(ValueError):
            version.increment({"version": "1.2.3", "build": version.MAX_BUILD}, "patch")

    def test_invalid_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Version.json"
            for value in ['{"version":"1.0.0","build":true}', '{"version":"1.0.0","build":1,"extra":2}', "[]"]:
                path.write_text(value)
                with self.assertRaises(ValueError):
                    version.read_version(path)


if __name__ == "__main__":
    unittest.main()
