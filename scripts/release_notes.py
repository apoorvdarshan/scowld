#!/usr/bin/env python3
"""Print the reviewed release notes for an exact tag from RELEASE_NOTES.md.

Exit codes: 0 = notes printed; 3 = no section for this tag (the GitHub Release
then uses GitHub's generated notes); 2 = the section exists but is empty, or the
arguments are wrong (the release fails rather than publishing empty notes).
"""
import argparse
import re
import sys
from pathlib import Path

NO_SECTION = 3

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('tag', help='release tag, e.g. v2.0.2')
parser.add_argument('--file', type=Path, default=Path(__file__).resolve().parents[1] / 'RELEASE_NOTES.md')
args = parser.parse_args()
if args.tag == 'Unreleased':
    parser.error('pass a release tag, not Unreleased')

text = args.file.read_text(encoding='utf-8') if args.file.is_file() else ''
for section in re.split(r'^## ', text, flags=re.MULTILINE)[1:]:
    title, _, body = section.partition('\n')
    if title.strip() == args.tag:
        body = body.strip()
        if not body:
            parser.error(f'the ## {args.tag} section of RELEASE_NOTES.md is empty')
        print(body)
        sys.exit(0)
print(f'no ## {args.tag} section in RELEASE_NOTES.md; GitHub will generate the notes', file=sys.stderr)
sys.exit(NO_SECTION)
