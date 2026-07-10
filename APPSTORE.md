# App Store Listing

App Store Connect submission details for Scowld v2.0.1. Each field is in a code block for easy copy-paste.

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

    Scowld is an AI voice companion built for natural, expressive conversations with an animated character. Talk by voice or text, get spoken replies, save conversations, and personalize the companion experience from a polished iOS interface.

    WHAT YOU GET
    - Animated AI companion with voice and text conversation
    - Optional hands-free wake mode using Bella or your custom companion name
    - Bring-your-own-key AI provider settings
    - Gemini, OpenAI, Claude, Ollama, Groq, OpenRouter, xAI, Together AI, Hugging Face, Venice AI, and Moonshot AI support
    - Native iOS speech recognition plus optional cloud STT providers
    - Deepgram, OpenAI Whisper, Groq Whisper, AssemblyAI, and Google Cloud STT options
    - ElevenLabs text-to-speech with your own API key
    - Celine, Claire, bundled voice presets, and custom ElevenLabs voice ID support
    - Saved past chats that can be reused as conversation context
    - Custom character name and system prompt controls
    - Optional AI response captions
    - Camera vision support when you choose to send visual context
    - Multilingual speech settings with iPhone language inheritance
    - App Store update checks, rating, sharing, contact, and social links in About

    PRIVACY AND SECURITY
    - No user account is required
    - Provider API keys are entered by you and stored in iOS Keychain
    - Provider API keys are not bundled in the app and are not stored in plain app preferences
    - No subscriptions, paywall, Billing tab, StoreKit purchases, voice credits, or extra credit packs
    - Hands-free wake detection is processed on device while enabled and is not sent to external providers before command recording starts
    - Microphone audio is transcribed only when voice input is used
    - Camera frames are used only when you enable camera and send visual context
    - Scowld does not use Apple's TrueDepth API or ARKit face tracking
    - Scowld does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data

    HOW IT WORKS
    1. Open Settings and add your provider API keys
    2. Choose AI, speech-to-text, and ElevenLabs text-to-speech options
    3. Talk with the animated companion hands-free, by voice, or by typing a message
    4. Scowld transcribes speech, sends the message to your selected AI provider, and speaks the response with ElevenLabs
    5. Save and switch between past chats when you want separate conversation contexts

    Built with SwiftUI, iOS Keychain, Gemini, OpenAI, Claude, Ollama, OpenAI-compatible providers, cloud STT providers, ElevenLabs, and a Cloudflare-hosted website.
    Website: https://scowld.xyz
    Blog: https://scowld.xyz/blog
    Instagram: https://www.instagram.com/scowld_/
    Product Hunt: https://www.producthunt.com/products/scowld
    Privacy Policy: https://scowld.xyz/privacy
    Terms of Service: https://scowld.xyz/terms
    Contact: ad13dtu@gmail.com

    Not affiliated with Google, OpenAI, Anthropic, Deepgram, ElevenLabs, Apple, Cloudflare, or other supported providers.

## What's New (v2.0.1)

    - Streamlined onboarding with direct Privacy Policy and Terms links
    - Simplified the About screen
    - Character settings now show an editable default name and system prompt with a Clear option
    - Minor fixes and refinements

## Keywords (100 chars max)

    ai companion,voice chat,avatar,tts,stt,byok,gemini,openai,elevenlabs,assistant

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
    API keys. To use it, you MUST enter your OWN API keys in Settings. This is by design,
    the same way the app requires an AI provider key to chat.

    What needs a key:
    - AI chat: requires an AI provider key (e.g. Gemini or OpenAI). Without it, chat cannot
      generate a reply.
    - Spoken voice replies: require an ElevenLabs or OpenAI text-to-speech key in
      Settings > Text-to-Speech.

    The message "ElevenLabs API key is missing. Add it in Settings > Text-to-Speech" is the
    EXPECTED, in-app guidance shown when no TTS key has been entered yet. It is not a crash
    or malfunction - it is telling you to add your own key, exactly like the AI provider key.
    Once a valid ElevenLabs (or OpenAI) key is added, the companion speaks normally.

    Step-by-step to test a full working session:
    1. Complete onboarding and accept Privacy/Terms.
    2. Open Settings > BYOK AI, choose a provider (e.g. Gemini), paste your API key, Save.
    3. Type a message in Chat - you will get a text reply from the AI.
    4. To hear spoken replies, open Settings > Text-to-Speech, paste an ElevenLabs API key,
       Save, then send another message.
    5. (Optional) Use the hands-free toggle beside the eye icon, then say "Bella" or
       "hey Bella" while the app is idle.

    Scowld 2.0 has no subscription, paywall, Billing tab, StoreKit purchase flow, voice
    credits, or extra credit packs. Provider API keys are entered by the user and stored in
    the iOS Keychain. Network access is required for cloud AI, cloud STT, and cloud TTS
    providers. The app is designed for iPhone and iPad.
