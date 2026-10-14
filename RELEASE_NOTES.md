# Release notes

The iOS Release workflow publishes the GitHub Release for a `v<version>` tag with
the section below whose heading is exactly that tag (for example `## v2.0.2`).
Without a matching section, GitHub's generated notes are used instead. An empty
matching section, or more than one section with the same heading, fails the
release rather than publishing empty or ambiguous notes.

App Store "What's New" text is separate: it lives in
`store/metadata/ios/<locale>/whats_new.txt` (see `store/README.md`).

## Unreleased

- Unit and UI tests run on every pull request (GitHub Actions, iOS simulator).
- Releases are built, signed and uploaded by GitHub Actions; every store step has its own switch.

## v2.0.1

- Streamlined onboarding with direct Privacy Policy and Terms links
- Simplified the About screen
- Character settings now show an editable default name and system prompt with a Clear option
- Minor fixes and refinements
