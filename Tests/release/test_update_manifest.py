import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/update-manifest.py'

class UpdateManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        def git(*args):
            return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()
        self.git = git
        git('init', '-q')
        git('config', 'user.name', 'Fixture')
        git('config', 'user.email', 'fixture@example.invalid')
        self.plist = self.root / 'Info.plist'
        self.plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '41'}))
        git('add', 'Info.plist')
        git('commit', '-qm', 'Fixture')
        git('tag', 'v1.0.0')
        self.notes = self.root / 'notes.md'
        self.notes.write_text('### Fixed\n- 中文 "quotes" and newlines\n', encoding='utf-8')

    def tearDown(self):
        self.temp.cleanup()

    def generate(self, tag='v1.0.0'):
        return subprocess.run(['python3', str(SCRIPT), tag, str(self.notes), str(self.plist), '--repo', str(self.root)], capture_output=True, text=True)

    def testManifestPinsTagCommitAndPreservesNotes(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        obj = json.loads(result.stdout)
        self.assertEqual(obj['schemaVersion'], 1)
        self.assertEqual(obj['version'], '1.0.0')
        self.assertEqual(obj['build'], 41)
        self.assertEqual(obj['tag'], 'v1.0.0')
        self.assertEqual(obj['sourceRevision'], self.git('rev-parse', 'v1.0.0^{commit}'))
        self.assertEqual(obj['releaseURL'], 'https://github.com/MisterBrookT/kaji/releases/tag/v1.0.0')
        self.assertEqual(obj['notes'], self.notes.read_text())
        self.assertNotIn('command', obj)

    def testVersionMismatchFailsWithoutPublishingJSON(self):
        self.plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.1', 'CFBundleVersion': '41'}))
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def testRejectsTagDifferentFromBuiltCheckout(self):
        self.git('commit', '--allow-empty', '-qm', 'Different checkout')
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def testRejectsUntrustedOrPrereleaseTag(self):
        for tag in ['v1.0.0-beta.1', 'v1.0.0;touch /tmp/no', 'latest', '../v1.0.0', 'v01.0.0', 'v999999999999999999999.0.0']:
            result = self.generate(tag)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')

if __name__ == '__main__':
    unittest.main()
