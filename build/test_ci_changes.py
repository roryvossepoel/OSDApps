import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from ci_changes import changed_files, icon_only, main, validate_icons

SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M0 0h10v10z"/></svg>'


class ChangesTests(unittest.TestCase):
    def test_icon_edits_and_additions(self):
        self.assertTrue(icon_only([('M', 'metadata/icons/7zip.svg'), ('A', 'metadata/icons/new.svg')]))

    def test_mixed_deleted_renamed_unknown_and_empty_changes_run_full(self):
        for changes in [[], [('D', 'metadata/icons/7zip.svg')], [('T', 'metadata/icons/7zip.svg')],
                        [('M', 'metadata/icons/7zip.svg'), ('M', 'Public/Test.ps1')],
                        [('M', 'metadata/builtins.json')], [('M', '.github/workflows/ci.yml')],
                        [('M', 'README.md')], [('M', 'metadata/icons/sub/icon.svg')],
                        [('D', 'metadata/icons/old.svg'), ('A', 'metadata/icons/new.svg')]]:
            with self.subTest(changes=changes):
                self.assertFalse(icon_only(changes))

    def test_manual_dispatch_runs_full(self):
        self.assertFalse(icon_only(changed_files('workflow_dispatch', {})))

    def test_push_diff_covers_multiple_commits(self):
        with tempfile.TemporaryDirectory() as folder:
            def git(*args):
                return subprocess.check_output(['git', '-C', folder, *args]).decode().strip()
            git('init', '-q'); git('config', 'user.email', 'ci@example.invalid'); git('config', 'user.name', 'CI')
            path = Path(folder, 'metadata/icons/7zip.svg'); path.parent.mkdir(parents=True); path.write_text(SVG)
            git('add', '.'); git('commit', '-qm', 'base'); base = git('rev-parse', 'HEAD')
            path.write_text(SVG + '\n'); git('commit', '-qam', 'icon'); icon_head = git('rev-parse', 'HEAD')
            Path(folder, 'module.ps1').write_text('Get-Date'); git('add', '.'); git('commit', '-qm', 'code')
            head = git('rev-parse', 'HEAD')
            with patch('ci_changes.git', side_effect=lambda *args: subprocess.check_output(['git', '-C', folder, *args])):
                self.assertTrue(icon_only(changed_files('push', {'before': base, 'after': icon_head})))
                self.assertFalse(icon_only(changed_files('push', {'before': base, 'after': head})))
                self.assertFalse(icon_only(changed_files('pull_request', {'pull_request': {'base': {'sha': base}, 'head': {'sha': head}}})))

    def test_missing_history_and_first_push_fall_back_to_full(self):
        for event in [{'before': '0' * 40, 'after': 'a' * 40}, {'before': 'a' * 40, 'after': 'b' * 40}]:
            with self.subTest(event=event), tempfile.TemporaryDirectory() as folder:
                event_path, output = Path(folder, 'event.json'), Path(folder, 'output')
                event_path.write_text(json.dumps(event))
                with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event_path), GITHUB_EVENT_NAME='push', GITHUB_OUTPUT=str(output), GITHUB_STEP_SUMMARY=''), patch('ci_changes.git', side_effect=OSError('missing history')), patch('ci_changes.validate_icons', return_value=15):
                    main()
                self.assertEqual(output.read_text(), 'run_module=true\n')

    def test_valid_and_malformed_svg(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder, 'icon.svg'); path.write_text(SVG)
            self.assertEqual(validate_icons(Path(folder)), 1)
            path.write_text(SVG.replace('viewBox="0 0 64 64"', 'width="64px" height="64"'))
            self.assertEqual(validate_icons(Path(folder)), 1)
            for invalid in ['<svg', '<html/>', SVG.replace('0 0 64 64', '0 0 0 64'), SVG.replace('0 0 64 64', '0 0 NaN 64'), '<!DOCTYPE svg>' + SVG]:
                with self.subTest(invalid=invalid):
                    path.write_text(invalid)
                    with self.assertRaises(Exception):
                        validate_icons(Path(folder))


if __name__ == '__main__':
    unittest.main()
