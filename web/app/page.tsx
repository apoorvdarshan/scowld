"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef } from "react";

/* ---- Data ---- */
const features = [
  { icon: "fa-microphone", title: "Hands-Free Voice", desc: "Always-on recognition. Talk naturally — auto-sends after you pause." },
  { icon: "fa-wand-magic-sparkles", title: "3D Anime Avatar", desc: "VRM character with real-time lip sync, idle animations, and reactions." },
  { icon: "fa-eye", title: "Vision", desc: "Front camera feeds to AI. She sees what you see. Privacy-first." },
  { icon: "fa-brain", title: "Persistent Memory", desc: "Remembers details across every conversation. Context that compounds." },
  { icon: "fa-bolt", title: "Multi-Provider LLM", desc: "Gemini, OpenAI, Claude, Ollama, xAI, Together. Switch anytime." },
  { icon: "fa-volume-high", title: "Premium TTS", desc: "ElevenLabs, OpenAI TTS, or native iOS. Expressive and natural." },
];

const tags = [
  "HANDS-FREE VOICE", "3D AVATAR", "VISION", "MEMORY", "MULTI-LLM",
  "ELEVENLABS", "ON-DEVICE STT", "OPEN SOURCE", "PRIVACY FIRST", "VRM",
];

/* ---- SVG components ---- */
function GitHubIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
    </svg>
  );
}

/* ---- Page ---- */
export default function Home() {
  const mainRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    /* IntersectionObserver for scroll-reveal */
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

    /* Word reveal for hero headline */
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

      {/* ====== NAV ====== */}
      <header className="nav">
        <Link href="/" className="nav__logo">
          <Image src="/logo.png" alt="" width={20} height={20} className="nav__logo-img" />
          Scowld
        </Link>
        <nav className="nav__links">
          <Link href="/privacy" className="nav__link">Privacy</Link>
          <Link href="/terms" className="nav__link">Terms</Link>
          <a
            href="https://github.com/apoorvdarshan/scowld"
            target="_blank"
            className="nav__github"
          >
            <GitHubIcon size={14} />
          </a>
        </nav>
      </header>

      {/* ====== HERO ====== */}
      <section className="hero">
        <div className="hero__grid">

          {/* Left column */}
          <div className="hero__content">

            {/* Badge */}
            <div className="sr sr-delay-1 hero__badge">
              <span className="hero__badge-dot">
                <span className="hero__badge-dot-ping" />
                <span className="hero__badge-dot-solid" />
              </span>
              <span className="hero__badge-text">Open source on GitHub</span>
            </div>

            {/* Headline */}
            <h1 className="hero__heading">
              <span className="word-reveal"><span>Talk to her.</span></span>
              <br />
              <span className="word-reveal"><span className="hero__heading-dim">She remembers.</span></span>
            </h1>

            {/* Description */}
            <p className="sr sr-delay-2 hero__desc">
              An AI companion with a 3D anime avatar, hands-free voice, real-time vision, and memory that grows. Built in the open.
            </p>

            {/* Buttons */}
            <div className="sr sr-delay-3 hero__buttons">
              <a
                href="https://github.com/apoorvdarshan/scowld"
                target="_blank"
                className="btn-primary"
              >
                <GitHubIcon size={16} /> View on GitHub
              </a>
              <a href="https://testflight.apple.com/join/7WgDe7e4" target="_blank" className="btn-secondary">
                Join Beta <span className="btn-secondary__arrow">&rarr;</span>
              </a>
            </div>
            <a
              href="https://www.producthunt.com/products/scowld?utm_source=badge-featured&utm_medium=badge&utm_campaign=badge-scowld"
              target="_blank"
              rel="noopener noreferrer"
              className="sr sr-delay-4 btn-ph"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                <path d="M13.604 8.4h-3.405V12h3.405a1.8 1.8 0 0 0 0-3.6zM12 0C5.372 0 0 5.372 0 12s5.372 12 12 12 12-5.372 12-12S18.628 0 12 0zm1.604 14.4h-3.405V18H7.801V6h5.804a4.2 4.2 0 0 1 0 8.4z"/>
              </svg>
              Find us on Product Hunt
            </a>
          </div>

          {/* Right column -- Phone mockup */}
          <div className="hero__phone-wrap">
            <div className="sr sr-delay-4 phone-float">
              <Image
                src="/mockup.png"
                alt="Scowld app screenshot"
                width={320}
                height={654}
                priority
                className="hero__phone"
              />
            </div>
          </div>
        </div>
      </section>

      {/* ====== MARQUEE ====== */}
      <div className="marquee">
        <div className="marquee__track">
          {[0, 1].map((k) => (
            <div key={k} className="marquee__group">
              {tags.map((t) => (
                <span key={t + k} className="marquee__item">
                  <span className="marquee__dot" />
                  {t}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>

      {/* ====== FEATURES ====== */}
      <section id="features" className="features">
        <div className="features__header">
          <p className="sr sr-delay-1 features__label">
            <span className="features__label-line" />
            Capabilities
          </p>
          <h2 className="sr sr-delay-2 features__title">Everything built in.</h2>
          <p className="sr sr-delay-3 features__subtitle">
            Natural conversation. Privacy by default. Your choice of AI.
          </p>
        </div>

        <div className="features__grid">
          {features.map((f, i) => (
            <div key={f.title} className={`sr sr-delay-${i + 3} feature-card`}>
              <span className="feature-card__icon">
                <i className={`fa-solid ${f.icon}`} />
              </span>
              <h3 className="feature-card__title">{f.title}</h3>
              <p className="feature-card__desc">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ====== FOOTER ====== */}
      <footer className="footer">
        <div className="footer__inner">
          {/* Left: logo, links, copyright */}
          <div className="footer__left">
            <Link href="/" className="footer__logo">
              <Image src="/logo.png" alt="" width={15} height={15} className="footer__logo-img" />
              Scowld
            </Link>
            <span className="footer__divider" />
            <div className="footer__links">
              <a href="https://github.com/apoorvdarshan/scowld" target="_blank" className="footer__link">GitHub</a>
              <Link href="/privacy" className="footer__link">Privacy</Link>
              <Link href="/terms" className="footer__link">Terms</Link>
            </div>
            <span className="footer__divider" />
            <p className="footer__copy">&copy; 2026 Apoorv Darshan</p>
          </div>

          {/* Right: social icons */}
          <div className="footer__socials">
            {[
              {
                href: "mailto:ad13dtu@gmail.com",
                icon: (
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <rect x="2" y="4" width="20" height="16" rx="2" />
                    <path d="M22 4l-10 8L2 4" />
                  </svg>
                ),
              },
              {
                href: "https://x.com/apoorvdarshan",
                icon: (
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                  </svg>
                ),
              },
              {
                href: "https://linkedin.com/in/apoorvdarshan",
                icon: (
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
                  </svg>
                ),
              },
              {
                href: "https://github.com/apoorvdarshan/scowld",
                icon: <GitHubIcon size={12} />,
              },
            ].map((s) => (
              <a
                key={s.href}
                href={s.href}
                target={s.href.startsWith("mailto") ? undefined : "_blank"}
                className="footer__social"
              >
                {s.icon}
              </a>
            ))}
          </div>
        </div>
      </footer>
    </div>
  );
}
