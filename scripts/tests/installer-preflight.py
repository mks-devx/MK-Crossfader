#!/usr/bin/env python3
"""Exercise release configuration gates without building or signing artifacts."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallerPreflightTests(unittest.TestCase):
    def test_configuration_gates(self):
        source = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="mk-installer-preflight-") as folder:
            root = Path(folder)
            for relative in (
                "scripts/build-installer.sh",
                "macos-app/packaging/Info.plist",
                "vst3/CMakeLists.txt",
            ):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / relative, target)
            audit = root / "scripts/audit-release.sh"
            audit.write_text("#!/bin/zsh\nprint 'PREFLIGHT_REACHED'\nexit 71\n")
            audit.chmod(0o700)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            names = ("APP_SIGNING_IDENTITY", "INSTALLER_SIGNING_IDENTITY", "NOTARY_PROFILE")
            env = {key: value for key, value in os.environ.items() if key not in names}
            cases = [
                ([], {}, 1, "Release builds require"),
                ([], {names[0]: "test"}, 1, "Release builds require"),
                ([], {names[0]: "test", names[1]: "test"}, 1, "Release builds require"),
                ([], {names[2]: "test"}, 1, "Release builds require"),
                ([], dict.fromkeys(names, "test"), 1, "clean Git checkout"),
                (["--local-test"], {}, 71, "PREFLIGHT_REACHED"),
                (["--local-test"], dict.fromkeys(names, "test"), 1, "cannot use signing"),
                (["--invalid"], {}, 2, "Usage:"),
            ]
            for args, settings, code, message in cases:
                with self.subTest(args=args, configured=list(settings)):
                    result = subprocess.run(
                        ["zsh", str(root / "scripts/build-installer.sh"), *args],
                        env={**env, **settings}, capture_output=True, text=True,
                        timeout=20,
                    )
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                    self.assertIn(message, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
