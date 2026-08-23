import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://www.scowld.xyz"),
  title: {
    default: "Scowld - AI Voice Companion for iOS",
    template: "%s | Scowld",
  },
  description: "Scowld is a free, open-source iOS AI voice companion with an animated avatar and bring-your-own-key AI, speech-to-text, and text-to-speech, plus optional vision and saved past chats.",
  keywords: ["AI companion", "AI voice companion", "AI companion app", "AI assistant", "animated avatar", "voice assistant", "AI vision", "AI that can see", "AI companion that can see", "VRM avatar", "iOS AI app", "BYOK", "bring your own key", "open source AI app", "OpenAI", "Claude", "Gemini", "ElevenLabs", "voice chat", "hands-free AI", "Character AI alternative", "scowld"],
  authors: [{ name: "Apoorv Darshan", url: "https://x.com/apoorvdarshan" }],
  creator: "Apoorv Darshan",
  publisher: "Apoorv Darshan",
  applicationName: "Scowld",
  category: "technology",
  icons: { icon: "/logo.png", apple: "/logo.png" },
  alternates: { canonical: "/" },
  openGraph: {
    title: "Scowld - AI Voice Companion for iOS",
    description: "Talk by voice or text with an animated AI companion. Free and open source — bring your own AI, speech-to-text, and text-to-speech keys.",
    url: "https://www.scowld.xyz",
    siteName: "Scowld",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og-image-scowld.jpg",
        width: 1200,
        height: 630,
        alt: "Scowld AI voice companion",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Scowld - AI Voice Companion for iOS",
    description: "Animated AI companion with voice, text, optional vision, and saved past chats.",
    creator: "@apoorvdarshan",
    images: [{ url: "/og-image-scowld.jpg", alt: "Scowld AI voice companion for iOS" }],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true },
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://api.fontshare.com" crossOrigin="anonymous" />
        <link rel="preconnect" href="https://fonts.googleapis.com" crossOrigin="anonymous" />
        <link rel="preconnect" href="https://cdnjs.cloudflare.com" crossOrigin="anonymous" />
        <link rel="dns-prefetch" href="https://api.fontshare.com" />
        <link href="https://api.fontshare.com/v2/css?f[]=clash-display@200,300,400,500,600,700&display=swap" rel="stylesheet" />
        <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
      </head>
      <body>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                function prevent(event) {
                  event.preventDefault();
                  event.stopPropagation();
                  return false;
                }
                ['contextmenu', 'selectstart', 'dragstart', 'copy', 'cut'].forEach(function(type) {
                  document.addEventListener(type, prevent, true);
                });
              })();
            `,
          }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "SoftwareApplication",
              name: "Scowld",
              applicationCategory: "LifestyleApplication",
              applicationSubCategory: "AI Voice Companion",
              operatingSystem: "iOS 17.0 or later",
              softwareVersion: "2.0.1",
              description: "Free, open-source iOS AI voice companion with an animated avatar and bring-your-own-key AI, speech-to-text, and text-to-speech, plus optional vision and saved past chats.",
              url: "https://www.scowld.xyz",
              image: "https://www.scowld.xyz/og-image-scowld.jpg",
              screenshot: "https://www.scowld.xyz/screenshot.png",
              downloadUrl: "https://apps.apple.com/app/id6760672848",
              installUrl: "https://apps.apple.com/app/id6760672848",
              featureList: [
                "Bring-your-own-key AI providers (Gemini, OpenAI, Claude, Ollama, Groq, OpenRouter, xAI, and more)",
                "Hands-free wake word to start voice input on device",
                "Voice input with native iOS speech or cloud speech-to-text (Deepgram, Whisper, AssemblyAI, Google Cloud)",
                "ElevenLabs and OpenAI text-to-speech for spoken replies",
                "Animated VRM avatar with lip sync and expressions",
                "Optional camera vision so the companion can respond to what you show it",
                "Saved past chats reusable as conversation context",
              ],
              author: { "@type": "Person", name: "Apoorv Darshan", url: "https://x.com/apoorvdarshan" },
              sameAs: [
                "https://www.instagram.com/scowld_/",
                "https://www.producthunt.com/products/scowld",
                "https://github.com/aopv/scowld",
                "https://x.com/apoorvdarshan",
              ],
              offers: {
                "@type": "Offer",
                price: "0",
                priceCurrency: "USD",
              },
            }),
          }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "WebSite",
              name: "Scowld",
              alternateName: "Scowld AI Voice Companion",
              url: "https://www.scowld.xyz",
              description:
                "Free, open-source iOS AI voice companion with an animated avatar and bring-your-own-key AI, speech-to-text, and text-to-speech.",
            }),
          }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "Organization",
              name: "Scowld",
              url: "https://www.scowld.xyz",
              logo: "https://www.scowld.xyz/logo.png",
              founder: { "@type": "Person", name: "Apoorv Darshan" },
              sameAs: [
                "https://www.instagram.com/scowld_/",
                "https://www.producthunt.com/products/scowld",
                "https://github.com/aopv/scowld",
                "https://x.com/apoorvdarshan",
              ],
            }),
          }}
        />
        {children}
      </body>
    </html>
  );
}
