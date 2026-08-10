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
  const plot = { left: 76, top: 144, right: 904, bottom: 424 };
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

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
  <title id="title">Scowld GitHub star history</title>
  <desc id="description">${stars.length} GitHub stars over time for ${OWNER}/${REPOSITORY}.</desc>
  <defs>
    <linearGradient id="voice-line" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#35D9FF"/><stop offset="0.5" stop-color="#738BFF"/><stop offset="1" stop-color="#C968FF"/></linearGradient>
    <linearGradient id="voice-area" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#738BFF" stop-opacity="0.27"/><stop offset="1" stop-color="#C968FF" stop-opacity="0"/></linearGradient>
    <radialGradient id="aura" cx="17%" cy="2%" r="68%"><stop stop-color="#35D9FF" stop-opacity="${themeName === "dark" ? "0.12" : "0.07"}"/><stop offset="1" stop-color="#738BFF" stop-opacity="0"/></radialGradient>
    <clipPath id="plot"><rect x="${plot.left}" y="${plot.top - 10}" width="${plot.right - plot.left}" height="${plot.bottom - plot.top + 10}"/></clipPath>
    <style>.axis{fill:${theme.muted};font:500 13px ui-sans-serif,-apple-system,sans-serif}.grid{stroke:${theme.grid};stroke-width:1;stroke-dasharray:2 8;stroke-linecap:round}.title{fill:${theme.text};font:700 17px ui-sans-serif,-apple-system,sans-serif}.muted{fill:${theme.muted};font:500 13px ui-sans-serif,-apple-system,sans-serif}.mono{fill:${theme.muted};font:650 11px ui-monospace,SFMono-Regular,monospace;letter-spacing:1.5px}</style>
  </defs>
  <rect x="0.5" y="0.5" width="959" height="519" rx="24" fill="${theme.background}" stroke="${theme.border}"/>
  <rect x="1" y="1" width="958" height="518" rx="23" fill="url(#aura)"/>
  <g transform="translate(42 30)">
    <rect width="54" height="54" rx="18" fill="${theme.panel}" stroke="${theme.border}"/>
    <circle cx="27" cy="27" r="13" fill="none" stroke="#738BFF" stroke-width="2" opacity=".55"/>
    <path d="M13 28h5l3-9 5 18 4-14 3 7h8" fill="none" stroke="url(#voice-line)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <text x="114" y="50" class="title">Scowld / companion signal</text>
  <text x="114" y="73" class="muted">Stars gathered while Bella listens</text>
  <text x="${plot.right}" y="42" text-anchor="end" class="mono">SIGNAL STRENGTH</text>
  <text x="${plot.right}" y="78" text-anchor="end" fill="${theme.text}" font-family="ui-sans-serif,-apple-system,sans-serif" font-size="34" font-weight="740">${stars.length}<tspan dx="9" fill="${theme.muted}" font-size="14" font-weight="600">STARS</tspan></text>
  <line x1="${plot.left}" y1="112" x2="${plot.right}" y2="112" stroke="${theme.border}"/>
  ${yGrid}${dateLabels}
  <g clip-path="url(#plot)"><path d="${area}" fill="url(#voice-area)"/><path d="${path}" fill="none" stroke="url(#voice-line)" stroke-width="4.5" stroke-linecap="round"/></g>
  <circle cx="${plot.right}" cy="${currentY}" r="13" fill="#C968FF" opacity=".13"/><circle cx="${plot.right}" cy="${currentY}" r="6.5" fill="#C968FF" stroke="${theme.background}" stroke-width="3"/>
  <line x1="${plot.left}" y1="${plot.bottom}" x2="${plot.right}" y2="${plot.bottom}" stroke="${theme.border}"/>
</svg>`;
}

function niceMaximum(value: number) {
  if (value <= 5) return 5;
  const exponent = 10 ** Math.floor(Math.log10(value));
  const fraction = value / exponent;
  return ([1, 1.25, 2, 2.5, 5, 10].find((candidate) => candidate >= fraction) ?? 10) * exponent;
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
