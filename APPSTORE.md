# App Store Listing

App Store Connect submission details for Scowld v1.1. Each field is in a code block for easy copy-paste.

## App Name (30 chars max)

    Scowld - AI Voice Companion

## Subtitle (30 chars max)

    AI Voice Chat With Memory

## Promotional Text (170 chars max)

    Talk hands-free, by voice, or by text with an animated AI companion. Gemini, Deepgram, and ElevenLabs run through Scowld's hosted backend.

## Keywords (100 chars max)

    ai companion,voice chat,avatar,tts,stt,gemini,deepgram,elevenlabs,chatbot,assistant

## Category

    Primary Category: Lifestyle
    Secondary Category: Entertainment

## Description

    Scowld is an AI voice companion built for natural, expressive conversations with an animated character. Talk by voice or text, get spoken replies, save conversations, and personalize the companion experience from a polished iOS interface.

    WHAT YOU GET
    - Animated AI companion with voice and text conversation
    - Optional hands-free wake mode using Bella or your custom companion name
    - Hosted Gemini AI responses through Scowld's backend
    - Deepgram speech-to-text for voice input
    - ElevenLabs text-to-speech for expressive spoken replies
    - Selectable ElevenLabs voices with local voice sample previews
    - Optional custom ElevenLabs voice ID support
    - Saved past chats that can be reused as conversation context
    - Custom character name and system prompt controls
    - Optional AI response captions
    - Camera vision support when you choose to send visual context
    - Multilingual speech settings with iPhone language inheritance
    - App Store update checks, rating, sharing, contact, and social links in About

    PRIVACY AND SECURITY
    - No user account is required
    - No provider API keys are entered in the app
    - Provider API keys stay on Scowld's hosted backend, not inside the App Store binary
    - Hands-free wake detection is processed on device while enabled and is not sent to Scowld's backend before command recording starts
    - Microphone audio is sent for speech recognition only when voice input is used
    - Camera frames are used only when you enable camera and send visual context
    - Provider keys can be rotated on the hosted backend without an App Store update
    - Scowld does not use Apple's TrueDepth API or ARKit face tracking
    - Scowld does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data

    HOW IT WORKS
    1. Choose a subscription plan to unlock Scowld
    2. Talk with the animated companion hands-free, by voice, or by typing a message
    3. Scowld transcribes speech, sends the message to Gemini, and speaks the response with ElevenLabs
    4. Save and switch between past chats when you want separate conversation contexts
    5. Buy extra voice credits if you need more voice turns

    VOICE CREDITS
    - 1 credit = 1 full voice turn
    - Subscription credits refill weekly
    - Extra credits are used after subscription credits
    - Safety limits still apply, including one active reply at a time, capped audio input length, and capped TTS reply length

    PRICING
    - Weekly: $9.99/week, 40 credits/week
    - Monthly: $34.99/month, 180 credits included, refilled as 45 credits/week
    - Yearly: $299.99/year, 2,340 credits included, refilled as 45 credits/week
    - Extra credits: 10, 50, 100, 200, and 500 credit packs
    - Purchases are handled by Apple and can be managed from Apple ID settings

    Built with SwiftUI, StoreKit, RevenueCat, Gemini, Deepgram, ElevenLabs, and a hosted Vercel backend.
    Website: https://scowld.xyz
    LinkedIn: https://www.linkedin.com/company/scowld
    Instagram: https://www.instagram.com/scowld_/
    Product Hunt: https://www.producthunt.com/products/scowld
    Ko-fi: https://ko-fi.com/apoorvdarshan
    Privacy Policy: https://scowld.xyz/privacy
    Terms of Service: https://scowld.xyz/terms
    Contact: ad13dtu@gmail.com

    Not affiliated with Google, Deepgram, ElevenLabs, Apple, or Vercel.

## What's New (v1.1)

    - Added hands-free wake mode with a composer toggle
    - Added a Home tips button that explains hands-free wake and composer controls
    - Wake recording can start from Bella, a saved custom companion name, or "hey" plus that name
    - Default character names now resolve to Bella unless a custom name is saved
    - Updated character picker labels to Character 1, Character 2, and Character 3
    - Updated bundled Privacy Policy and Terms for hands-free wake behavior

## Privacy URL

    https://scowld.xyz/privacy

## Terms URL

    https://scowld.xyz/terms

## Support URL

    https://scowld.xyz

## Marketing URL

    https://scowld.xyz

## Reviewer Notes

    Scowld requires an active subscription. Please use Apple sandbox purchase flow on the startup paywall, or Restore Purchases if a sandbox entitlement already exists.

    Quick test path:
    1. Subscribe or restore from the paywall.
    2. Send a typed message.
    3. Grant microphone permission and test voice input.
    4. Use the hands-free toggle beside the eye icon, then say "Bella" or "hey Bella" while the app is idle.
    5. Tap the top-right info button on Home to view control tips.

    Network access is required. AI chat, speech-to-text, and text-to-speech are routed through Scowld's hosted backend so provider API keys are not included in the app binary. The app is designed for iPhone and iPad.

## App Review Response Notes

    Hello App Review,

    This resubmission addresses the two issues from Submission ID a6fcf69a-48c6-4caa-86c2-5fe0513fab37.

    Guideline 1.1:
    We updated the app metadata to remove keyword/marketing references that could imply objectionable content. Current keywords are: ai companion, voice chat, avatar, tts, stt, gemini, deepgram, elevenlabs, chatbot, assistant.

    Guideline 2.1(a):
    We fixed the launch crash in build 1.1 (9). The crash logs pointed to hands-free wake audio input setup, so the app now waits for microphone/speech permissions, validates the input audio format, and removes stale audio taps before restarting recognition.

    Please review version 1.1 build 9.
