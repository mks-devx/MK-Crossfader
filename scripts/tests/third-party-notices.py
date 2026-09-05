from pathlib import Path
import unittest


class ThirdPartyNoticesTests(unittest.TestCase):
    def test_binary_distribution_notices_are_bundled(self):
        root = Path(__file__).resolve().parents[2]
        notices = (root / "THIRD_PARTY_NOTICES.md").read_text()
        required = {
            "Steinberg VST3 SDK": "MIT License",
            "HarfBuzz": "COPYRIGHT HOLDER SPECIFICALLY DISCLAIMS",
            "SheenBidi": "Copyright (C) 2014-2025 Muhammad Tayyab Akram",
            "libpng": "The PNG Reference Library Authors",
            "zlib": "1995-2022 Jean-loup Gailly and Mark Adler",
            "Independent JPEG Group": "This software is based in part on the work of the Independent JPEG Group.",
        }
        for component, attribution in required.items():
            with self.subTest(component=component):
                self.assertIn("### " + component, notices)
                self.assertIn(attribution, notices)
        self.assertIn("Version 2.0, January 2004", notices)
        self.assertIn("The above copyright notice and this permission notice", notices)
        packaging = (root / "scripts/build-installer.sh").read_text()
        self.assertIn('cp "$ROOT/THIRD_PARTY_NOTICES.md"', packaging)


if __name__ == "__main__":
    unittest.main()
