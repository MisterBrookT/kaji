import base64
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/sparkle-appcast.py'
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

class SparkleAppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        self.tools = self.root / 'bin'
        self.tools.mkdir()
        self.key = self.root / 'private-fixture.key'
        self.key.write_text('fixture-not-a-production-key')
        self.plist = self.root / 'Info.plist'
        self.plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.1', 'CFBundleVersion': '42', 'LSMinimumSystemVersion': '13.0'}))
        (self.dist / 'Kaji.app.zip').write_bytes(b'fixture archive')
        (self.dist / 'release-notes.md').write_text('### Fixed\n- Works in English.\n')
        self.signature = base64.b64encode(bytes(64)).decode()
        self.generator = self.tools / 'generate_appcast'
        self.generator.write_text('''#!/usr/bin/env python3
import pathlib, sys
args=sys.argv[1:]
assert '--ed-key-file' in args
assert pathlib.Path(args[args.index('--ed-key-file')+1]).is_file()
d=pathlib.Path(args[-1]); prefix=args[args.index('--download-url-prefix')+1]
(d/'appcast.xml').write_text(''' + repr(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>1.0.1</title><description>Notes</description><sparkle:version>42</sparkle:version><sparkle:shortVersionString>1.0.1</sparkle:shortVersionString><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><enclosure url="{{prefix}}Kaji.app.zip" length="15" type="application/octet-stream" sparkle:edSignature="{self.signature}" /></item></channel></rss>''') + '.format(prefix=prefix))\n')
        self.generator.chmod(0o755)
        self.verifier = self.tools / 'sign_update'
        self.verifier.write_text('''#!/usr/bin/env python3
import sys
assert '--verify' in sys.argv and '--ed-key-file' in sys.argv
''')
        self.verifier.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def generate(self, tag='v1.0.1', key=None):
        return subprocess.run(['python3', str(SCRIPT), tag, '--dist', str(self.dist), '--plist', str(self.plist), '--tools', str(self.tools), '--key-file', str(key or self.key)], capture_output=True, text=True)

    def testGeneratesCanonicalSignedFeedUsingExplicitKeyFile(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        item = ET.parse(self.dist / 'appcast.xml').find('./channel/item')
        self.assertEqual(item.find(NS + 'version').text, '42')
        self.assertEqual(item.find('enclosure').get('url'), 'https://github.com/MisterBrookT/kaji/releases/download/v1.0.1/Kaji.app.zip')
        self.assertEqual((self.dist / 'Kaji.app.md').read_text(), (self.dist / 'release-notes.md').read_text())

    def testMissingPrivateKeyFailsWithoutKeychainFallback(self):
        result = self.generate(key=self.root / 'missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dist / 'appcast.xml').exists())

    def testTagVersionMismatchFailsBeforeGenerating(self):
        result = self.generate(tag='v1.0.2')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dist / 'appcast.xml').exists())

    def testBadSignatureOrUnexpectedDownloadURLFails(self):
        original = self.generator.read_text()
        for changed in [original.replace(self.signature, 'bad'), original.replace('{prefix}Kaji.app.zip', 'https://evil.invalid/app.zip')]:
            self.generator.write_text(changed)
            result = self.generate()
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def testSignatureVerificationFailureAborts(self):
        self.verifier.write_text('#!/usr/bin/env python3\nraise SystemExit(1)\n')
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)

if __name__ == '__main__':
    unittest.main()
