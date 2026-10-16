// One Durable Object per Premium user (keyed by their RevenueCat app user ID).
// It checks their purchases and relays at most one conversation at a time to
// Gemini Live with Scowld's key, which never leaves the server. Minutes used
// are kept per purchase in the PremiumLedger.
import { REVENUECAT_PROJECT, allowance, balance, debit, summary, usageKeys } from "./premium.js";
import { MeteredRelay, notice } from "./relay.js";

const GEMINI_LIVE_URL =
  "https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent";

export class PremiumAccount {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.relay = null;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const userID = request.headers.get("X-Scowld-User");
    if (!this.env.REVENUECAT_SECRET_KEY || !this.env.GEMINI_API_KEY) {
      return unavailable(url);
    }

    let customer;
    try {
      // REVENUECAT_API_BASE is only set for local end-to-end tests.
      customer = await fetchCustomer(userID, this.env.REVENUECAT_SECRET_KEY, this.env.REVENUECAT_API_BASE);
    } catch (error) {
      console.error("RevenueCat lookup failed:", error.message);
      return unavailable(url);
    }
    const allowed = allowance(customer, Date.now());
    const ledger = this.env.PREMIUM_LEDGER.get(this.env.PREMIUM_LEDGER.idFromName("ledger"));
    let usage;
    try {
      usage = await ledger.usage(usageKeys(allowed));
    } catch (error) {
      console.error("Ledger read failed:", error.message);
      return unavailable(url);
    }

    if (url.pathname === "/api/premium/balance") {
      return json(summary(usage, allowed));
    }
    return this.live(allowed, usage, ledger);
  }

  async live(allowed, usage, ledger) {
    const [client, server] = Object.values(new WebSocketPair());
    server.accept();
    const opened = new Response(null, { status: 101, webSocket: client });

    if (balance(usage, allowed).totalSeconds <= 0) {
      server.send(notice("out_of_minutes"));
      server.close(4002, "Out of minutes");
      return opened;
    }

    // One conversation at a time: a new one replaces the old.
    this.relay?.close(4003, "Replaced by a new conversation");

    let upstream;
    try {
      const response = await fetch(GEMINI_LIVE_URL, {
        headers: { Upgrade: "websocket", "x-goog-api-key": this.env.GEMINI_API_KEY },
      });
      upstream = response.webSocket;
      if (!upstream) throw new Error(`Gemini returned HTTP ${response.status}`);
      upstream.accept();
    } catch (error) {
      console.error("Gemini connection failed:", error.message);
      server.send(notice("unavailable"));
      server.close(1011, "Premium is unavailable right now");
      return opened;
    }

    // Binary messages (Gemini sends its JSON as binary frames) must arrive as
    // ArrayBuffers: with this compatibility date the default is Blob, which
    // can't be passed on with send().
    server.binaryType = "arraybuffer";
    upstream.binaryType = "arraybuffer";

    let current = usage;
    const relay = new MeteredRelay({
      toClient: (data) => send(server, data),
      toUpstream: (data) => send(upstream, data),
      close: (code, reason) => {
        close(server, code, reason);
        close(upstream, 1000, "Closed");
      },
      onTalked: (seconds) => {
        const { usage: next, increments } = debit(current, allowed, seconds);
        current = next;
        if (Object.keys(increments).length > 0) {
          this.ctx.waitUntil(ledger.add(increments).catch((error) => console.error("Ledger write failed:", error.message)));
        }
        return balance(current, allowed).totalSeconds;
      },
    });
    this.relay = relay;

    server.addEventListener("message", (event) => relay.clientMessage(event.data));
    upstream.addEventListener("message", (event) => relay.upstreamMessage(event.data));
    const finish = (other, code, reason) => {
      relay.end();
      close(other, code, reason);
      if (this.relay === relay) this.relay = null;
    };
    server.addEventListener("close", () => finish(upstream, 1000, "Closed"));
    server.addEventListener("error", () => finish(upstream, 1011, "Client error"));
    // Gemini's close reason (a quota or a bad request) reaches the app as is.
    upstream.addEventListener("close", (event) => finish(server, closeCode(event.code), event.reason ?? ""));
    upstream.addEventListener("error", () => finish(server, 1011, "Gemini connection error"));
    return opened;
  }
}

/** The customer's subscriptions and one-time purchases (RevenueCat API v2). */
async function fetchCustomer(userID, secretKey, apiBase = "https://api.revenuecat.com") {
  const base = `${apiBase}/v2/projects/${REVENUECAT_PROJECT}/customers/${encodeURIComponent(userID)}`;
  const [subscriptions, purchases] = await Promise.all([
    list(`${base}/subscriptions?limit=100`, secretKey),
    list(`${base}/purchases?limit=100`, secretKey),
  ]);
  return { subscriptions, purchases };
}

async function list(url, secretKey) {
  const items = [];
  let next = url;
  for (let page = 0; next && page < 10; page++) {
    const response = await fetch(next, { headers: { Authorization: `Bearer ${secretKey}` } });
    // A customer RevenueCat hasn't seen yet has bought nothing.
    if (response.status === 404) return items;
    if (!response.ok) throw new Error(`RevenueCat returned HTTP ${response.status}`);
    const body = await response.json();
    items.push(...(body.items ?? []));
    next = body.next_page ? new URL(body.next_page, url).href : null;
  }
  return items;
}

function send(socket, data) {
  try {
    socket.send(data);
  } catch {
    // Already closed; the close handler finishes the conversation.
  }
}

function close(socket, code, reason) {
  try {
    socket.close(code, reason.slice(0, 120));
  } catch {
    // Already closed.
  }
}

/** Close codes 1005, 1006 and 1015 can't be sent; report them as a normal close. */
function closeCode(code) {
  return code >= 1000 && code <= 4999 && ![1005, 1006, 1015].includes(code) ? code : 1000;
}

function unavailable(url) {
  if (url.pathname === "/api/premium/balance") return json({ error: "unavailable" }, 503);
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.send(notice("unavailable"));
  server.close(1011, "Premium is unavailable right now");
  return new Response(null, { status: 101, webSocket: client });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
