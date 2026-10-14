import { getCloudflareContext } from "@opennextjs/cloudflare";
import {
  OWNER,
  parseStargazerPage,
  renderError,
  renderStarHistory,
  REPOSITORY,
  type ThemeName,
} from "@/lib/star-history";

export const runtime = "nodejs";

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

    const { starredAt, pageSize } = parseStargazerPage(await response.json());
    stars.push(...starredAt);

    if (pageSize < 100) break;
    if (page === 100) throw new Error("Star history exceeded the pagination limit");
  }

  return stars.sort((left, right) => left.localeCompare(right));
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
