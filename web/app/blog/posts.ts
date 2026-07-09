// Blog content lives here as structured data so each post renders with
// consistent styling and gets its own metadata + structured data.

export type PostSection = {
  heading?: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type Post = {
  slug: string;
  title: string;
  description: string;
  excerpt: string;
  datePublished: string; // ISO date
  dateModified: string; // ISO date
  readMinutes: number;
  keywords: string[];
  sections: PostSection[];
  faq?: { q: string; a: string }[];
};

export const posts: Post[] = [
  {
    slug: "ai-companion-that-can-see",
    title: "An AI Companion That Can See What You Show It",
    description:
      "How Scowld's optional camera vision lets an AI voice companion respond to real objects you hold up — on iPhone and iPad, using your own API key.",
    excerpt:
      "Most AI apps only read what you type. Scowld can optionally use the camera so the companion reacts to what you actually show it — here's how that works, and how it stays private.",
    datePublished: "2026-07-09",
    dateModified: "2026-07-09",
    readMinutes: 4,
    keywords: [
      "AI companion that can see",
      "AI vision app",
      "AI that responds to what you show it",
      "iOS AI vision",
      "camera AI companion",
    ],
    sections: [
      {
        paragraphs: [
          "Text is a narrow way to talk to an AI. You describe a thing in words, the model imagines it, and something is always lost in translation. Scowld takes a different route: with the camera enabled, the companion can respond to what you physically show it — hold up an object, point at something on your desk, or just let it see the room.",
          "This vision feature is optional and off by default. When you turn it on, it turns a one-way chat into something closer to showing a friend what you're looking at.",
        ],
      },
      {
        heading: "How the camera vision works",
        paragraphs: [
          "When vision is enabled and your message would benefit from it, Scowld captures a single frame from the front camera and sends it to the AI provider you configured alongside your text. The provider's vision model reads the image and the companion replies out loud.",
        ],
        bullets: [
          "Frames are captured on device and only sent when you send a message with vision enabled.",
          "Vision uses whichever AI provider you picked that supports images — for example Gemini, OpenAI, or Claude.",
          "Images are never saved to your photo library by Scowld.",
        ],
      },
      {
        heading: "Privacy by design",
        paragraphs: [
          "Vision is opt-in and scoped to the moment you use it. There is no always-on recording, and Scowld does not run a server that sees your images — the frame goes straight from your device to the provider whose key you added.",
          "Scowld also does not use Apple's TrueDepth API or ARKit face tracking, and it does not collect, store, or share face geometry, depth maps, facial expressions, or any other face data. The camera is there to see the world you point it at, not to profile you.",
        ],
      },
      {
        heading: "When showing beats telling",
        bullets: [
          "Ask what something is when you don't have the words for it.",
          "Get a second opinion on an outfit, a label, or a screen.",
          "Talk through something on your desk without typing a description.",
        ],
      },
      {
        heading: "How to try it",
        paragraphs: [
          "Download Scowld from the App Store, add an AI provider key that supports vision in Settings, then enable the camera from the composer and send a message. Because Scowld is bring-your-own-key, you only pay your provider for what you use — there's no subscription.",
        ],
      },
    ],
    faq: [
      {
        q: "Does Scowld record video?",
        a: "No. Vision captures a single still frame only when you send a message with the camera enabled. There is no continuous recording, and images are not saved to your photo library.",
      },
      {
        q: "Which providers support vision in Scowld?",
        a: "Image input works with vision-capable providers such as Google Gemini, OpenAI, and Anthropic Claude. You choose the provider and add your own key in Settings.",
      },
    ],
  },
  {
    slug: "bring-your-own-key-ai-app",
    title: "What 'Bring Your Own Key' Means for an AI App",
    description:
      "Scowld is a bring-your-own-key (BYOK) iOS AI companion — no subscription, no server storing your keys. Here's how BYOK works and why it's more private and often cheaper.",
    excerpt:
      "Most AI apps charge a monthly fee and route your conversations through their servers. Bring-your-own-key flips that: you use your own provider keys, stored on your device. Here's what that actually means.",
    datePublished: "2026-07-09",
    dateModified: "2026-07-09",
    readMinutes: 5,
    keywords: [
      "bring your own key AI app",
      "BYOK AI iOS",
      "free AI companion app",
      "open source AI companion",
      "no subscription AI app",
    ],
    sections: [
      {
        paragraphs: [
          "\"Bring your own key\" (BYOK) means an app doesn't sell you AI usage — instead, you bring an API key from a provider you already trust, and the app talks to that provider directly on your behalf. Scowld is built this way from the ground up.",
          "The practical result: there's no Scowld subscription, no paywall, and no middle-man server holding your conversations or your keys.",
        ],
      },
      {
        heading: "Why BYOK matters",
        bullets: [
          "Privacy: requests go from your device straight to the provider you configured. Scowld runs no backend that receives, proxies off-device, or stores your keys or chats.",
          "Cost: you pay your chosen provider for actual usage instead of a flat monthly fee, which is often far cheaper for typical use.",
          "Control: switch providers and models whenever you want, and stop instantly by removing the key.",
        ],
      },
      {
        heading: "Where your keys are stored",
        paragraphs: [
          "Keys you enter live in the iOS Keychain on your device. They are not bundled in the app binary, not written to plain preferences, and not committed to the open-source repository. Delete the app or remove a key in Settings and it's gone.",
        ],
      },
      {
        heading: "Which providers Scowld supports",
        paragraphs: [
          "You can mix and match across AI chat, speech-to-text, and text-to-speech:",
        ],
        bullets: [
          "AI chat: Google Gemini, OpenAI, Anthropic Claude, Ollama, Groq, OpenRouter, xAI, Together AI, Hugging Face, Venice AI, and Moonshot AI.",
          "Speech-to-text: native iOS speech, OpenAI Whisper, Groq Whisper, Deepgram, AssemblyAI, and Google Cloud Speech-to-Text.",
          "Text-to-speech: ElevenLabs and OpenAI voices.",
        ],
      },
      {
        heading: "Getting started",
        paragraphs: [
          "Download Scowld, open Settings, choose an AI provider, and paste your key. Add an ElevenLabs or OpenAI key under Text-to-Speech if you want spoken replies. That's the whole setup — no account, no card on file with Scowld. Scowld is also open source under the MIT License, so you can read exactly how your keys are handled.",
        ],
      },
    ],
    faq: [
      {
        q: "Is a bring-your-own-key app actually free?",
        a: "The Scowld app is free and open source with no subscription. You only pay the AI, speech-to-text, and text-to-speech providers you choose, based on your own usage.",
      },
      {
        q: "Can Scowld see my API keys?",
        a: "No. Keys are stored in the iOS Keychain on your device and requests go directly to the provider. There is no Scowld server that receives or stores your keys.",
      },
    ],
  },
];

export function getPost(slug: string): Post | undefined {
  return posts.find((post) => post.slug === slug);
}

export function formatPostDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}
