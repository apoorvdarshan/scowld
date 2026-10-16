# App Store Listing

App Store Connect submission details for Scowld v2.1.0, including live voice and optional Scowld Premium. Each field is in a code block for easy copy-paste.

> Reference copy. The release automation uploads the listing from
> [`store/metadata/ios/`](store/metadata/ios), which is exported from the live
> App Store listing and edited there before a release. See
> [store/README.md](store/README.md).

## App Name (30 chars max)

    Scowld - AI Voice Companion

## Subtitle (30 chars max)

    AI Voice Chat With Memory

## Promotional Text (170 chars max)

    Talk live with an animated AI companion who answers out loud. No API key needed with Scowld Premium, or bring your own Gemini, OpenAI or xAI key for free.

## Category

    Primary Category: Lifestyle
    Secondary Category: Entertainment

## Description

    Scowld is an AI voice companion built for natural, expressive conversations with an animated character. Talk with her live, and she answers out loud in the voice you pick. Use optional Scowld Premium with no API key, or bring your own key for free.

    WHAT YOU GET
    - Animated anime-style AI companion you talk with live, out loud
    - Live speech-to-speech, with no separate speech-to-text or text-to-speech step
    - Interrupt her anytime by speaking
    - Optional hands-free wake mode using Bella or your custom companion name
    - Optional Scowld Premium: no API key needed, with Google Gemini Live and 14 female voices
    - Or bring your own key with no Scowld subscription (provider fees apply): Google Gemini Live (14 female voices), OpenAI Realtime (4), or xAI Grok Voice (2)
    - Lip sync that follows her voice
    - Saved past chats you can reuse as conversation context
    - Custom character name and system prompt
    - Optional captions of what she says
    - Optional camera vision with Premium, Gemini, or OpenAI, off until you turn it on
    - Reply language that follows your iPhone language, or one you choose

    SCOWLD PREMIUM (OPTIONAL)
    Google Gemini Live with Scowld's own key, so there's nothing to set up.
    - Weekly: $6.99 a week, with 20 minutes a week
    - Yearly: $99.99 a year, with 50 minutes a month; new subscribers get a 3-day free trial that includes 10 minutes
    - Minute packs, no subscription needed: 20 minutes for $6.99, 60 for $16.99, or 150 for $34.99. They never expire and are used after a plan's minutes run out
    - Minutes count the time a Premium conversation is connected. Plan minutes reset each week or each month of the subscription year and don't roll over
    - US prices shown; other countries get local equivalents

    Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. The free trial converts to the paid yearly plan unless canceled at least 24 hours before it ends. Manage or cancel in the iPhone Settings app > [your name] > Subscriptions.

    PRIVACY AND SECURITY
    - No user account is required
    - With your own key, there's no subscription and nothing goes through a Scowld server; keys are stored in iOS Keychain, sent only to their provider, and never bundled in the app
    - With Premium, Scowld's server (hosted on Cloudflare) relays your conversation to Google Gemini Live in real time and doesn't store audio, camera frames, or transcripts
    - Optional one-time tips unlock nothing
    - Hands-free wake mode listens on device only for her name; nothing is sent before a live conversation starts
    - During a live conversation, microphone audio streams continuously to the provider (with Premium, through Scowld's server)
    - Camera frames are sent only while the camera is on, and Scowld doesn't record or store them
    - A live conversation ends after 90 seconds of silence, or when you leave the Chat tab or the app
    - Saved chats stay on your device
    - Scowld does not use Apple's TrueDepth API or ARKit face tracking, and does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data

    HOW IT WORKS
    1. Tap the mic and pick a Premium plan, or open Settings > Live Voice, choose Own API Key, and add a Gemini, OpenAI, or xAI key
    2. Pick a voice in Settings > Live Voice
    3. Tap the mic, or say her name with hands-free on, and talk naturally
    4. She hears you over one live connection and answers out loud while the companion lip syncs
    5. Each turn is saved on your device; switch past chats for separate contexts

    Website: https://scowld.xyz
    Blog: https://scowld.xyz/blog
    Instagram: https://www.instagram.com/apoorvcodes/
    Product Hunt: https://www.producthunt.com/products/scowld-2
    Terms of Use: https://scowld.xyz/terms
    Privacy Policy: https://scowld.xyz/privacy
    Contact: ad13dtu@gmail.com

    Not affiliated with Google, OpenAI, xAI, Apple, or Cloudflare.

## What's New (v2.1.0)

    Scowld 2.1 introduces live voice conversations.

    - Talk naturally with Google Gemini Live, OpenAI Realtime, or xAI Grok Voice, and interrupt replies by speaking.
    - Use optional Scowld Premium to talk without an API key, with weekly or yearly plans and non-expiring minute packs.
    - Bring your own supported provider key with no Scowld subscription; provider fees apply.
    - Choose and preview built-in voices, with live lip sync and optional captions.
    - Share optional camera context with Premium, Gemini, or OpenAI.
    - Live transcripts are saved on your device, and past chats can be reused as context.
    - Support development with optional one-time tips.

    This update replaces typed chat and separate speech-to-text/text-to-speech settings with live voice. Claude, Ollama, and the other text-only integrations are no longer offered. Existing saved keys for Gemini, OpenAI, and xAI remain available in Own API Key mode.

## Keywords (100 chars max)

    ai companion,voice chat,avatar,anime,gemini live,openai,grok,realtime,talk,chatbot,assistant

## Privacy URL

    https://scowld.xyz/privacy

## Terms URL

    https://scowld.xyz/terms

## Support URL

    https://scowld.xyz

## Marketing URL

    https://scowld.xyz

## Reviewer Notes

    No Scowld account or login is required. Reviewers can test Premium with sandbox
    purchases without supplying a provider API key.

    IMPORTANT - Scowld offers two ways to talk with the companion. Both are in
    Settings > Live Voice (Scowld Premium / Own API Key):
    - Scowld Premium (the default for new installs): no API key needed. It uses
      Google Gemini Live with Scowld's own key, through Scowld's server, and needs a
      Premium plan or a minute pack. It can be tested with a sandbox account.
    - Own API Key: bring-your-own-key (BYOK), with no Scowld subscription. Provider
      fees and usage limits apply. You enter your OWN API key for one of three live
      voice providers. The app has NO bundled or free provider keys for this mode.
      This is by design.

    Both run live, speech to speech: the model (Google Gemini Live, OpenAI Realtime,
    or xAI Grok Voice) hears the microphone and answers in its own voice. There is no
    separate speech-to-text or text-to-speech provider, so one key from the selected
    provider is all that Own API Key mode needs.

    Expected in-app guidance (not a crash or malfunction):
    - Scowld Premium without a plan or minutes: the Chat tab shows "Start Scowld
      Premium to talk to Bella." and tapping the mic opens the plans.
    - Own API Key without a key: the app shows "Add your Gemini API key in Settings
      to talk to Bella." (with the selected provider's name).

    To test Scowld Premium with a sandbox account:
    1. Complete onboarding and accept Privacy/Terms. The Premium plans are shown once
       after onboarding.
    2. Tap the mic on the Chat tab, or open Settings > Live Voice > Scowld Premium >
       See Premium Plans.
    3. Choose Weekly ($6.99/week, 20 minutes a week) or Yearly ($99.99/year, 50
       minutes a month, with a 3-day free trial including 10 minutes for eligible
       new subscribers) and
       confirm with the sandbox account.
    4. On the Chat tab, tap the mic button and speak. The companion answers out loud.
       Speak while she talks to interrupt her, and tap stop to end the conversation.
       Settings > Live Voice shows the minutes left. The eye icon (front camera) and
       the hands-free toggle work with Scowld Premium too.
    5. (Optional) Settings > Live Voice > Buy More Minutes sells minute packs (20, 60
       or 150 minutes; one-time purchases that never expire). Restore Purchases and
       Manage Subscription are in Settings > Live Voice too.

    To test with your own key:
    1. Complete onboarding and accept Privacy/Terms.
    2. Open Settings > Live Voice, choose Own API Key, choose a provider (e.g. Google
       Gemini Live), pick a voice, paste your API key, and tap Save.
    3. On the Chat tab, tap the mic button and speak. The companion answers out loud.
       Speak while she talks to interrupt her, and tap stop to end the conversation.
    4. (Optional) Tap the eye icon to let her see the front camera (Gemini or OpenAI
       only; the camera is off until you turn it on).
    5. (Optional) With the hands-free toggle beside the eye icon turned on, say "Bella"
       or "hey Bella" while the app is idle to start a live conversation.

    Scowld Premium plans are auto-renewing subscriptions and minute packs are
    consumable in-app purchases, managed with RevenueCat. About > Support Scowld
    offers optional one-time tips that unlock nothing. Provider API keys are entered
    by the user and stored in the iOS Keychain; with Own API Key, nothing goes through
    Scowld's server. Network access is required for live conversations. A live
    conversation ends by itself after 90 seconds of silence, and when you leave the
    Chat tab or the app goes to the background. The app is designed for iPhone and
    iPad.
