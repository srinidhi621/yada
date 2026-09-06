"""No certificates, Xcode build, network calls, or real app state are used."""
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import release

TEAM = 'ABCDEFGHIJ'
CERT = 'A' * 40
IDENTITIES = f' 1) {CERT} "Developer ID Application: Example ({TEAM})"\n'
DETAILS = f'Authority=Developer ID Application: Example ({TEAM})\nTeamIdentifier={TEAM}\nTimestamp=Sep 7 2026\nflags=0x10000(runtime)\n'


class ReleaseTests(unittest.TestCase):
    def test_only_one_correct_team_developer_id_accepted(self):
        self.assertEqual(release.choose_identity(IDENTITIES, TEAM)[0], CERT)
        for identities, team in [('', TEAM), (IDENTITIES, 'ZZZZZZZZZZ'),
                                 (IDENTITIES * 2, TEAM), (IDENTITIES, '-'),
                                 (IDENTITIES.replace('Developer ID Application:', 'Apple Development:'), TEAM)]:
            with self.subTest(identities=identities, team=team), self.assertRaises(RuntimeError):
                release.choose_identity(identities, team)

    def test_release_version_validation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(release, 'ROOT', Path(temp)):
            info = Path(temp) / 'Yada/Info.plist'
            info.parent.mkdir()
            for version, build, valid in [('0.1.0', '1', True), ('0.2.0', '12', True),
                                           ('../bad', '1', False), ('1.2', '1', False),
                                           ('1.2.3', '0', False), ('1.2.3', 'beta', False)]:
                info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': version, 'CFBundleVersion': build}))
                if valid:
                    self.assertEqual(release.version_info(), (version, build))
                else:
                    with self.assertRaises(RuntimeError):
                        release.version_info()

    def test_verify_rejects_adhoc_wrong_team_missing_timestamp_and_runtime(self):
        for details in ['Signature=adhoc\n', DETAILS.replace(TEAM, 'ZZZZZZZZZZ'),
                        DETAILS.replace('Timestamp=', 'NoTimestamp=').replace('NoTimestamp=Sep 7 2026\n', ''),
                        DETAILS.replace('(runtime)', '')]:
            with self.subTest(details=details), patch.object(release, 'run', side_effect=['', details]), self.assertRaises(RuntimeError):
                release.verify_signature(Path('Yada.app'), TEAM, app=True)

    def test_signed_entitlements_are_checked(self):
        for entitlements, valid in [({'com.apple.security.device.audio-input': True}, True),
                                     ({}, False),
                                     ({'com.apple.security.device.audio-input': True, 'com.apple.security.get-task-allow': True}, False)]:
            xml = plistlib.dumps(entitlements).decode()
            with patch.object(release, 'run', side_effect=['', DETAILS, 'Executable=/test\n' + xml]):
                if valid:
                    release.verify_signature(Path('Yada.app'), TEAM, app=True)
                else:
                    with self.assertRaises(RuntimeError):
                        release.verify_signature(Path('Yada.app'), TEAM, app=True)

    def test_failed_preflight_does_not_build(self):
        with patch.object(release, 'preflight', side_effect=RuntimeError('No identity')), patch.object(release, 'run') as run:
            with self.assertRaises(RuntimeError):
                release.build_release(TEAM)
            run.assert_not_called()

    def test_failed_tests_stop_before_release_build(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(release, 'ROOT', Path(temp)), patch.object(release, 'preflight', return_value=('0.1.0', '1', CERT)), patch.object(release, 'run', side_effect=RuntimeError('Test failed')) as run:
            with self.assertRaises(RuntimeError):
                release.build_release(TEAM)
            self.assertEqual(run.call_count, 1)
            self.assertIn('test', run.call_args.args)
            self.assertTrue((Path(temp) / '.build/releases/0.1.0-1/tests.log').exists())

    def test_build_packages_only_after_tests_and_signed_release(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(release, 'ROOT', Path(temp)), patch.object(release, 'preflight', return_value=('0.1.0', '1', CERT)), patch.object(release, 'verify_signature') as verify:
            def command(*args):
                if args[0] == 'xcodebuild' and 'build' in args:
                    app = Path(temp) / '.build/releases/0.1.0-1/DerivedData/Build/Products/Release/Yada.app'
                    (app / 'Contents').mkdir(parents=True)
                    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                        'CFBundleIdentifier': release.BUNDLE_ID,
                        'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1'}))
                return ''
            with patch.object(release, 'run', side_effect=command) as run:
                release.build_release(TEAM)
                calls = [call.args for call in run.call_args_list]
                self.assertIn('test', calls[0])
                self.assertIn('build', calls[1])
                self.assertIn('ENABLE_HARDENED_RUNTIME=YES', calls[1])
                self.assertIn(f'CODE_SIGN_IDENTITY={CERT}', calls[1])
                self.assertEqual([call[0] for call in calls[2:]], ['ditto', 'hdiutil', 'codesign'])
                self.assertEqual(verify.call_count, 2)
                self.assertTrue((Path(temp) / '.build/releases/0.1.0-1/DMG/Applications').is_symlink())

    def test_rejected_notarization_cannot_staple_or_write_checksum(self):
        with tempfile.TemporaryDirectory() as temp:
            dmg = Path(temp) / 'Yada.dmg'
            dmg.write_bytes(b'synthetic')
            with patch.object(release, 'verify_signature'), patch.object(release, 'run', return_value='{"status":"Invalid","id":"synthetic-id"}') as run:
                with self.assertRaises(RuntimeError):
                    release.notarize(dmg, TEAM, 'test-profile')
                self.assertEqual(run.call_count, 1)
                self.assertFalse(dmg.with_suffix('.dmg.sha256').exists())
                self.assertTrue((Path(temp) / 'Yada-notarization.json').exists())

    def test_notarization_acceptance_requires_staple_and_gatekeeper_before_checksum(self):
        with tempfile.TemporaryDirectory() as temp:
            dmg = Path(temp) / 'Yada.dmg'
            dmg.write_bytes(b'synthetic')
            with patch.object(release, 'verify_signature'), patch.object(release, 'run', side_effect=['{"status":"Accepted"}', '', '', '']) as run:
                release.notarize(dmg, TEAM, 'test-profile')
                self.assertEqual([call.args[:3] for call in run.call_args_list], [
                    ('xcrun', 'notarytool', 'submit'), ('xcrun', 'stapler', 'staple'),
                    ('xcrun', 'stapler', 'validate'), ('spctl', '--assess', '--type')])
                self.assertTrue(dmg.with_suffix('.dmg.sha256').exists())


if __name__ == '__main__':
    unittest.main()
