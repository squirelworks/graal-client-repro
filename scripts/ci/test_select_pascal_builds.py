import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from select_pascal_builds import select_builds


class SelectionTests(unittest.TestCase):
    builds = ['graal-3.04-G3D03014', 'graal-4.20r8-G3D20126', 'graal-6.03r7-G3D0511C']

    def test_shared_and_build_paths_keep_all_clients(self):
        for path in [
            'common/GSocket.pas', 'common/torque/vm/Executor.pas',
            'common/torque/vm/ops.inc', 'common/torque/unknown/new-tool',
            'common/torque/shared/first_frame.cpp',
            'common/torque/host304/src/main.cpp',
            'scripts/tests/host_script_selection.py', 'scripts/build.sh',
            'scripts/ci/select_pascal_builds.py',
            'scripts/ci/test_select_pascal_builds.py',
            '.github/workflows/ci.yml', '.github/workflows/cpp-hosts.yml',
            '.github/workflows/host-boot.yml',
        ]:
            with self.subTest(path=path):
                self.assertEqual(select_builds([path], self.builds), sorted(self.builds))

    def test_client_source_selects_only_that_client(self):
        self.assertEqual(select_builds([
            self.builds[0] + '/src/client.pas', self.builds[0] + '/tests/test.dpr',
        ], self.builds), [self.builds[0]])

    def test_documentation_and_separate_3d_workflow(self):
        self.assertEqual(select_builds([
            'README.md', 'common/torque/README.md',
            'graal-3d-20000205/src/Graal3D.dpr',
        ], self.builds), [])

    def test_mixed_shared_and_client_change(self):
        self.assertEqual(select_builds([
            self.builds[0] + '/src/client.pas', 'common/torque/vm/VM.pas',
        ], self.builds), sorted(self.builds))

    def test_cli_does_not_delegate_to_missing_disabled_or_narrow_workflows(self):
        # Exercise the actual stdin/checkout discovery interface, including
        # misleading workflow files. Their presence must never suppress builds.
        selector = Path(__file__).with_name('select_pascal_builds.py')
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            destination = repo / 'scripts/ci/select_pascal_builds.py'
            destination.parent.mkdir(parents=True)
            shutil.copyfile(selector, destination)
            for folder in self.builds + ['graal-3d-20000205']:
                (repo / folder / 'src').mkdir(parents=True)
            workflows = repo / '.github/workflows'
            workflows.mkdir(parents=True)
            for fixture in [None, 'on: workflow_dispatch\njobs: {}\n',
                            'on:\n  pull_request:\n    paths: [common/torque/host304/**]\njobs: {}\n']:
                for name in ['cpp-hosts.yml', 'host-boot.yml']:
                    path = workflows / name
                    if fixture is not None:
                        path.write_text(fixture)
                for changed in ['common/torque/host304/src/main.cpp',
                                'common/torque/vm/VM.pas',
                                'scripts/tests/host_script_selection.py',
                                '.github/workflows/ci.yml',
                                'scripts/ci/select_pascal_builds.py']:
                    with self.subTest(workflow=fixture, changed=changed):
                        result = subprocess.run([sys.executable, str(destination)],
                                                input=changed + '\n', text=True,
                                                capture_output=True, check=True)
                        self.assertEqual(result.stdout.split(), sorted(self.builds))


if __name__ == '__main__':
    unittest.main()
