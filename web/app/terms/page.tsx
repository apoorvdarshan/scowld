import Image from "next/image";
import Link from "next/link";

export const metadata = { title: "Terms of Service - Scowld" };

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
        <p className="legal__date">Last updated: May 14, 2026</p>

        <div className="legal__body">
          <div>
            <h2>1. Acceptance of Terms</h2>
            <p>By downloading, installing, purchasing, subscribing to, or using Scowld (&quot;the App&quot;), you agree to these Terms of Service. If you do not agree, do not use the App.</p>
          </div>

          <div>
            <h2>2. Description of Service</h2>
            <p>Scowld is a paid iOS AI companion app with the following features:</p>
            <ul>
              <li>Conversational AI powered by Google Gemini through Scowld&apos;s hosted backend.</li>
              <li>An animated VRM companion with lip sync, idle animations, and expression support.</li>
              <li>Voice input using Deepgram speech-to-text through Scowld&apos;s hosted backend.</li>
              <li>Text-to-speech output using ElevenLabs through Scowld&apos;s hosted backend.</li>
              <li>Optional camera/vision context.</li>
              <li>Saved past chats and selectable conversation context stored locally on device.</li>
              <li>Subscriptions and extra credit packs handled by Apple in-app purchase.</li>
            </ul>
            <p>The App is provided &quot;as is&quot; and &quot;as available&quot; without warranties of any kind.</p>
          </div>

          <div>
            <h2>3. Purchases, Subscriptions, and Credits</h2>
            <p>Scowld uses Apple in-app purchase for subscriptions and extra voice credit packs. Payments, renewals, cancellations, refunds, and subscription management are handled by Apple under Apple&apos;s App Store terms.</p>
            <ul>
              <li>1 voice credit means 1 full voice turn.</li>
              <li>Subscription credits refill weekly according to the selected plan.</li>
              <li>Extra credits are used after subscription credits.</li>
              <li>Credits and plans may be adjusted for abuse prevention, provider cost changes, or operational reasons.</li>
              <li>Extra credits do not bypass safety limits such as one active reply at a time, audio length limits, TTS length limits, or reply-rate limits.</li>
            </ul>
          </div>

          <div>
            <h2>4. Your Responsibilities</h2>
            <ul>
              <li><strong className="legal__strong-dim">Lawful use:</strong> You agree not to use Scowld for illegal, harmful, abusive, harassing, threatening, exploitative, or otherwise objectionable purposes.</li>
              <li><strong className="legal__strong-dim">Content:</strong> You are responsible for content you submit and for how you use generated responses.</li>
              <li><strong className="legal__strong-dim">AI limitations:</strong> Do not rely on AI responses for medical, legal, financial, safety-critical, or emergency advice.</li>
              <li><strong className="legal__strong-dim">Camera and microphone:</strong> When you enable these permissions, you consent to their use for the purposes described in the Privacy Policy.</li>
              <li><strong className="legal__strong-dim">Third-party terms:</strong> You must comply with applicable terms and acceptable use policies of providers used by Scowld, including Gemini, Deepgram, ElevenLabs, Apple, and Vercel.</li>
            </ul>
          </div>

          <div>
            <h2>5. Service Limits and Availability</h2>
            <ul>
              <li>AI, speech-to-text, and text-to-speech require an active internet connection.</li>
              <li>Third-party providers may change, fail, rate limit, or become unavailable.</li>
              <li>Scowld may enforce usage limits to control cost, prevent abuse, or protect service reliability.</li>
              <li>Features, providers, prices, and credit amounts may change over time.</li>
            </ul>
          </div>

          <div>
            <h2>6. AI Output Disclaimer</h2>
            <p>AI-generated responses may be inaccurate, incomplete, biased, offensive, or inappropriate. Scowld is an entertainment and companion experience, not a professional advisor. You are responsible for evaluating any output before relying on it.</p>
          </div>

          <div>
            <h2>7. Third-Party Services</h2>
            <p>The App integrates with third-party services not owned or controlled by the developer, including Google Gemini, Deepgram, ElevenLabs, Apple services, and Vercel hosting. The developer is not responsible for third-party service content, policies, availability, or data practices.</p>
          </div>

          <div>
            <h2>8. Intellectual Property</h2>
            <p>The Scowld name, logo, branding, app design, website, and private app code are owned by Apoorv Darshan unless otherwise stated. The bundled character/avatar frontend is based on Amica / Arbius AI components credited in the app.</p>
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
