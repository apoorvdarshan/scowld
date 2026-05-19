import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy - Scowld",
  description: "Privacy policy for Scowld, an iOS AI voice companion with hosted AI, speech, voice, optional vision, and local saved chats.",
  alternates: { canonical: "/privacy" },
};

export default function Privacy() {
  return (
    <div className="legal">
      <nav className="legal__nav">
        <Link href="/" className="legal__nav-logo">
          <Image src="/logo.png" alt="Scowld" width={20} height={20} className="legal__nav-logo-img" />
          SCOWLD
        </Link>
      </nav>
      <div className="legal__container">
        <Link href="/" className="legal__back">&larr; Back to home</Link>
        <h1 className="legal__title">Privacy Policy</h1>
        <p className="legal__date">Last updated: May 19, 2026</p>

        <div className="legal__body">
          <div>
            <h2>1. Overview</h2>
            <p>Scowld is an iOS AI companion app. It uses a hosted backend to route chat, speech-to-text, and text-to-speech requests to configured providers without putting provider API keys inside the iOS app.</p>
            <p>This policy explains what information is processed when you use the app, website, and hosted backend.</p>
          </div>

          <div>
            <h2>2. Account and App Analytics</h2>
            <p>The iOS app does not require a Scowld account. The app does not include advertising SDKs or third-party app analytics SDKs.</p>
            <ul>
              <li>We do not ask for your name, email, location, or account password in the iOS app.</li>
              <li>We do not sell personal data.</li>
              <li>We do not use advertising frameworks in the iOS app.</li>
              <li>The marketing website may use Vercel Analytics for aggregate website traffic measurement.</li>
            </ul>
          </div>

          <div>
            <h2>3. AI and Voice Processing</h2>
            <p>To provide the app features, Scowld may process the following through the hosted backend:</p>
            <ul>
              <li>Typed messages and selected conversation context.</li>
              <li>Voice audio sent for speech-to-text.</li>
              <li>Recognized speech text sent to Gemini for a response.</li>
              <li>Assistant response text sent to ElevenLabs for speech generation.</li>
              <li>Optional camera image context when you enable camera/vision and send a message.</li>
            </ul>
            <p>The hosted backend is not designed to store conversation content, speech audio, generated speech, images, or provider API keys in a database.</p>
          </div>

          <div>
            <h2>4. Camera Access</h2>
            <p>Scowld requests camera access for the optional vision feature. When camera context is enabled:</p>
            <ul>
              <li>Frames are captured on device and sent through the hosted backend to Gemini only when visual context is used in a message.</li>
              <li>Images are not saved to your photo library by Scowld.</li>
              <li>Camera access can be disabled from the app or iOS settings.</li>
              <li>When camera is disabled, Scowld does not capture camera frames.</li>
            </ul>
            <p>Scowld does not use Apple&apos;s TrueDepth API or ARKit face tracking. Scowld does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or any other face data.</p>
          </div>

          <div>
            <h2>5. Face Data and TrueDepth API</h2>
            <p>Scowld does not use Apple&apos;s TrueDepth API. The app does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or any other face data.</p>
            <ul>
              <li>No TrueDepth information is collected by Scowld.</li>
              <li>No TrueDepth or face data is used by Scowld for any purpose.</li>
              <li>No TrueDepth or face data is stored locally by Scowld or on Scowld&apos;s hosted backend.</li>
              <li>No TrueDepth or face data is disclosed or shared with Gemini, Deepgram, ElevenLabs, Vercel, Apple, or any other third party by Scowld.</li>
              <li>No TrueDepth or face data is retained because Scowld does not collect it.</li>
            </ul>
          </div>

          <div>
            <h2>6. Microphone Access</h2>
            <p>Scowld requests microphone access for voice input. When you record or send voice input:</p>
            <ul>
              <li>Speech audio is sent through the hosted backend to Deepgram for transcription.</li>
              <li>The recognized text is sent to Gemini as part of the conversation.</li>
              <li>The microphone is not needed for typed messages.</li>
              <li>Microphone permission can be revoked from iOS settings.</li>
            </ul>
          </div>

          <div>
            <h2>7. Third-Party Providers</h2>
            <p>Scowld uses managed third-party providers through the hosted backend. These providers may process data needed to provide app features:</p>
            <ul>
              <li><strong className="legal__strong-dim">Google Gemini</strong> for AI chat and optional image understanding.</li>
              <li><strong className="legal__strong-dim">Deepgram</strong> for speech-to-text.</li>
              <li><strong className="legal__strong-dim">ElevenLabs</strong> for text-to-speech.</li>
              <li><strong className="legal__strong-dim">Apple</strong> for in-app purchases and subscription management.</li>
              <li><strong className="legal__strong-dim">Vercel</strong> for website and hosted backend deployment.</li>
            </ul>
            <p>These third-party services have their own privacy policies and terms.</p>
          </div>

          <div>
            <h2>8. Provider API Keys</h2>
            <p>Scowld does not ask users to enter Gemini, Deepgram, or ElevenLabs API keys. Provider keys are stored as hosted backend environment variables and are not included in the App Store binary.</p>
            <ul>
              <li>Provider keys are not shown in the iOS app UI.</li>
              <li>Provider keys are not committed to the source repository.</li>
              <li>Provider keys can be rotated from the hosted deployment without an App Store update.</li>
            </ul>
          </div>

          <div>
            <h2>9. Local Device Storage</h2>
            <p>Scowld stores app data locally on your device using Apple&apos;s local storage frameworks. This may include:</p>
            <ul>
              <li>Past chat messages and assistant replies.</li>
              <li>The selected active chat.</li>
              <li>Character settings such as avatar, custom name, and system prompt.</li>
              <li>Voice, language, and caption preferences.</li>
              <li>Local purchase/credit state used by the app UI.</li>
            </ul>
            <p>Deleting the app removes local app data from the device, subject to normal iOS behavior and backups.</p>
          </div>

          <div>
            <h2>10. Voice Samples</h2>
            <p>Voice sample playback in Settings uses bundled local preview audio files included with the app. Playing a bundled sample does not call ElevenLabs.</p>
          </div>

          <div>
            <h2>11. Children&apos;s Privacy</h2>
            <p>Scowld is not directed at children under 13. We do not knowingly collect personal information from children under 13.</p>
          </div>

          <div>
            <h2>12. Changes to This Policy</h2>
            <p>We may update this privacy policy from time to time. Changes will be reflected on this page with an updated date.</p>
          </div>

          <div>
            <h2>13. Contact</h2>
            <p>For privacy questions, contact:<br />
            <strong className="legal__strong-dim">Apoorv Darshan</strong> - <a href="mailto:ad13dtu@gmail.com">ad13dtu@gmail.com</a></p>
          </div>
        </div>
      </div>
    </div>
  );
}
