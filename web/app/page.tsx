"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef } from "react";

const links = {
  appStore: "https://apps.apple.com/in/app/scowld-ai-voice-companion/id6760672848",
  productHunt: "https://www.producthunt.com/products/scowld",
  instagram: "https://www.instagram.com/scowld_/",
  github: "https://github.com/apoorvdarshan/scowld",
  koFi: "https://ko-fi.com/apoorvdarshan",
  x: "https://x.com/apoorvdarshan",
  mail: "mailto:ad13dtu@gmail.com",
};

const features = [
  { icon: "fa-microphone-lines", title: "Voice input", desc: "Speak from the iOS composer using native iOS speech or your configured cloud STT provider." },
  { icon: "fa-bell", title: "Hands-free wake", desc: "When enabled, Scowld can listen locally for Bella or your custom name to start voice recording." },
  { icon: "fa-circle-info", title: "Home tips", desc: "A compact in-app guide explains wake phrases and the eye, hands-free, voice, send, and cancel controls." },
  { icon: "fa-wand-magic-sparkles", title: "Animated companion", desc: "A VRM character with lip sync, idle animation, and expressive response playback." },
  { icon: "fa-eye", title: "Optional vision", desc: "Enable camera context when you want the AI to respond to what you are seeing." },
  { icon: "fa-comments", title: "Past chats", desc: "Save conversations locally, switch between chats, and reuse one as context for future replies." },
  { icon: "fa-key", title: "Bring your own keys", desc: "Use your own AI, speech-to-text, and ElevenLabs keys. Keys stay in the iOS Keychain." },
  { icon: "fa-volume-high", title: "ElevenLabs voice", desc: "Celine, Claire, bundled voice presets, custom voice ID support, and local voice previews." },
];

const tags = [
  "BYOK", "OPEN SOURCE", "NO PAYWALL", "HANDS-FREE WAKE", "GEMINI", "OPENAI", "CLAUDE", "ELEVENLABS", "DEEPGRAM STT",
  "ANIMATED AVATAR", "VISION", "PAST CHATS", "IOS", "PRIVACY FIRST",
];

const faqs = [
  {
    q: "What is Scowld?",
    a: "Scowld is a free, open-source iOS AI voice companion with an animated on-screen avatar. You talk by voice or text, get spoken replies through ElevenLabs or OpenAI voices, and can optionally let it use the camera so it responds to what you show it. You bring your own AI, speech-to-text, and text-to-speech API keys.",
  },
  {
    q: "Is Scowld free?",
    a: "Yes. Scowld is free and open source (MIT). There are no subscriptions, paywalls, voice credits, or in-app purchases. You bring your own provider API keys and pay your chosen providers directly for usage.",
  },
  {
    q: "Can Scowld see through the camera?",
    a: "Yes, optionally. When you enable the camera, Scowld can send a frame to your chosen AI provider so the companion responds to what you show it — like holding up an object. Camera vision is off by default and only used when you send a message with it enabled.",
  },
  {
    q: "Does Scowld work on iPhone and iPad?",
    a: "Yes. Scowld runs on iPhone and iPad with iOS 17 or later. Settings, provider keys, and saved chats stay on the device.",
  },
  {
    q: "How is Scowld different from other AI companion apps?",
    a: "Scowld is bring-your-own-key and open source, so there is no paywall and no server that stores your keys or conversations — requests go straight from your device to the providers you pick. It also pairs an animated avatar with optional camera vision, hands-free wake, and swappable AI, speech-to-text, and text-to-speech providers.",
  },
  {
    q: "What does bring-your-own-key (BYOK) mean?",
    a: "You use your own API keys for the AI, speech-to-text, and text-to-speech providers you choose. Keys are stored only in the iOS Keychain on your device, so Scowld never runs a server that sees or stores them.",
  },
  {
    q: "Which AI providers does Scowld support?",
    a: "Gemini, OpenAI, Claude, Ollama, Groq, OpenRouter, xAI, Together AI, Hugging Face, Venice AI, and Moonshot AI. You can switch providers and models any time in Settings.",
  },
  {
    q: "What speech-to-text and text-to-speech options are available?",
    a: "Voice input works with native iOS speech recognition or cloud providers like OpenAI Whisper, Groq Whisper, Deepgram, AssemblyAI, and Google Cloud Speech-to-Text. Spoken replies use ElevenLabs or OpenAI voices.",
  },
  {
    q: "Are my API keys stored securely?",
    a: "Yes. Provider keys are stored in the iOS Keychain on your device, are not bundled in the app binary, and are never sent to Scowld servers. Requests go directly from your device to the provider you configured.",
  },
  {
    q: "Is Scowld open source?",
    a: "Yes. Scowld is released under the MIT License and the source is available on GitHub at github.com/apoorvdarshan/scowld.",
  },
  {
    q: "Does Scowld need an account or an internet connection?",
    a: "No account is required. Cloud AI, speech-to-text, and text-to-speech need an internet connection and valid provider keys, while native iOS speech recognition works on device.",
  },
  {
    q: "What is hands-free wake mode?",
    a: "An optional mode where Scowld listens on device for \"Bella\" or your custom companion name to start voice recording. Wake detection is processed on device and is not sent to providers before recording starts.",
  },
];

const socialLinks = [
  { href: links.github, label: "GitHub", icon: "fa-brands fa-github" },
  { href: links.instagram, label: "Instagram", icon: "fa-brands fa-instagram" },
  { href: links.koFi, label: "Ko-fi", icon: "fa-solid fa-mug-saucer" },
  { href: links.x, label: "X", icon: "fa-brands fa-x-twitter" },
  { href: links.mail, label: "Email", icon: "fa-solid fa-envelope" },
];

export default function Home() {
  const mainRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const els = document.querySelectorAll(".sr");
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.05, rootMargin: "0px 0px 0px 0px" }
    );
    requestAnimationFrame(() => {
      els.forEach((el) => observer.observe(el));
    });

    const words = document.querySelectorAll(".word-reveal");
    const wordObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
            wordObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.5 }
    );
    words.forEach((w, i) => {
      const span = w.querySelector("span");
      if (span) (span as HTMLElement).style.transitionDelay = `${0.15 + i * 0.1}s`;
      wordObserver.observe(w);
    });

    return () => {
      observer.disconnect();
      wordObserver.disconnect();
    };
  }, []);

  return (
    <div ref={mainRef} className="page">
      <header className="nav">
        <Link href="/" className="nav__logo">
          <Image src="/logo.png" alt="" width={30} height={30} className="nav__logo-img" />
          Scowld
        </Link>
        <nav className="nav__links">
          <Link href="/blog" className="nav__link">Blog</Link>
          <Link href="/privacy" className="nav__link">Privacy</Link>
          <Link href="/terms" className="nav__link">Terms</Link>
          <a href={links.instagram} target="_blank" rel="noopener noreferrer" className="nav__link">Instagram</a>
          <a href={links.github} target="_blank" rel="noopener noreferrer" className="nav__link">GitHub</a>
          <a href={links.x} target="_blank" rel="noopener noreferrer" className="nav__link">
            X <span className="nav__link-handle">@apoorvdarshan</span>
          </a>
        </nav>
      </header>

      <section className="hero">
        <div className="hero__grid">
          <div className="hero__content">
            <div className="sr sr-delay-1 hero__badge">
              <span className="hero__badge-dot">
                <span className="hero__badge-dot-ping" />
                <span className="hero__badge-dot-solid" />
              </span>
                <span className="hero__badge-text">Scowld 2.0 for iOS</span>
            </div>

            <h1 className="hero__heading">
              <span className="word-reveal"><span>Talk to her.</span></span>
              <br />
              <span className="word-reveal"><span className="hero__heading-dim">She remembers.</span></span>
            </h1>

            <p className="sr sr-delay-2 hero__desc">
              An AI voice companion with an animated character, hands-free wake mode, bring-your-own-key AI providers, ElevenLabs speech, optional vision, and saved past chats.
            </p>

            <div className="sr sr-delay-3 hero__buttons">
              <a
                href={links.appStore}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-primary btn-appstore"
              >
                <i className="fa-brands fa-apple" aria-hidden="true" />
                Download on App Store
              </a>
              <a href={links.productHunt} target="_blank" rel="noopener noreferrer" className="btn-secondary">
                Vote on Product Hunt
              </a>
              <a href={links.github} target="_blank" rel="noopener noreferrer" className="btn-secondary">
                <i className="fa-brands fa-github" aria-hidden="true" /> Star on GitHub
              </a>
              <a href={links.koFi} target="_blank" rel="noopener noreferrer" className="btn-secondary">
                Support on Ko-fi <span className="btn-secondary__arrow">&rarr;</span>
              </a>
            </div>
          </div>

          <div className="hero__phone-wrap">
            <div className="sr sr-delay-4 phone-float">
              <Image
                src="/mockup.png"
                alt="Scowld AI voice companion app on iPhone showing the animated avatar and voice chat composer"
                width={1080}
                height={1920}
                priority
                className="hero__phone"
              />
            </div>
          </div>
        </div>
      </section>

      <div className="marquee">
        <div className="marquee__track">
          {[0, 1].map((k) => (
            <div key={k} className="marquee__group">
              {tags.map((tag) => (
                <span key={tag + k} className="marquee__item">
                  <span className="marquee__dot" />
                  {tag}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>

      <section id="features" className="features">
        <div className="features__header">
          <p className="sr sr-delay-1 features__label">
            <span className="features__label-line" />
            Capabilities
          </p>
          <h2 className="sr sr-delay-2 features__title">Built for voice-first companion chat.</h2>
          <p className="sr sr-delay-3 features__subtitle">
            BYOK AI, speech, voice, hands-free wake, camera context, and local conversation history in one iOS app.
          </p>
        </div>

        <div className="features__grid">
          {features.map((feature, i) => (
            <div key={feature.title} className={`sr sr-delay-${i + 3} feature-card`}>
              <span className="feature-card__icon">
                <i className={`fa-solid ${feature.icon}`} />
              </span>
              <h3 className="feature-card__title">{feature.title}</h3>
              <p className="feature-card__desc">{feature.desc}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="faq" className="faq">
        <div className="features__header">
          <p className="sr sr-delay-1 features__label">
            <span className="features__label-line" />
            FAQ
          </p>
          <h2 className="sr sr-delay-2 features__title">Frequently asked questions.</h2>
          <p className="sr sr-delay-3 features__subtitle">
            Free, open source, and bring-your-own-key. Here is how Scowld works.
          </p>
        </div>

        <div className="faq__list">
          {faqs.map((item, i) => (
            <details key={item.q} className={`sr sr-delay-${Math.min(i + 3, 8)} faq__item`}>
              <summary className="faq__question">
                {item.q}
                <span className="faq__icon" aria-hidden="true" />
              </summary>
              <p className="faq__answer">{item.a}</p>
            </details>
          ))}
        </div>
      </section>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "FAQPage",
            mainEntity: faqs.map((f) => ({
              "@type": "Question",
              name: f.q,
              acceptedAnswer: { "@type": "Answer", text: f.a },
            })),
          }),
        }}
      />

      <footer className="footer">
        <div className="footer__inner">
          <div className="footer__left">
            <Link href="/" className="footer__logo">
              <Image src="/logo.png" alt="" width={15} height={15} className="footer__logo-img" />
              Scowld
            </Link>
            <span className="footer__divider" />
            <div className="footer__links">
              <a href={links.instagram} target="_blank" rel="noopener noreferrer" className="footer__link">Instagram</a>
              <a href={links.x} target="_blank" rel="noopener noreferrer" className="footer__link">X @apoorvdarshan</a>
              <a href={links.github} target="_blank" rel="noopener noreferrer" className="footer__link">GitHub</a>
              <a href={links.productHunt} target="_blank" rel="noopener noreferrer" className="footer__link">Product Hunt</a>
              <Link href="/blog" className="footer__link">Blog</Link>
              <Link href="/privacy" className="footer__link">Privacy</Link>
              <Link href="/terms" className="footer__link">Terms</Link>
            </div>
            <span className="footer__divider" />
            <p className="footer__copy">&copy; 2026 Apoorv Darshan</p>
          </div>

          <div className="footer__socials">
            {socialLinks.map((link) => (
              <a
                key={link.href}
                href={link.href}
                target={link.href.startsWith("mailto") ? undefined : "_blank"}
                rel={link.href.startsWith("mailto") ? undefined : "noopener noreferrer"}
                className="footer__social"
                aria-label={link.label}
              >
                <i className={link.icon} />
              </a>
            ))}
          </div>
        </div>
      </footer>
    </div>
  );
}
