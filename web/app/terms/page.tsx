import Image from "next/image";
import Link from "next/link";

export const metadata = { title: "Terms of Service — Scowld" };

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
        <p className="legal__date">Last updated: March 16, 2026</p>

        <div className="legal__body">

          <div>
            <h2>1. Acceptance of Terms</h2>
            <p>By downloading, installing, or using Scowld (&quot;the App&quot;), you agree to be bound by these Terms of Service. If you do not agree to these terms, do not use the App. These terms constitute a legal agreement between you and the developer, Apoorv Darshan.</p>
          </div>

          <div>
            <h2>2. Description of Service</h2>
            <p>Scowld is an open-source iOS application that provides an AI companion experience with the following features:</p>
            <ul>
              <li>Conversational AI powered by third-party language model providers (Gemini, OpenAI, Claude, Ollama, OpenRouter, xAI, Together AI).</li>
              <li>A 3D anime avatar with real-time lip sync, idle animations, and emotional expressions.</li>
              <li>Hands-free voice input using on-device Apple Speech recognition.</li>
              <li>Vision capabilities using the device&apos;s front camera.</li>
              <li>Persistent memory that extracts and stores conversation context locally.</li>
              <li>Text-to-speech output via ElevenLabs, OpenAI TTS, or native iOS synthesis.</li>
            </ul>
            <p>The App is provided &quot;as is&quot; and &quot;as available&quot; without warranties of any kind, either express or implied.</p>
          </div>

          <div>
            <h2>3. Open Source License</h2>
            <p>Scowld is released under the <strong className="legal__strong-dim">MIT License</strong>. You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions of the MIT License. The full license text is available at <a href="https://github.com/apoorvdarshan/scowld/blob/main/LICENSE" target="_blank">github.com/apoorvdarshan/scowld/blob/main/LICENSE</a>.</p>
          </div>

          <div>
            <h2>4. Your Responsibilities</h2>
            <ul>
              <li><strong className="legal__strong-dim">API Keys:</strong> You are solely responsible for obtaining, managing, and securing your own API keys for third-party AI providers. Any costs, charges, or fees incurred through API usage are entirely your responsibility.</li>
              <li><strong className="legal__strong-dim">Third-Party Terms:</strong> You must comply with the terms of service and acceptable use policies of any AI provider you configure within the App (Google, OpenAI, Anthropic, ElevenLabs, etc.).</li>
              <li><strong className="legal__strong-dim">Lawful Use:</strong> You agree not to use the App for any illegal, harmful, abusive, harassing, threatening, or otherwise objectionable purposes.</li>
              <li><strong className="legal__strong-dim">Content:</strong> You are responsible for all content you generate, transmit, or receive through the App. The developer has no visibility into or control over your conversations.</li>
              <li><strong className="legal__strong-dim">Camera & Microphone:</strong> When you enable camera or microphone features, you consent to the App accessing these device capabilities for the purposes described in the Privacy Policy.</li>
            </ul>
          </div>

          <div>
            <h2>5. Limitations & Disclaimers</h2>
            <ul>
              <li><strong className="legal__strong-dim">AI Accuracy:</strong> AI-generated responses may be inaccurate, incomplete, biased, or inappropriate. Do not rely on AI responses for medical, legal, financial, or safety-critical advice.</li>
              <li><strong className="legal__strong-dim">No Guarantee of Availability:</strong> Third-party AI providers may change their APIs, pricing, or terms at any time. The App may stop functioning with a particular provider without notice.</li>
              <li><strong className="legal__strong-dim">No Warranty:</strong> The App is provided without warranty of any kind. The developer does not guarantee that the App will be error-free, secure, or uninterrupted.</li>
              <li><strong className="legal__strong-dim">API Costs:</strong> The developer is not responsible for any costs you incur from third-party API usage. Monitor your own usage and set spending limits with your provider.</li>
              <li><strong className="legal__strong-dim">Data Loss:</strong> While the App stores data locally on your device, the developer is not responsible for any loss of chat history, memories, or settings due to device failure, iOS updates, or app deletion.</li>
              <li><strong className="legal__strong-dim">Internet Requirement:</strong> AI features require an active internet connection (except on-device speech recognition and native iOS TTS).</li>
            </ul>
          </div>

          <div>
            <h2>6. Limitation of Liability</h2>
            <p>To the maximum extent permitted by applicable law, the developer shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of profits, data, or use, arising out of or in connection with your use of the App, whether based on warranty, contract, tort, or any other legal theory.</p>
          </div>

          <div>
            <h2>7. Third-Party Services</h2>
            <p>The App integrates with third-party services that are not owned or controlled by the developer. The developer assumes no responsibility for the content, privacy policies, or practices of any third-party services. Your use of these services is governed by their respective terms.</p>
          </div>

          <div>
            <h2>8. Intellectual Property</h2>
            <p>The Scowld name, logo, and branding are the intellectual property of Apoorv Darshan. The source code is licensed under MIT. The 3D avatar system uses <a href="https://github.com/semperai/amica" target="_blank">Amica</a> by Semperai (MIT License).</p>
          </div>

          <div>
            <h2>9. Modifications to Terms</h2>
            <p>The developer reserves the right to modify these terms at any time. Updated terms will be posted on this page with a revised date. Your continued use of the App after changes are posted constitutes acceptance of the updated terms. Since the App has no server component, there is no mechanism to push notifications about term changes.</p>
          </div>

          <div>
            <h2>10. Termination</h2>
            <p>You may stop using the App at any time by deleting it from your device. There is no account to close. All locally stored data will be removed when the app is deleted.</p>
          </div>

          <div>
            <h2>11. Governing Law</h2>
            <p>These terms shall be governed by and construed in accordance with applicable laws, without regard to conflict of law principles.</p>
          </div>

          <div>
            <h2>12. Contact</h2>
            <p>For questions about these terms, contact:<br />
            <strong className="legal__strong-dim">Apoorv Darshan</strong> — <a href="mailto:ad13dtu@gmail.com">ad13dtu@gmail.com</a></p>
          </div>

        </div>
      </div>
    </div>
  );
}
