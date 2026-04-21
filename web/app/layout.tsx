import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://scowld.vercel.app"),
  title: {
    default: "Scowld — AI Companion with 3D Anime Avatar, Voice & Vision",
    template: "%s | Scowld",
  },
  description: "Open-source AI companion with a 3D anime avatar, hands-free voice, real-time vision, and persistent memory. Supports Gemini, OpenAI, Claude & more.",
  keywords: ["AI companion", "AI assistant", "3D anime avatar", "voice assistant", "AI vision", "open source AI", "VRM avatar", "iOS AI app", "hands-free AI", "persistent memory AI", "scowld", "AI waifu"],
  authors: [{ name: "Apoorv Darshan", url: "https://github.com/apoorvdarshan" }],
  creator: "Apoorv Darshan",
  icons: { icon: "/logo.png", apple: "/logo.png" },
  alternates: { canonical: "https://scowld.vercel.app" },
  openGraph: {
    title: "Scowld — AI Companion with 3D Anime Avatar, Voice & Vision",
    description: "Open-source AI companion with a 3D anime avatar, hands-free voice, real-time vision, and persistent memory. Built in the open.",
    url: "https://scowld.vercel.app",
    siteName: "Scowld",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Scowld — AI Companion with 3D Anime Avatar",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Scowld — AI Companion with 3D Anime Avatar, Voice & Vision",
    description: "Open-source AI companion with a 3D anime avatar, hands-free voice, real-time vision, and persistent memory.",
    creator: "@apoorvdarshan",
    images: ["/og.png"],
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
        <link href="https://api.fontshare.com/v2/css?f[]=clash-display@200,300,400,500,600,700&display=swap" rel="stylesheet" />
        <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
      </head>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "SoftwareApplication",
              name: "Scowld",
              applicationCategory: "LifestyleApplication",
              operatingSystem: "iOS",
              description: "Open-source AI companion with a 3D anime avatar, hands-free voice, real-time vision, and persistent memory.",
              url: "https://scowld.vercel.app",
              author: { "@type": "Person", name: "Apoorv Darshan", url: "https://github.com/apoorvdarshan" },
              offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
            }),
          }}
        />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
