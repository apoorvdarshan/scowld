#!/usr/bin/env python3
"""Print the reviewed release notes for an exact tag from RELEASE_NOTES.md.

Exit codes: 0 = notes printed; 3 = no section for this tag, or no RELEASE_NOTES.md
at all (the GitHub Release then uses GitHub's generated notes); 2 = the section
exists but is empty, the tag has more than one section, or the arguments are
wrong (the release fails rather than publishing empty or ambiguous notes).
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
bodies = []
for section in re.split(r'^## ', text, flags=re.MULTILINE)[1:]:
    title, _, body = section.partition('\n')
    if title.strip() == args.tag:
        bodies.append(body.strip())
if len(bodies) > 1:
    parser.error(f'RELEASE_NOTES.md has {len(bodies)} "## {args.tag}" sections; keep exactly one')
if bodies:
    if not bodies[0]:
        parser.error(f'the ## {args.tag} section of RELEASE_NOTES.md is empty')
    print(bodies[0])
    sys.exit(0)
print(f'no ## {args.tag} section in RELEASE_NOTES.md; GitHub will generate the notes', file=sys.stderr)
sys.exit(NO_SECTION)
