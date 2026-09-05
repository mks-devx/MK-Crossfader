#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('container_audit', Path(__file__).resolve().parents[1] / 'audit-installer-container.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ContainerPrivacyTests(unittest.TestCase):
    def test_package_payload_round_trip(self):
        with tempfile.TemporaryDirectory(prefix='mk-container-roundtrip-') as folder:
            root = Path(folder)
            payload = root / 'payload'
            payload.mkdir()
            (payload / 'example.txt').write_text('Public payload\n')
            subprocess.run(['pkgbuild', '--root', str(payload), '--identifier', 'org.example.container-test',
                            '--version', '1.0', str(root / 'original.pkg')], check=True, capture_output=True)
            subprocess.run(['pkgutil', '--expand', str(root / 'original.pkg'), str(root / 'expanded')], check=True)
            subprocess.run(['xar', '--distribution', '--compression=none', '-cf', str(root / 'public.pkg'),
                            'Bom', 'PackageInfo', 'Payload'], cwd=root / 'expanded', check=True, capture_output=True)
            audit.audit_container(root / 'public.pkg')
            subprocess.run(['pkgutil', '--expand-full', str(root / 'public.pkg'), str(root / 'full')], check=True)
            self.assertEqual((root / 'full/Payload/example.txt').read_text(), 'Public payload\n')

    def test_distribution_archive_omits_local_metadata(self):
        with tempfile.TemporaryDirectory(prefix='mk-container-tests-') as folder:
            root = Path(folder)
            (root / 'resource.txt').write_text('Public installer resource\n')
            for name, options in [('local.pkg', []), ('public.pkg', ['--distribution'])]:
                subprocess.run(['xar', '-cf', name, *options, 'resource.txt'], cwd=root, check=True, capture_output=True)
            with self.assertRaisesRegex(ValueError, 'ownership'):
                audit.audit_container(root / 'local.pkg')
            self.assertEqual(audit.audit_container(root / 'public.pkg'), 1)
            raw = (root / 'public.pkg').read_bytes()
            (root / 'truncated.pkg').write_bytes(raw[:30])
            with self.assertRaises(ValueError):
                audit.audit_container(root / 'truncated.pkg')
            (root / 'invalid.pkg').write_bytes(b'not a package')
            with self.assertRaises(ValueError):
                audit.audit_container(root / 'invalid.pkg')


if __name__ == '__main__':
    unittest.main()
