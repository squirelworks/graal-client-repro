#!/usr/bin/env python3
"""Checks for profiles.py: manifests as build inputs (#152).

  python3 common/torque/manifests/test_profiles.py

The fpc cases are skipped when Free Pascal is not on PATH.
Modern test harness, not historical client code.
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import profiles  # noqa: E402

FPC = shutil.which(os.environ.get("FPC", "fpc"))


class ManifestChecks(unittest.TestCase):
    def setUp(self):
        self.table = profiles.read_cuts()

    def test_every_manifest_matches_cuts(self):
        self.assertEqual(profiles.check_all(), sorted(profiles.COLUMNS))

    def test_module_marked_no_is_rejected(self):
        with self.assertRaisesRegex(profiles.ProfileError, "console is 'no'"):
            profiles.check_profile("4.2.0.8-g3d", ["console", "sim", "gui", "gameobject", "net-torque"], self.table)

    def test_module_the_note_does_not_name_is_rejected(self):
        with self.assertRaisesRegex(profiles.ProfileError, "actionmap is '—'"):
            profiles.check_profile("4.2.0.8-g3d", ["sim", "gui", "actionmap", "gameobject", "net-torque"], self.table)

    def test_residual_names_are_not_linked(self):
        with self.assertRaisesRegex(profiles.ProfileError, "gui is 'names'"):
            profiles.check_profile("6.x", ["gui"], self.table)

    def test_linked_module_left_out_is_rejected(self):
        mods = profiles.read_manifest(profiles.manifest_path("3.04"))
        mods.remove("sim")
        with self.assertRaisesRegex(profiles.ProfileError, "CUTS.md links sim"):
            profiles.check_profile("3.04", mods, self.table)

    def test_unknown_module_and_program_are_rejected(self):
        with self.assertRaisesRegex(profiles.ProfileError, "not a CUTS.md module"):
            profiles.check_profile("3.04", ["renderer"], self.table)
        with self.assertRaisesRegex(profiles.ProfileError, "no CUTS.md column"):
            profiles.check_profile("9.99", [], self.table)

    def test_synthetic_profile(self):
        # A neutral table and program, independent of any real client.
        table = {"synthetic": {"sim": "yes", "gui": "yes", "console": "no", "math": "—"}}
        profiles.COLUMNS["synthetic"] = "synthetic"
        try:
            profiles.check_profile("synthetic", ["gui", "sim"], table)
            for bad in (["gui"], ["gui", "sim", "console"], ["gui", "sim", "math"]):
                with self.subTest(mods=bad), self.assertRaises(profiles.ProfileError):
                    profiles.check_profile("synthetic", bad, table)
        finally:
            del profiles.COLUMNS["synthetic"]

    def test_manifest_syntax(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.list")
            with open(p, "w") as f:
                f.write("# comment\n\nsim  # trailing\ngui\n")
            self.assertEqual(profiles.read_manifest(p), ["sim", "gui"])
            for text, err in (("sim\nsim\n", "listed twice"), ("../gui\n", "not a module directory")):
                with open(p, "w") as f:
                    f.write(text)
                with self.subTest(text=text), self.assertRaisesRegex(profiles.ProfileError, err):
                    profiles.read_manifest(p)


@unittest.skipUnless(FPC, "Free Pascal not on PATH")
class ProfileBuilds(unittest.TestCase):
    def test_every_profile_builds_from_its_manifest(self):
        for name in profiles.all_names():
            mods = profiles.read_manifest(profiles.manifest_path(name))
            with self.subTest(program=name), tempfile.TemporaryDirectory() as d:
                r = profiles.build(name, mods, d, FPC)
                self.assertEqual(r.returncode, 0, r.stdout)
                with open(os.path.join(d, profiles.program_name(name) + ".dpr")) as f:
                    src = f.read()
                for m in mods:
                    self.assertIn(profiles.module_unit(m), src)

    def test_unlisted_module_cannot_link(self):
        # 4.2.0.8's 2D engine does not link sim; its unit is not on the path.
        name = "4.2.0.8-engine"
        mods = profiles.read_manifest(profiles.manifest_path(name))
        self.assertNotIn("sim", mods)
        with tempfile.TemporaryDirectory() as d:
            r = profiles.build(name, mods, d, FPC, extra_units=["TqSim"])
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertIn("TqSim", r.stdout)


if __name__ == "__main__":
    unittest.main()
