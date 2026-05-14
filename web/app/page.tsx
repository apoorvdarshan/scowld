"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef } from "react";

const links = {
  productHunt: "https://www.producthunt.com/products/scowld",
  linkedIn: "https://www.linkedin.com/company/scowld",
  instagram: "https://www.instagram.com/scowld_/",
  koFi: "https://ko-fi.com/apoorvdarshan",
  x: "https://x.com/apoorvdarshan",
  mail: "mailto:ad13dtu@gmail.com",
};

const features = [
  { icon: "fa-microphone-lines", title: "Voice input", desc: "Speak from the iOS composer. Deepgram turns your voice into text through Scowld's hosted backend." },
  { icon: "fa-wand-magic-sparkles", title: "Animated companion", desc: "A VRM character with lip sync, idle animation, and expressive response playback." },
  { icon: "fa-eye", title: "Optional vision", desc: "Enable camera context when you want the AI to respond to what you are seeing." },
  { icon: "fa-comments", title: "Past chats", desc: "Save conversations locally, switch between chats, and reuse one as context for future replies." },
  { icon: "fa-bolt", title: "Hosted Gemini", desc: "Gemini 3 Flash starts the response path with hosted fallback models for reliability." },
  { icon: "fa-volume-high", title: "ElevenLabs voice", desc: "Selectable ElevenLabs voices, custom voice ID support, and bundled local voice previews." },
];

const tags = [
  "SCOWLD PLUS", "VOICE CREDITS", "GEMINI", "ELEVENLABS", "DEEPGRAM STT",
  "ANIMATED AVATAR", "VISION", "PAST CHATS", "IOS", "PRIVACY FIRST",
];

const socialLinks = [
  { href: links.linkedIn, label: "LinkedIn", icon: "fa-brands fa-linkedin-in" },
  { href: links.instagram, label: "Instagram", icon: "fa-brands fa-instagram" },
  { href: links.koFi, label: "Ko-fi", icon: "fa-solid fa-mug-saucer" },
  { href: links.x, label: "X", icon: "fa-brands fa-x-twitter" },
  { href: links.mail, label: "Email", icon: "fa-solid fa-envelope" },
];

const screenshots = [
  { src: "/screenshots/aria.webp", title: "Aria", caption: "Main companion view" },
  { src: "/screenshots/bella.webp", title: "Bella", caption: "Character switching" },
  { src: "/screenshots/ciel.webp", title: "Ciel", caption: "Voice-first chat" },
  { src: "/screenshots/chats.webp", title: "Chats", caption: "Past conversations" },
  { src: "/screenshots/customization.webp", title: "Settings", caption: "Voice and character controls" },
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
          <Link href="/privacy" className="nav__link">Privacy</Link>
          <Link href="/terms" className="nav__link">Terms</Link>
          <a href={links.linkedIn} target="_blank" rel="noopener noreferrer" className="nav__link">LinkedIn</a>
          <a href={links.instagram} target="_blank" rel="noopener noreferrer" className="nav__link">Instagram</a>
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
              <span className="hero__badge-text">Scowld Plus for iOS</span>
            </div>

            <h1 className="hero__heading">
              <span className="word-reveal"><span>Talk to her.</span></span>
              <br />
              <span className="word-reveal"><span className="hero__heading-dim">She remembers.</span></span>
            </h1>

            <p className="sr sr-delay-2 hero__desc">
              A paid AI voice companion with an animated character, Gemini chat, Deepgram speech-to-text, ElevenLabs speech, optional vision, and saved past chats.
            </p>

            <div className="sr sr-delay-3 hero__buttons">
              <button
                type="button"
                className="btn-primary btn-appstore"
                onClick={() => window.alert("Available soon")}
              >
                <i className="fa-brands fa-apple" aria-hidden="true" />
                Download on App Store
              </button>
              <a href={links.productHunt} target="_blank" rel="noopener noreferrer" className="btn-secondary">
                Vote on Product Hunt
              </a>
              <a href={links.koFi} target="_blank" rel="noopener noreferrer" className="btn-secondary">
                Support on Ko-fi <span className="btn-secondary__arrow">&rarr;</span>
              </a>
            </div>

            <div className="sr sr-delay-4 hero__socials" aria-label="Scowld social links">
              <a href={links.instagram} target="_blank" rel="noopener noreferrer" className="hero__social-link">
                <i className="fa-brands fa-instagram" aria-hidden="true" />
                Instagram
              </a>
              <a href={links.linkedIn} target="_blank" rel="noopener noreferrer" className="hero__social-link">
                <i className="fa-brands fa-linkedin-in" aria-hidden="true" />
                LinkedIn
              </a>
              <a href={links.x} target="_blank" rel="noopener noreferrer" className="hero__social-link">
                <i className="fa-brands fa-x-twitter" aria-hidden="true" />
                @apoorvdarshan
              </a>
            </div>
          </div>

          <div className="hero__phone-wrap">
            <div className="sr sr-delay-4 phone-float">
              <Image
                src="/mockup.png"
                alt="Scowld app screenshot"
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

      <section className="screenshots" aria-labelledby="screenshots-title">
        <div className="screenshots__header">
          <p className="sr sr-delay-1 screenshots__label">
            <span className="screenshots__label-line" />
            Screenshots
          </p>
          <h2 id="screenshots-title" className="sr sr-delay-2 screenshots__title">See Scowld in motion.</h2>
          <p className="sr sr-delay-3 screenshots__subtitle">
            Character views, saved chats, and settings built around fast voice conversation.
          </p>
        </div>

        <div className="screenshots__rail" aria-label="Scowld app screenshots">
          {screenshots.map((shot, i) => (
            <figure key={shot.src} className={`sr sr-delay-${i + 3} screenshot-card`}>
              <Image
                src={shot.src}
                alt={`${shot.title} screenshot`}
                width={720}
                height={1561}
                className="screenshot-card__image"
              />
              <figcaption className="screenshot-card__caption">
                <span className="screenshot-card__title">{shot.title}</span>
                <span className="screenshot-card__text">{shot.caption}</span>
              </figcaption>
            </figure>
          ))}
        </div>
      </section>

      <section id="features" className="features">
        <div className="features__header">
          <p className="sr sr-delay-1 features__label">
            <span className="features__label-line" />
            Capabilities
          </p>
          <h2 className="sr sr-delay-2 features__title">Built for voice-first companion chat.</h2>
          <p className="sr sr-delay-3 features__subtitle">
            Hosted AI, speech, voice, camera context, billing, and local conversation history in one iOS app.
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

      <footer className="footer">
        <div className="footer__inner">
          <div className="footer__left">
            <Link href="/" className="footer__logo">
              <Image src="/logo.png" alt="" width={15} height={15} className="footer__logo-img" />
              Scowld
            </Link>
            <span className="footer__divider" />
            <div className="footer__links">
              <a href={links.linkedIn} target="_blank" rel="noopener noreferrer" className="footer__link">LinkedIn</a>
              <a href={links.instagram} target="_blank" rel="noopener noreferrer" className="footer__link">Instagram</a>
              <a href={links.productHunt} target="_blank" rel="noopener noreferrer" className="footer__link">Product Hunt</a>
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
