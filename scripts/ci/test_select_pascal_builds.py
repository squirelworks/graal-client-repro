import unittest
from select_pascal_builds import select_builds

class SelectionTests(unittest.TestCase):
    builds = ['graal-3.04-G3D03014', 'graal-4.20r8-G3D20126', 'graal-6.03r7-G3D0511C']
    def test_cpp_only_changes_do_not_select_pascal(self):
        self.assertEqual(select_builds([
            'common/torque/shared/first_frame.cpp',
            'common/torque/host304/src/main.cpp',
            'scripts/tests/host_script_selection.py',
            'graal-3.04-G3D03014/RELEASE_NOTES.md',
            '.github/workflows/cpp-hosts.yml'], self.builds), [])
    def test_no_scoped_workflow_keeps_legacy_coverage(self):
        self.assertEqual(select_builds(['common/torque/host304/src/main.cpp'],
            self.builds, cpp_hosts_scoped=False), sorted(self.builds))
    def test_client_source_selects_only_that_client(self):
        self.assertEqual(select_builds([
            'graal-6.03r7-G3D0511C/src/Graal603.dpr'], self.builds),
            ['graal-6.03r7-G3D0511C'])
    def test_shared_pascal_still_selects_all(self):
        self.assertEqual(select_builds(['common/GSocket.pas'], self.builds), sorted(self.builds))
    def test_build_script_still_selects_all(self):
        self.assertEqual(select_builds(['scripts/build.sh'], self.builds), sorted(self.builds))
    def test_mixed_cpp_and_pascal_keeps_pascal(self):
        self.assertEqual(select_builds(['common/torque/shared/first_frame.cpp',
            'graal-3.04-G3D03014/tests/Test304.dpr'], self.builds), [self.builds[0]])
    def test_docs_selector_and_unrelated_paths(self):
        self.assertEqual(select_builds(['README.md', 'docs/v6-repro.md',
            'scripts/ci/select_pascal_builds.py', '.github/workflows/ci.yml',
            'graal-3d-20000205/src/Graal3D.dpr'], self.builds), [])
    def test_deduplicates_and_ignores_unknown_folders(self):
        self.assertEqual(select_builds([self.builds[0]+'/src/a.pas',
            self.builds[0]+'/tests/b.dpr', 'graal-unknown/src/a.pas'], self.builds), [self.builds[0]])

if __name__ == '__main__':
    unittest.main()
