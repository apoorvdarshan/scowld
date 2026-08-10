import { getCloudflareContext } from "@opennextjs/cloudflare";

export const runtime = "nodejs";

const OWNER = "apoorvdarshan";
const REPOSITORY = "scowld";
const ONE_DAY = 86_400_000;

type ThemeName = "light" | "dark";

const themes = {
  dark: {
    background: "#080A12",
    panel: "#101522",
    border: "#273148",
    grid: "#20283B",
    text: "#F5F7FF",
    muted: "#8993AA",
  },
  light: {
    background: "#FAFBFF",
    panel: "#F1F4FC",
    border: "#D7DDEE",
    grid: "#E0E5F1",
    text: "#171B2B",
    muted: "#69738B",
  },
};

export async function GET(request: Request) {
  const themeName: ThemeName = new URL(request.url).searchParams.get("theme") === "dark"
    ? "dark"
    : "light";

  try {
    const { env } = await getCloudflareContext({ async: true });
    const token = (env as CloudflareEnv & { GITHUB_TOKEN?: string }).GITHUB_TOKEN;

    if (!token) {
      throw new Error("GITHUB_TOKEN is not configured");
    }

    const stars = await fetchStarHistory(token);
    return svgResponse(renderStarHistory(stars, themeName), 200, 21_600);
  } catch (error) {
    console.error("Unable to render Scowld star history", error);
    return svgResponse(renderError(themeName), 503, 60);
  }
}

export async function HEAD(request: Request) {
  const response = await GET(request);
  return new Response(null, { status: response.status, headers: response.headers });
}

async function fetchStarHistory(token: string) {
  const stars: string[] = [];

  for (let page = 1; page <= 100; page += 1) {
    const response = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPOSITORY}/stargazers?per_page=100&page=${page}`,
      {
        headers: {
          Accept: "application/vnd.github.star+json",
          Authorization: `Bearer ${token}`,
          "User-Agent": "scowld-star-history",
          "X-GitHub-Api-Version": "2022-11-28",
        },
      },
    );

    if (!response.ok) {
      throw new Error(`GitHub returned ${response.status}`);
    }

    const payload = (await response.json()) as Array<{ starred_at?: string }>;

    if (!Array.isArray(payload)) {
      throw new Error("GitHub returned an unexpected response");
    }

    for (const item of payload) {
      if (typeof item.starred_at === "string") stars.push(item.starred_at);
    }

    if (payload.length < 100) break;
    if (page === 100) throw new Error("Star history exceeded the pagination limit");
  }

  return stars.sort((left, right) => left.localeCompare(right));
}

function renderStarHistory(starredAtValues: string[], themeName: ThemeName) {
  const theme = themes[themeName];
  const width = 960;
  const height = 520;
  const plot = { left: 76, top: 158, right: 904, bottom: 395 };
  const now = Date.now();
  const stars = starredAtValues
    .map((value) => new Date(value).getTime())
    .filter(Number.isFinite)
    .sort((left, right) => left - right);
  const start = Math.min((stars[0] ?? now) - ONE_DAY, now - 30 * ONE_DAY);
  const end = Math.max(now, start + ONE_DAY);
  const maximum = niceMaximum(Math.max(stars.length, 1));
  const x = (timestamp: number) =>
    plot.left + ((timestamp - start) / (end - start)) * (plot.right - plot.left);
  const y = (count: number) =>
    plot.bottom - (count / maximum) * (plot.bottom - plot.top);
  let starIndex = 0;
  const points = ticks(start, end, 52).map((timestamp) => {
    while (starIndex < stars.length && stars[starIndex] <= timestamp) starIndex += 1;
    return [x(timestamp), y(starIndex)] as const;
  });
  const path = smoothPath(points);
  const area = `${path} L${plot.right} ${plot.bottom} L${plot.left} ${plot.bottom} Z`;
  const yGrid = numberTicks(maximum, 6)
    .map((value) => {
      const position = y(value);
      return `<line x1="${plot.left}" y1="${position}" x2="${plot.right}" y2="${position}" class="grid"/><text x="${plot.left - 16}" y="${position + 5}" text-anchor="end" class="axis">${value}</text>`;
    })
    .join("");
  const dateLabels = ticks(start, end, 4)
    .map((timestamp, index, values) => {
      const anchor = index === 0 ? "start" : index === values.length - 1 ? "end" : "middle";
      const label = new Intl.DateTimeFormat("en", {
        month: "short",
        ...(end - start >= 365 * ONE_DAY ? { year: "numeric" } : { day: "numeric" }),
        timeZone: "UTC",
      }).format(new Date(timestamp));
      return `<text x="${x(timestamp)}" y="${plot.bottom + 38}" text-anchor="${anchor}" class="axis">${label}</text>`;
    })
    .join("");
  const currentY = y(stars.length);
  const reactions = [0.3, 0.56, 0.8]
    .map((ratio, index) => {
      const point = points[Math.round((points.length - 1) * ratio)];
      const glyph = ["✦", "♡", "♪"][index];
      return `<g transform="translate(${point[0]} ${point[1] - 7}) rotate(${index % 2 ? 5 : -5})" filter="url(#soft-sketch)"><path d="M-12 -30 Q-12 -42 0 -42 H18 Q30 -42 30 -30 V-16 Q30 -5 18 -5 H7 L1 3 L0 -5 Q-12 -5 -12 -17Z" fill="${theme.panel}" stroke="${index === 0 ? "#35D9FF" : index === 1 ? "#C968FF" : "#738BFF"}" stroke-width="1.8"/><text x="9" y="-18" text-anchor="middle" fill="${index === 0 ? "#35D9FF" : index === 1 ? "#C968FF" : "#738BFF"}" font-family="ui-rounded,'Arial Rounded MT Bold',sans-serif" font-size="18" font-weight="800">${glyph}</text></g>`;
    })
    .join("");
  const dark = themeName === "dark";
  const card = dark ? "#0D1120" : "#FFFFFF";
  const hair = dark ? "#274BC8" : "#2148C7";
  const ink = dark ? "#F8FAFF" : "#17203B";

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
  <title id="title">Scowld GitHub star history</title>
  <desc id="description">${stars.length} GitHub stars over time for ${OWNER}/${REPOSITORY}.</desc>
  <defs>
    <linearGradient id="voice-line" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#2DDCFF"/><stop offset=".5" stop-color="#6387FF"/><stop offset="1" stop-color="#D56EFF"/></linearGradient>
    <linearGradient id="voice-area" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#6387FF" stop-opacity=".32"/><stop offset="1" stop-color="#D56EFF" stop-opacity=".02"/></linearGradient>
    <radialGradient id="aura" cx="17%" cy="2%" r="68%"><stop stop-color="#35D9FF" stop-opacity="${dark ? ".15" : ".08"}"/><stop offset="1" stop-color="#738BFF" stop-opacity="0"/></radialGradient>
    <radialGradient id="eye" cx="48%" cy="35%" r="65%"><stop stop-color="#FFF7C7"/><stop offset=".28" stop-color="#70E7FF"/><stop offset=".65" stop-color="#3475F4"/><stop offset="1" stop-color="#101C62"/></radialGradient>
    <pattern id="stars" width="32" height="32" patternUnits="userSpaceOnUse"><circle cx="5" cy="6" r=".8" fill="${theme.grid}"/><circle cx="24" cy="21" r=".55" fill="#738BFF" opacity=".45"/></pattern>
    <filter id="soft-sketch" x="-35%" y="-35%" width="170%" height="170%"><feTurbulence type="fractalNoise" baseFrequency=".022" numOctaves="2" seed="21" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale=".65"/></filter>
    <filter id="dream-glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="5" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <clipPath id="plot"><rect x="${plot.left}" y="${plot.top - 10}" width="${plot.right - plot.left}" height="${plot.bottom - plot.top + 10}"/></clipPath>
    <style>.axis{fill:${theme.muted};font:600 13px 'Trebuchet MS',sans-serif}.grid{stroke:${theme.grid};stroke-width:1.2;stroke-dasharray:4 8;stroke-linecap:round}.title{fill:${ink};font:800 25px ui-rounded,'Arial Rounded MT Bold','Trebuchet MS',sans-serif}.muted{fill:${theme.muted};font:600 13.5px 'Trebuchet MS',sans-serif}.tiny{fill:${theme.muted};font:700 11px 'Trebuchet MS',sans-serif;letter-spacing:1px}</style>
  </defs>
  <rect width="960" height="520" rx="30" fill="${theme.background}"/>
  <rect x="16" y="16" width="928" height="488" rx="27" fill="${card}" stroke="${theme.border}" stroke-width="1.5"/>
  <rect x="27" y="27" width="906" height="466" rx="21" fill="url(#stars)" stroke="${theme.border}" stroke-dasharray="6 9"/>
  <rect x="39" y="32" width="67" height="67" rx="22" fill="url(#aura)" stroke="#477DFF" stroke-width="1.5"/>
  <g transform="translate(42 35)" filter="url(#soft-sketch)">
    <path d="M8 35 C5 12 18 1 32 1 C48 1 61 13 58 38 C56 57 47 62 32 62 C16 62 9 54 8 35Z" fill="${hair}"/>
    <path d="M14 34 C14 20 22 13 32 13 C44 13 52 21 51 35 C50 49 44 55 32 55 C20 55 14 49 14 34Z" fill="#FFE7DE"/>
    <path d="M11 24 C15 8 31 5 42 11 C50 15 55 24 52 35 C45 28 42 20 38 17 C33 24 25 28 15 30Z" fill="${hair}"/>
    <circle cx="24" cy="36" r="6.7" fill="url(#eye)" stroke="#121A4D" stroke-width="1.5"/><circle cx="41" cy="36" r="6.7" fill="url(#eye)" stroke="#121A4D" stroke-width="1.5"/><circle cx="22" cy="34" r="2" fill="white"/><circle cx="39" cy="34" r="2" fill="white"/>
    <path d="M29 47 Q33 50 37 47" fill="none" stroke="#C67682" stroke-width="1.6" stroke-linecap="round"/>
    <path d="M8 27 L0 20 L7 16 M56 27 L64 20 L57 16" fill="#10172D" stroke="#35D9FF" stroke-width="2"/>
  </g>
  <text x="124" y="57" class="title">Bella noticed every star.</text>
  <text x="125" y="81" class="muted">Scowld’s little companion constellation keeps growing.</text>
  <g transform="translate(748 36)" filter="url(#soft-sketch)"><path d="M16 0 H123 Q140 0 140 16 V38 Q140 52 123 52 H16 Q0 52 0 36 V16 Q0 0 16 0Z" fill="${dark ? "#1B2142" : "#EEF2FF"}" stroke="#738BFF" stroke-width="1.5" stroke-dasharray="5 4"/><path d="M24 10 L28 21 L39 24 L29 29 L27 40 L21 31 L10 33 L17 24 L12 14 L23 18Z" fill="#FFE17A" filter="url(#dream-glow)"/><text x="49" y="34" fill="${ink}" font-family="ui-rounded,'Arial Rounded MT Bold',sans-serif" font-size="21" font-weight="800">${stars.length}</text><text x="98" y="32" class="tiny">STARS</text></g>
  <path d="M105 108 C180 124 235 109 300 128" fill="none" stroke="#35D9FF" stroke-width="1.5" stroke-dasharray="4 7" opacity=".45"/><path d="M856 107 C800 123 753 110 701 130" fill="none" stroke="#C968FF" stroke-width="1.5" stroke-dasharray="4 7" opacity=".4"/>
  ${yGrid}${dateLabels}
  <g clip-path="url(#plot)"><path d="${area}" fill="url(#voice-area)"/><path d="${path}" fill="none" stroke="#738BFF" stroke-width="9" opacity=".13"/><path d="${path}" fill="none" stroke="url(#voice-line)" stroke-width="4.5" stroke-linecap="round" filter="url(#soft-sketch)"/></g>
  ${reactions}
  <g transform="translate(${plot.right} ${currentY})" filter="url(#soft-sketch)"><circle r="9" fill="#C968FF" opacity=".18"/><circle r="6.7" fill="#35D9FF" stroke="${card}" stroke-width="3"/><path d="M5 -7 L8 -15 M9 -5 L17 -8 M5 0 L12 5" stroke="#FFE17A" stroke-width="2" stroke-linecap="round"/></g>
  <g transform="translate(57 451)" opacity=".75" filter="url(#soft-sketch)"><rect x="0" y="2" width="18" height="28" rx="9" fill="none" stroke="#35D9FF" stroke-width="2.2"/><path d="M-5 18 Q-5 36 9 36 Q23 36 23 18 M9 36 V43 M2 43 H16" fill="none" stroke="#35D9FF" stroke-width="2.2" stroke-linecap="round"/><path d="M4 12 H14 M4 18 H14" stroke="#738BFF" stroke-width="1.4"/><text x="35" y="25" class="muted">voice on</text></g>
  <g transform="translate(778 451)" opacity=".72" filter="url(#soft-sketch)"><path d="M0 19 Q17 1 34 19 Q17 37 0 19Z" fill="none" stroke="#C968FF" stroke-width="2.1"/><circle cx="17" cy="19" r="6" fill="url(#eye)"/><path d="M45 8 L49 14 L56 16 L50 21 L50 28 L44 24 L37 27 L39 20 L35 15 L42 14Z" fill="#FFE17A"/></g>
</svg>`;
}

function niceMaximum(value: number) {
  if (value <= 5) return 5;
  if (value <= 10) return 10;
  if (value <= 20) return Math.ceil(value / 5) * 5;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  const fraction = value / magnitude;
  const step = magnitude * (fraction <= 1.25 ? 0.25 : 0.5);
  return Math.ceil(value / step) * step;
}

function ticks(start: number, end: number, count: number) {
  return Array.from({ length: count }, (_, index) => start + ((end - start) / (count - 1)) * index);
}

function numberTicks(maximum: number, count: number) {
  return Array.from({ length: count }, (_, index) => Math.round((maximum / (count - 1)) * index));
}

function smoothPath(points: ReadonlyArray<readonly [number, number]>) {
  return points.reduce((path, [x, y], index) => {
    if (index === 0) return `M${x.toFixed(2)} ${y.toFixed(2)}`;
    const [previousX, previousY] = points[index - 1];
    const controlX = (previousX + x) / 2;
    return `${path} C${controlX.toFixed(2)} ${previousY.toFixed(2)} ${controlX.toFixed(2)} ${y.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)}`;
  }, "");
}

function svgResponse(svg: string, status: number, cacheSeconds: number) {
  return new Response(svg, {
    status,
    headers: {
      "Cache-Control": `public, max-age=3600, s-maxage=${cacheSeconds}, stale-if-error=86400`,
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
      "Content-Type": "image/svg+xml; charset=utf-8",
      "Cross-Origin-Resource-Policy": "cross-origin",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function renderError(themeName: ThemeName) {
  const theme = themes[themeName];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="960" height="180" viewBox="0 0 960 180" role="img" aria-label="Star history is temporarily unavailable"><rect x=".5" y=".5" width="959" height="179" rx="18" fill="${theme.background}" stroke="${theme.border}"/><text x="48" y="80" fill="${theme.text}" font-family="ui-sans-serif,-apple-system,sans-serif" font-size="24" font-weight="700">Companion signal is refreshing</text><text x="48" y="118" fill="${theme.muted}" font-family="ui-sans-serif,-apple-system,sans-serif" font-size="17">The cached star history will return shortly.</text></svg>`;
}
