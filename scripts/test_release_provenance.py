"""Linux unit checks for release guards, using synthetic zip metadata (never an IPA build)."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('provenance', Path(__file__).with_name('verify-unsigned-source.py'))
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class ReleaseProvenanceTests(unittest.TestCase):
    def test_annotated_tag_uses_peeled_commit(self):
        text = 'a' * 40 + '\trefs/tags/unsigned-x\n' + 'b' * 40 + '\trefs/tags/unsigned-x^{}\n'
        self.assertEqual(provenance.remote_tag_commit(text, 'unsigned-x'), 'b' * 40)
        self.assertIsNone(provenance.remote_tag_commit('', 'unsigned-x'))

    def test_different_or_unfinished_tests_do_not_authorize_release(self):
        sha = 'a' * 40
        cases = [dict(head_sha='b' * 40, status='completed', conclusion='success'),
                 dict(head_sha=sha, status='in_progress', conclusion=None),
                 dict(head_sha=sha, status='completed', conclusion='failure'),
                 dict(head_sha=sha, status='completed', conclusion='skipped')]
        self.assertIsNone(provenance.successful_test_run(cases, sha))
        cases.append(dict(id=42, head_sha=sha, status='completed', conclusion='success'))
        self.assertEqual(provenance.successful_test_run(cases, sha)['id'], 42)

    def test_skipped_required_ui_job_fails_closed(self):
        runs = json.dumps({'workflow_runs': [dict(id=1, head_sha='a' * 40, status='completed', conclusion='success')]})
        jobs = json.dumps({'jobs': [dict(name='Unit tests (TingyeTests)', conclusion='success'),
                                   dict(name='UI tests (TingyeUITests)', conclusion='skipped')]})
        with patch.object(provenance, 'run', side_effect=[runs, jobs]):
            with self.assertRaisesRegex(ValueError, 'Required unit/UI'):
                provenance.verify_tests('a' * 40)

    def test_packaged_and_sidecar_source_must_both_match(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'metadata-fixture.zip'
            sha = 'a' * 40
            info = dict(CFBundleShortVersionString='1.26.0', CFBundleVersion='143', TingyeSourceCommit=sha)
            def write():
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr('Payload/Tingye.app/Info.plist', plistlib.dumps(info))
            write()
            sidecar = path.with_name('Tingye-build-provenance.json')
            sidecar.write_text(json.dumps(dict(source_sha=sha, version='1.26.0', build='143')))
            provenance.verify_ipa(path, sha, '1.26.0', '143')
            info['TingyeSourceCommit'] = 'b' * 40
            write()
            with self.assertRaisesRegex(ValueError, 'Packaged source'):
                provenance.verify_ipa(path, sha, '1.26.0', '143')
            info['TingyeSourceCommit'] = sha
            write()
            sidecar.write_text(json.dumps(dict(source_sha='b' * 40, version='1.26.0', build='143')))
            with self.assertRaisesRegex(ValueError, 'sidecar'):
                provenance.verify_ipa(path, sha, '1.26.0', '143')

    def test_stale_build_and_disagreeing_configurations_fail(self):
        with patch.object(provenance.Path, 'read_text', return_value='MARKETING_VERSION = 1.25.0; CURRENT_PROJECT_VERSION = 142;'):
            with self.assertRaisesRegex(ValueError, 'old marketing'):
                provenance.project_version()
        with patch.object(provenance.Path, 'read_text', return_value='MARKETING_VERSION = 1.26.0; CURRENT_PROJECT_VERSION = 143; CURRENT_PROJECT_VERSION = 144;'):
            with self.assertRaisesRegex(ValueError, 'disagree'):
                provenance.project_version()

    def test_reused_or_lower_build_is_rejected_even_under_a_new_tag(self):
        names = '听页 1.25.0 (142)\n听页 1.26.0 (143) 预发布'
        provenance.require_fresh_build(names, '144')
        for build in ['142', '143']:
            with self.assertRaisesRegex(ValueError, 'already been used'):
                provenance.require_fresh_build(names, build)

        release = dict(name='听页 1.26.0 (143) UNTESTED', prerelease=True,
                       assets=[dict(name='Tingye-build-provenance.json', id=1)])
        manifest = dict(source_sha='a' * 40, version='1.26.0', build='143')
        provenance.validate_verified_build([release], 'a' * 40, '1.26.0', '143', lambda _: manifest)
        with self.assertRaisesRegex(ValueError, 'different source'):
            provenance.validate_verified_build([release], 'b' * 40, '1.26.0', '143', lambda _: manifest)

    def test_remote_wrong_tag_commit_fails_before_publish(self):
        with patch.object(provenance.subprocess, 'run'), patch.object(provenance, 'run', return_value='b' * 40 + '\trefs/tags/unsigned-x\n'):
            with self.assertRaisesRegex(ValueError, 'targets'):
                provenance.verify_tag('unsigned-x', 'a' * 40)


if __name__ == '__main__':
    unittest.main()
