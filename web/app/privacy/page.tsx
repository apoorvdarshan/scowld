import Image from "next/image";
import Link from "next/link";

export const metadata = { title: "Privacy Policy — Scowld" };

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
        <p className="legal__date">Last updated: May 13, 2026</p>

        <div className="legal__body">

          <div>
            <h2>1. Overview</h2>
            <p>Scowld is an AI companion application for iOS. It uses a hosted backend only to route AI, speech-to-text, and text-to-speech requests to configured providers without putting provider API keys inside the iOS app.</p>
            <p>The complete source code is publicly available at <a href="https://github.com/apoorvdarshan/scowld" target="_blank">github.com/apoorvdarshan/scowld</a> under the MIT License. You can audit exactly what the app does at any time.</p>
          </div>

          <div>
            <h2>2. Data Collection</h2>
            <p>Scowld does not require an account and does not use advertising or analytics SDKs. Specifically:</p>
            <ul>
              <li>We do not ask for your name, email, location, or account credentials.</li>
              <li>We do not use analytics SDKs, crash reporting services, or advertising frameworks.</li>
              <li>We do not track your usage patterns, session duration, or feature engagement.</li>
              <li>AI requests, speech audio, and generated speech text pass through the hosted backend only to provide the app features.</li>
              <li>The hosted backend is not designed to store conversation content, audio, images, or API keys in a database.</li>
            </ul>
          </div>

          <div>
            <h2>3. Camera Access</h2>
            <p>Scowld requests access to your device&apos;s front-facing camera for the Vision feature. When enabled:</p>
            <ul>
              <li>Camera frames are captured on-device and sent through the hosted backend to Google Gemini <strong>only</strong> when you explicitly send a message.</li>
              <li>No images or video are stored on your device or transmitted anywhere else.</li>
              <li>No images are saved to your photo library.</li>
              <li>Camera data is never processed, cached, or buffered beyond the immediate frame capture.</li>
              <li>The camera can be disabled at any time using the eye icon toggle in the app.</li>
              <li>When the camera is disabled, no frames are captured and no camera data is accessed.</li>
            </ul>
          </div>

          <div>
            <h2>4. Microphone Access</h2>
            <p>Scowld requests microphone access for the hands-free voice chat feature. When enabled:</p>
            <ul>
              <li>Speech audio is sent through the hosted backend to Deepgram for speech-to-text conversion when voice mode detects speech.</li>
              <li>Audio is not intentionally stored by the app or hosted backend after transcription completes.</li>
              <li>The recognized text is sent to Gemini when a message is sent.</li>
              <li>The microphone automatically pauses during AI text-to-speech playback to prevent feedback loops.</li>
              <li>Voice mode can be toggled on/off at any time using the waveform icon.</li>
            </ul>
          </div>

          <div>
            <h2>5. Third-Party AI Providers</h2>
            <p>Scowld uses managed third-party providers. Your text messages, optional camera frames, speech audio, and generated speech text may be sent to these services through the hosted backend. Each provider has its own privacy policy:</p>
            <ul>
              <li><strong className="legal__strong-dim">Google Gemini</strong> — <a href="https://ai.google.dev/terms" target="_blank">ai.google.dev/terms</a></li>
              <li><strong className="legal__strong-dim">ElevenLabs</strong> (TTS) — <a href="https://elevenlabs.io/privacy" target="_blank">elevenlabs.io/privacy</a></li>
              <li><strong className="legal__strong-dim">Deepgram</strong> (STT) — <a href="https://deepgram.com/privacy" target="_blank">deepgram.com/privacy</a></li>
            </ul>
            <p>We do not control these third-party services or their data handling practices.</p>
          </div>

          <div>
            <h2>6. API Keys</h2>
            <p>Scowld does not ask users to enter provider API keys in the iOS app. Provider API keys are stored as hosted backend environment variables and are not included in the App Store binary. API keys are:</p>
            <ul>
              <li>Not shown in the iOS app UI.</li>
              <li>Not committed to the public source repository.</li>
              <li>Rotatable from the hosted deployment without an App Store update.</li>
            </ul>
          </div>

          <div>
            <h2>7. Local Data Storage</h2>
            <p>The following data is stored locally on your device using Apple&apos;s CoreData framework:</p>
            <ul>
              <li><strong className="legal__strong-dim">Chat history</strong> — your messages and AI responses.</li>
              <li><strong className="legal__strong-dim">Memory logs</strong> — AI-extracted summaries of key conversation details.</li>
              <li><strong className="legal__strong-dim">Memory slots</strong> — organizational containers for different conversation contexts.</li>
              <li><strong className="legal__strong-dim">Settings</strong> — your preferences such as avatar, voice ID, and character prompt.</li>
            </ul>
            <p>All of this data lives exclusively on your iPhone. It is not synced to iCloud, not backed up to any server, and not accessible to anyone but you. You can clear all data at any time from Settings &rarr; Clear All Memories.</p>
          </div>

          <div>
            <h2>8. Text-to-Speech</h2>
            <p>The AI&apos;s response text is sent through the hosted backend to ElevenLabs to generate audio. Voice sample playback in Settings uses local iOS speech and does not call ElevenLabs.</p>
          </div>

          <div>
            <h2>9. Children&apos;s Privacy</h2>
            <p>Scowld is not directed at children under 13. We do not knowingly collect any data from anyone, including children.</p>
          </div>

          <div>
            <h2>10. Open Source Transparency</h2>
            <p>Scowld is fully open source under the MIT License. Every line of code is publicly auditable. There are no hidden data collection mechanisms, no obfuscated network calls, and no proprietary SDKs. If you have concerns about what the app does, you can read the source code yourself at <a href="https://github.com/apoorvdarshan/scowld" target="_blank">github.com/apoorvdarshan/scowld</a>.</p>
          </div>

          <div>
            <h2>11. Changes to This Policy</h2>
            <p>We may update this privacy policy from time to time. Changes will be reflected on this page with an updated date.</p>
          </div>

          <div>
            <h2>12. Contact</h2>
            <p>For any privacy concerns or questions, contact:<br />
            <strong className="legal__strong-dim">Apoorv Darshan</strong> — <a href="mailto:ad13dtu@gmail.com">ad13dtu@gmail.com</a></p>
          </div>

        </div>
      </div>
    </div>
  );
}
