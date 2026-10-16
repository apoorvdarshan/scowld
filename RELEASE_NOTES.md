# Release notes

The iOS Release workflow publishes the GitHub Release for a `v<version>` tag with
the section below whose heading is exactly that tag (for example `## v2.0.2`).
Without a matching section, GitHub's generated notes are used instead. An empty
matching section, or more than one section with the same heading, fails the
release rather than publishing empty or ambiguous notes.

App Store "What's New" text is separate: it lives in
`store/metadata/ios/<locale>/whats_new.txt` (see `store/README.md`).

## v2.1.0

- Live voice conversations with Google Gemini Live, OpenAI Realtime, and xAI Grok Voice. Speak while the companion talks to interrupt a reply.
- Optional Scowld Premium lets you talk without an API key, with weekly or yearly plans and non-expiring minute packs. Bring your own supported provider key with no Scowld subscription; provider fees apply.
- Choose and preview built-in voices, with live lip sync and optional captions.
- Share optional camera context with Premium, Gemini, or OpenAI. Grok Voice does not support camera vision.
- Start a live conversation with the optional on-device wake-name feature. Conversations end after 90 seconds of silence or when you leave the Chat tab or the app.
- Live transcripts are saved on your device, and past chats can be reused as conversation context.
- Optional one-time tips in About support development and unlock no features.
- Updated community links, including Scowld's Product Hunt page.

This update replaces typed chat and separate speech-to-text/text-to-speech settings with live voice. Claude, Ollama, and the other text-only integrations are no longer offered. Existing saved keys for Gemini, OpenAI, and xAI remain available in Own API Key mode.

- Unit and UI tests run on every pull request (GitHub Actions, iOS simulator).
- Releases are built, signed and uploaded by GitHub Actions; every store step has its own switch.

## v2.0.1

- Streamlined onboarding with direct Privacy Policy and Terms links
- Simplified the About screen
- Character settings now show an editable default name and system prompt with a Clear option
- Minor fixes and refinements
