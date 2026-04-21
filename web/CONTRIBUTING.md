# Contributing to Scowld Website

Thanks for your interest in contributing to the Scowld website.

## Getting Started

1. Fork the repo
2. Clone your fork
   ```bash
   git clone https://github.com/YOUR_USERNAME/scowld-web.git
   ```
3. Install dependencies
   ```bash
   npm install
   ```
4. Start the dev server
   ```bash
   npm run dev
   ```
5. Open http://localhost:3000

## Project Structure

```
app/
├── globals.css        # All styles (vanilla CSS, no Tailwind)
├── layout.tsx         # Root layout
├── page.tsx           # Landing page
├── privacy/page.tsx   # Privacy Policy
└── terms/page.tsx     # Terms of Service
public/
├── logo.png           # Scowld logo (transparent)
├── mockup.png         # iPhone app screenshot
└── ...
```

## Guidelines

- **Vanilla CSS only** — no Tailwind, no CSS-in-JS
- **BEM naming** — `.block__element` convention for class names
- **Clash Display** font for all text, JetBrains Mono for monospace
- **Keep it minimal** — dark theme, no flashy gradients or glows
- **Test responsive** — must look good on mobile and desktop

## Reporting Issues

Open an issue on GitHub with a screenshot and your browser/device info.

## Contact

**Apoorv Darshan** — ad13dtu@gmail.com
