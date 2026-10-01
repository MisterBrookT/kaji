#!/usr/bin/env python3
"""Generate a static, data-only update feed for a verified stable release."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('notes', type=Path)
    parser.add_argument('plist', type=Path)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', args.tag):
        raise ValueError('only stable vX.Y.Z release tags are accepted')
    info = plistlib.loads(args.plist.read_bytes())
    version = args.tag[1:]
    if any(int(part) > 2**63 - 1 for part in version.split('.')):
        raise ValueError('version components exceed supported integer range')
    if info['CFBundleShortVersionString'] != version:
        raise ValueError('release tag does not match bundle version')
    revision = subprocess.check_output(
        ['git', '-C', str(args.repo), 'rev-parse', '--verify', args.tag + '^{commit}'], text=True
    ).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('release must resolve to a full Git commit')
    checkout = subprocess.check_output(
        ['git', '-C', str(args.repo), 'rev-parse', 'HEAD'], text=True
    ).strip()
    if checkout != revision:
        raise ValueError('release tag does not match the built checkout commit')
    obj = {
        'schemaVersion': 1,
        'version': version,
        'build': int(info['CFBundleVersion']),
        'tag': args.tag,
        'releaseURL': 'https://github.com/MisterBrookT/kaji/releases/tag/' + args.tag,
        'sourceRevision': revision,
        'notes': args.notes.read_text(encoding='utf-8'),
    }
    print(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print('manifest generation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
