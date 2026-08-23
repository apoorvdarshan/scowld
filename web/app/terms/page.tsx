import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms of Service - Scowld",
  description: "Terms of Service for Scowld, an iOS AI voice companion with BYOK AI, speech, and voice.",
  alternates: { canonical: "/terms" },
};

export default function Terms() {
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
        <h1 className="legal__title">Terms of Service</h1>
        <p className="legal__date">Last updated: July 10, 2026</p>

        <div className="legal__body">
          <div>
            <h2>1. Acceptance of Terms</h2>
            <p>By downloading, installing, or using Scowld (&quot;the App&quot;), you agree to these Terms of Service. If you do not agree, do not use the App.</p>
          </div>

          <div>
            <h2>2. Description of Service</h2>
            <p>Scowld is an iOS AI companion app with the following features:</p>
            <ul>
              <li>Bring-your-own-key conversational AI with multiple provider options.</li>
              <li>An animated VRM companion with lip sync, idle animations, and expression support.</li>
              <li>Optional hands-free wake mode that can start voice recording when the selected companion name is detected.</li>
              <li>Voice input using native iOS speech recognition or configured cloud STT providers.</li>
              <li>Text-to-speech output using your ElevenLabs or OpenAI API key.</li>
              <li>Optional camera/vision context.</li>
              <li>Saved past chats and selectable conversation context stored locally on device.</li>
            </ul>
            <p>The App is provided &quot;as is&quot; and &quot;as available&quot; without warranties of any kind.</p>
          </div>

          <div>
            <h2>3. Bring Your Own Keys</h2>
            <p>Scowld does not include subscriptions, paywalls, voice credits, extra credit packs, or Apple in-app purchases in version 2.0.</p>
            <ul>
              <li>You are responsible for provider accounts, API keys, provider billing, rate limits, and acceptable use policies.</li>
              <li>Provider API keys are stored in the iOS Keychain on your device.</li>
              <li>Third-party providers may charge your provider account based on your usage.</li>
              <li>Scowld is not responsible for third-party provider billing, credits, quotas, or refunds.</li>
            </ul>
          </div>

          <div>
            <h2>4. Your Responsibilities</h2>
            <ul>
              <li><strong className="legal__strong-dim">Lawful use:</strong> You agree not to use Scowld for illegal, harmful, abusive, harassing, threatening, exploitative, or otherwise objectionable purposes.</li>
              <li><strong className="legal__strong-dim">Content:</strong> You are responsible for content you submit and for how you use generated responses.</li>
              <li><strong className="legal__strong-dim">AI limitations:</strong> Do not rely on AI responses for medical, legal, financial, safety-critical, or emergency advice.</li>
              <li><strong className="legal__strong-dim">Camera and microphone:</strong> When you enable these permissions, you consent to their use for the purposes described in the Privacy Policy. If hands-free mode is enabled, the microphone may remain active while the app is open and idle so Scowld can listen on device for Bella or your saved custom companion name. Scowld does not use Apple&apos;s TrueDepth API or collect face data.</li>
              <li><strong className="legal__strong-dim">Third-party terms:</strong> You must comply with applicable terms and acceptable use policies of providers you configure, including AI, speech-to-text, text-to-speech, Apple platform services, and Cloudflare.</li>
            </ul>
          </div>

          <div>
            <h2>5. Service Limits and Availability</h2>
            <ul>
              <li>Cloud AI, cloud speech-to-text, and cloud text-to-speech require an active internet connection and valid provider API keys.</li>
              <li>Hands-free wake detection requires microphone and speech recognition permission, may miss wake phrases, and may occasionally trigger unexpectedly.</li>
              <li>Third-party providers may change, fail, rate limit, or become unavailable.</li>
              <li>Features and provider options may change over time.</li>
            </ul>
          </div>

          <div>
            <h2>6. AI Output Disclaimer</h2>
            <p>AI-generated responses may be inaccurate, incomplete, biased, offensive, or inappropriate. Scowld is an entertainment and companion experience, not a professional advisor. You are responsible for evaluating any output before relying on it.</p>
          </div>

          <div>
            <h2>7. Third-Party Services</h2>
            <p>The App integrates with third-party services not owned or controlled by the developer, including AI providers, speech-to-text providers, ElevenLabs, Apple services, and Cloudflare hosting. The developer is not responsible for third-party service content, policies, pricing, billing, availability, or data practices.</p>
          </div>

          <div>
            <h2>8. Intellectual Property</h2>
            <p>The Scowld name, logo, branding, app design, and website are owned by Apoorv Darshan unless otherwise stated. The Scowld app source code is open source and released under the MIT License at <a href="https://github.com/aopv/scowld">github.com/aopv/scowld</a>. The bundled character/avatar frontend is based on Amica / Arbius AI components credited in the app.</p>
          </div>

          <div>
            <h2>9. Termination</h2>
            <p>You may stop using Scowld at any time by deleting the app. We may restrict or disable access if we believe the service is being abused, used unlawfully, or used in violation of these terms.</p>
          </div>

          <div>
            <h2>10. Limitation of Liability</h2>
            <p>To the maximum extent permitted by law, the developer is not liable for indirect, incidental, special, consequential, or punitive damages, including loss of data, profits, use, or access, arising from your use of Scowld.</p>
          </div>

          <div>
            <h2>11. Changes to Terms</h2>
            <p>We may update these terms from time to time. Updated terms will be posted on this page with a revised date. Continued use of Scowld after changes are posted means you accept the updated terms.</p>
          </div>

          <div>
            <h2>12. Contact</h2>
            <p>For questions about these terms, contact:<br />
            <strong className="legal__strong-dim">Apoorv Darshan</strong> - <a href="mailto:ad13dtu@gmail.com">ad13dtu@gmail.com</a></p>
          </div>
        </div>
      </div>
    </div>
  );
}
