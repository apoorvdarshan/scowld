# App Store Listing

App Store Connect submission details for Scowld. Each field is in a code block for easy copy-paste. The description, keywords and reviewer notes describe the live voice update that follows v2.0.1; What's New is still the v2.0.1 text.

> Reference copy. The release automation uploads the listing from
> [`store/metadata/ios/`](store/metadata/ios), which is exported from the live
> App Store listing and edited there before a release. See
> [store/README.md](store/README.md).

## App Name (30 chars max)

    Scowld - AI Voice Companion

## Subtitle (30 chars max)

    AI Voice Chat With Memory

## Promotional Text (170 chars max)

    Talk hands-free, by voice, or by text with an animated AI companion. Version 2.0 adds bring-your-own-key providers and removes the paywall.

## Category

    Primary Category: Lifestyle
    Secondary Category: Entertainment

## Description

    Scowld is an AI voice companion built for natural, expressive conversations with an animated character. Talk with her live, and she answers out loud in the voice you pick. Save conversations and personalize the companion experience from a polished iOS interface.

    WHAT YOU GET
    - Animated anime-style AI companion you talk with live, out loud
    - Live speech-to-speech: the provider you choose hears you directly and answers in its own voice, with no separate speech-to-text or text-to-speech step
    - Interrupt her anytime by speaking
    - Optional hands-free wake mode using Bella or your custom companion name
    - Bring-your-own-key providers: Google Gemini Live, OpenAI Realtime, and xAI Grok Voice
    - Each provider's built-in female voices: 14 with Gemini, 4 with OpenAI including Marin and Coral, and 2 with xAI
    - Lip sync that follows her voice
    - Saved past chats that can be reused as conversation context
    - Custom character name and system prompt controls
    - Optional captions of what she says
    - Optional camera vision with Gemini or OpenAI, off until you turn it on
    - Reply language that follows your iPhone language, or one you choose
    - App Store update checks, rating, sharing, contact, and social links in About

    PRIVACY AND SECURITY
    - No user account is required
    - Provider API keys are entered by you, stored in iOS Keychain, and sent only to that provider
    - Provider API keys are not bundled in the app and are not stored in plain app preferences
    - No subscriptions, paywall, Billing tab, voice credits, or extra credit packs; optional one-time tips unlock nothing
    - Hands-free wake mode listens on device, with Apple's on-device speech recognition, only for her name; nothing is sent before a live conversation starts
    - During a live conversation, microphone audio streams continuously to the provider you chose
    - Camera frames go to the provider only while the camera is on, and Scowld doesn't record or store them
    - A live conversation ends after 90 seconds of silence, or when you leave the Chat tab or the app
    - Saved chats stay on your device
    - Scowld does not use Apple's TrueDepth API or ARKit face tracking
    - Scowld does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data

    HOW IT WORKS
    1. Open Settings and choose Google Gemini Live, OpenAI Realtime, or xAI Grok Voice
    2. Add your API key for that provider and pick a voice
    3. Tap the mic, or say her name with hands-free on, and talk naturally
    4. The provider hears you over one live connection and answers in its own voice while the companion lip syncs
    5. Each turn is saved on your device; switch between past chats when you want separate conversation contexts

    Built with SwiftUI, iOS Keychain, Google Gemini Live, OpenAI Realtime, xAI Grok Voice, and a Cloudflare-hosted website.
    Website: https://scowld.xyz
    Blog: https://scowld.xyz/blog
    Instagram: https://www.instagram.com/apoorvcodes/
    Product Hunt: https://www.producthunt.com/products/scowld
    Privacy Policy: https://scowld.xyz/privacy
    Terms of Service: https://scowld.xyz/terms
    Contact: ad13dtu@gmail.com

    Not affiliated with Google, OpenAI, xAI, Apple, or Cloudflare.

## What's New (v2.0.1)

    - Streamlined onboarding with direct Privacy Policy and Terms links
    - Simplified the About screen
    - Character settings now show an editable default name and system prompt with a Clear option
    - Minor fixes and refinements

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

    IMPORTANT - Scowld is a bring-your-own-key (BYOK) app. It has NO bundled or free
    API keys. To talk with the companion, you MUST enter your OWN API key for one of
    its three live voice providers in Settings > Live Voice. This is by design.

    What needs a key:
    - Conversations run live, speech to speech: the selected provider (Google Gemini
      Live, OpenAI Realtime, or xAI Grok Voice) hears the microphone directly and
      answers in its own voice. There is no separate speech-to-text or text-to-speech
      provider, so one key from the selected provider is all that is needed.

    Without a key, the app shows "Add your Gemini API key in Settings to talk to Bella."
    (with the selected provider's name). This is the EXPECTED, in-app guidance shown
    when no key has been entered yet. It is not a crash or malfunction.

    Step-by-step to test a full working session:
    1. Complete onboarding and accept Privacy/Terms.
    2. Open Settings > Live Voice, choose a provider (e.g. Google Gemini Live), pick a
       voice, paste your API key, and tap Save.
    3. On the Chat tab, tap the mic button and speak. The companion answers out loud.
       Speak while she talks to interrupt her, and tap stop to end the conversation.
    4. (Optional) Tap the eye icon to let her see the front camera (Gemini or OpenAI
       only; the camera is off until you turn it on).
    5. (Optional) With the hands-free toggle beside the eye icon turned on, say "Bella"
       or "hey Bella" while the app is idle to start a live conversation.

    Scowld has no subscription, paywall, Billing tab, voice credits, or extra credit
    packs. About > Support Scowld offers optional one-time tips that unlock nothing.
    Provider API keys are entered by the user and stored in the iOS Keychain. Network
    access is required for live conversations. A live conversation ends by itself after
    90 seconds of silence, and when you leave the Chat tab or the app goes to the
    background. The app is designed for iPhone and iPad.
