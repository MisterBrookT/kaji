#!/usr/bin/env python3
"""Generate and verify a Sparkle feed with an explicit file key (never Keychain)."""
import argparse
import base64
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--dist', type=Path, default=Path('dist'))
    parser.add_argument('--plist', type=Path, default=Path('dist/Kaji.app/Contents/Info.plist'))
    parser.add_argument('--tools', type=Path, required=True)
    parser.add_argument('--key-file', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', args.tag):
        raise ValueError('stable vX.Y.Z tag required')
    # A missing key must never invoke Sparkle tools' default Keychain lookup.
    if not args.key_file.is_file() or not args.key_file.stat().st_size:
        raise ValueError('explicit private update-signing key file is missing or empty')
    info = plistlib.loads(args.plist.read_bytes())
    if args.tag != 'v' + info['CFBundleShortVersionString']:
        raise ValueError('tag does not match bundle version')
    archive = args.dist / 'Kaji.app.zip'
    if not archive.is_file():
        raise ValueError('verified Kaji.app.zip is missing')
    shutil.copyfile(args.dist / 'release-notes.md', args.dist / 'Kaji.app.md')
    prefix = f'https://github.com/MisterBrookT/kaji/releases/download/{args.tag}/'
    subprocess.run([str(args.tools / 'generate_appcast'), '--ed-key-file', str(args.key_file),
                    '--download-url-prefix', prefix, '--embed-release-notes',
                    '--maximum-deltas', '0', '--maximum-versions', '1', str(args.dist)], check=True)
    feed = args.dist / 'appcast.xml'
    items = ET.parse(feed).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('expected exactly one current update item')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('update enclosure is missing')
    # Accept the current SDK's item fields and the legacy enclosure attributes.
    version = item.findtext(NS + 'version') or enclosure.get(NS + 'version')
    short = item.findtext(NS + 'shortVersionString') or enclosure.get(NS + 'shortVersionString')
    if version != str(info['CFBundleVersion']) or short != info['CFBundleShortVersionString']:
        raise ValueError('appcast version/build does not match verified bundle')
    if enclosure.get('url') != prefix + 'Kaji.app.zip':
        raise ValueError('unexpected update download URL')
    if int(enclosure.get('length', '-1')) != archive.stat().st_size:
        raise ValueError('appcast archive length mismatch')
    signature = enclosure.get(NS + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('invalid Ed25519 archive signature')
    subprocess.run([str(args.tools / 'sign_update'), '--verify', '--ed-key-file', str(args.key_file),
                    str(archive), signature], check=True)
    # generate_appcast signs the feed when SURequireSignedFeed is set on its host.
    if info.get('SURequireSignedFeed'):
        subprocess.run([str(args.tools / 'sign_update'), '--verify', '--ed-key-file', str(args.key_file),
                        str(feed)], check=True)
    print('Sparkle appcast: version/build/URL/length and signatures verified')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        print('Sparkle appcast generation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
