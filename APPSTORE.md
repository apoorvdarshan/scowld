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

    Scowld requires an active subscription to enter the app. Extra credits extend voice usage after subscription credits are used. Purchases are processed through Apple in-app purchase and can be tested with Apple sandbox purchase flow.

    To test:
    1. Launch the app.
    2. Choose a subscription plan on the startup paywall using Apple sandbox purchase flow.
    3. Open Chat and send a typed message.
    4. Grant microphone permission and test voice input.
    5. Use the hands-free toggle beside the eye icon and say "Bella" or "hey Bella" while the app is idle to start recording.
    6. Optionally grant camera permission and ask a visual question with camera enabled.
    7. Open Chats to confirm conversations are saved and can be selected as context.
    8. Open Settings to test language, voice selection, local voice previews, captions, avatar, custom name, and system prompt.
    9. Open Billing to view active subscription, restore purchases, credit balance, manage subscription, and extra credit packs.
    10. Open About to test update check, rating prompt, sharing, contact, social, support, privacy, and terms links.

    Network access is required. The app routes AI chat, speech-to-text, and text-to-speech through Scowld's hosted backend so provider API keys are not shipped in the app binary.

    The app uses the microphone for voice input and optional hands-free wake detection. Hands-free wake detection runs on device while enabled and does not send audio to Scowld's hosted backend before command recording starts. The app uses the camera only when the user enables vision/camera context.
    The startup onboarding includes bundled offline Privacy Policy and Terms of Service text with a required acceptance checkbox before the paywall.
    The paywall includes a distinct Restore button in the top-right toolbar, and Billing includes Restore Purchases for users returning later.

    The app is designed for iPhone and iPad.

## App Review Response Notes

    Restore Purchases:
    Build 1.1 (9) keeps the distinct Restore button in the top-right toolbar of the startup paywall and a Restore Purchases row in the Billing tab. Tapping either initiates RevenueCat's restore purchases flow.

    Hands-free wake mode:
    Build 1.1 (9) adds an optional hands-free wake toggle in the composer. While enabled and the app is open and idle, Scowld listens on device for Bella or the saved custom companion name. Once detected, the app starts normal voice recording and sends only the command recording for speech-to-text.

    Crash fix:
    Build 1.1 (9) fixes a launch/restart crash in hands-free wake listening by waiting for microphone and speech permissions before starting the listener, validating the input audio format, and removing stale audio input taps before restarting recognition.

    Home tips:
    Build 1.1 (9) adds an info button on the Home screen. It opens a compact guide for hands-free wake phrases and the eye, hands-free, voice, send, and trash controls.

    Age Rating:
    Set App Store Connect age rating to 18+ using "Override to Higher Age Rating" because the AI companion can generate general AI content.

    TrueDepth / Face Data:
    Scowld does not use Apple's TrueDepth API or ARKit face tracking. The previous unused ARKit face-tracking code path was removed from the app target.

    What information is collected using TrueDepth API?
    None. Scowld does not collect TrueDepth API information.

    For what purpose is this information collected?
    No TrueDepth information is collected, so there is no planned use.

    Will the data be shared with any third parties? Where is it stored?
    No TrueDepth or face data is shared with third parties or stored anywhere by Scowld, because Scowld does not collect it.

    Privacy policy location:
    Privacy Policy section 5, "Face Data and TrueDepth API," explains collection, use, disclosure, sharing, and retention of face data.

    Privacy policy quote:
    "Scowld does not use Apple's TrueDepth API. The app does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or any other face data."
