// scowld.xyz runs on Cloudflare Workers. Static files in public/ are served
// straight from the assets binding; only /api/* reaches this Worker (see
// run_worker_first in wrangler.jsonc).
import { isValidUserID } from "./premium.js";
import {
  OWNER,
  parseStargazerPage,
  renderError,
  renderStarHistory,
  REPOSITORY,
} from "./star-history.js";

export { PremiumAccount } from "./premium-account.js";
export { PremiumLedger } from "./premium-ledger.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/star-history.svg") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
      }
      const response = await starHistory(url, env);
      return request.method === "HEAD"
        ? new Response(null, { status: response.status, headers: response.headers })
        : response;
    }

    if (url.pathname === "/api/live" || url.pathname === "/api/premium/balance") {
      return premium(request, env, url);
    }

    return env.ASSETS.fetch(request);
  },
};

// Scowld Premium: the app identifies itself with its RevenueCat app user ID,
// and each ID has its own Durable Object that checks its purchases with
// RevenueCat, keeps its minute usage and relays its conversations.
async function premium(request, env, url) {
  const userID = request.headers.get("X-Scowld-User") ?? "";
  if (!isValidUserID(userID)) {
    return new Response("Unknown user", { status: 400 });
  }
  if (url.pathname === "/api/live") {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade", { status: 426, headers: { Upgrade: "websocket" } });
    }
  } else if (request.method !== "GET") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  }
  const accounts = env.PREMIUM_ACCOUNTS;
  return accounts.get(accounts.idFromName(userID)).fetch(request);
}

// The README embeds this chart, so failures render a designed fallback card
// with a short cache instead of an error page.
async function starHistory(url, env) {
  const themeName = url.searchParams.get("theme") === "dark" ? "dark" : "light";

  try {
    if (!env.GITHUB_TOKEN) {
      throw new Error("GITHUB_TOKEN is not configured");
    }
    const stars = await fetchStarHistory(env.GITHUB_TOKEN);
    return svgResponse(renderStarHistory(stars, themeName), 200, 21_600);
  } catch (error) {
    console.error("Unable to render Scowld star history", error);
    return svgResponse(renderError(themeName), 503, 60);
  }
}

async function fetchStarHistory(token) {
  const stars = [];

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

function svgResponse(svg, status, cacheSeconds) {
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
