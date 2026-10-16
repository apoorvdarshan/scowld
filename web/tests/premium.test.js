import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  CONTEXT_TOKENS,
  LIVE_MODEL,
  PRODUCTS,
  REVENUECAT_PRODUCTS,
  VOICES,
  allowance,
  balance,
  debit,
  isValidUserID,
  premiumSetup,
  summary,
  usageKeys,
} from "../src/premium.js";
import { MeteredRelay, notice } from "../src/relay.js";

const DAY = 24 * 60 * 60 * 1000;
const now = Date.parse("2026-10-16T12:00:00Z");
const iso = (ms) => new Date(ms).toISOString();

// RevenueCat API v2 subscription and purchase items.
const YEARLY = "prod99628106a0";
const WEEKLY = "prod8d789d474c";
function subscription(product, start, end, extra = {}) {
  return {
    id: `sub_${product}`,
    product_id: product,
    status: "active",
    gives_access: true,
    current_period_starts_at: start,
    current_period_ends_at: end,
    store_subscription_identifier: "2000000111",
    ...extra,
  };
}

describe("premium allowance", () => {
  it("accepts only RevenueCat anonymous IDs", () => {
    expect(isValidUserID("$RCAnonymousID:0123456789abcdef0123456789abcdef")).toBe(true);
    expect(isValidUserID("$RCAnonymousID:0123")).toBe(false);
    expect(isValidUserID("someone@example.com")).toBe(false);
    expect(isValidUserID(undefined)).toBe(false);
  });

  it("maps RevenueCat's product IDs to the App Store products", () => {
    expect(REVENUECAT_PRODUCTS[YEARLY]).toBe(PRODUCTS.yearly);
    expect(REVENUECAT_PRODUCTS[WEEKLY]).toBe(PRODUCTS.weekly);
  });

  it("gives a weekly subscriber 20 minutes for the current week", () => {
    const result = allowance({ subscriptions: [subscription(WEEKLY, now - 2 * DAY, now + 5 * DAY)] }, now);
    expect(result.plan).toEqual({
      kind: "weekly",
      key: `weekly:2000000111:${now - 2 * DAY}`,
      minutes: 20,
      endsAt: now + 5 * DAY,
    });
    expect(result.packs).toEqual([]);
  });

  it("gives the yearly free trial 10 minutes and a paid year 50 minutes a month", () => {
    const trial = allowance({ subscriptions: [subscription(YEARLY, now - DAY, now + 2 * DAY, { status: "trialing" })] }, now);
    expect(trial.plan).toMatchObject({ kind: "trial", key: "trial:2000000111", minutes: 10 });

    const start = now - 40 * DAY;
    const year = allowance({ subscriptions: [subscription(YEARLY, start, start + 365 * DAY)] }, now);
    expect(year.plan).toMatchObject({ kind: "yearly", minutes: 50, key: `yearly:2000000111:${start}:1` });
    // The second month of the year renews about 61 days after the purchase.
    expect(Math.round((year.plan.endsAt - start) / DAY)).toBe(61);
  });

  it("prefers the yearly plan and ignores expired, inactive and future subscriptions", () => {
    const both = allowance({ subscriptions: [
      subscription(WEEKLY, now - DAY, now + 6 * DAY),
      subscription(YEARLY, now - DAY, now + 300 * DAY),
    ] }, now);
    expect(both.plan.kind).toBe("yearly");

    const none = allowance({ subscriptions: [
      subscription(WEEKLY, now - 8 * DAY, now - DAY),
      subscription(YEARLY, now - DAY, now + 300 * DAY, { gives_access: false }),
      subscription(WEEKLY, now - DAY, now + 6 * DAY, { status: "expired" }),
      subscription(WEEKLY, now + DAY, now + 8 * DAY),
      subscription("prod_unknown", now - DAY, now + 8 * DAY),
    ] }, now);
    expect(none.plan).toBeNull();
    expect(allowance(undefined, now)).toEqual({ plan: null, packs: [] });
  });

  it("lists every minute pack by its App Store transaction, oldest first", () => {
    const result = allowance({ purchases: [
      { id: "p3", product_id: "prod813c87edce", store_purchase_identifier: "t3", purchased_at: now - DAY, status: "owned" },
      { id: "p1", product_id: "prod4362784d98", store_purchase_identifier: "t1", purchased_at: now - 9 * DAY, status: "owned" },
      { id: "p2", product_id: "prod4362784d98", purchased_at: now - 5 * DAY, quantity: 2 },
      { id: "p4", product_id: "prod5f8bbc1eb2", store_purchase_identifier: "t4", purchased_at: now - 2 * DAY, status: "refunded" },
      { id: "tip", product_id: "prodbeab70dcd3", purchased_at: now - DAY },
    ] }, now);
    expect(result.packs.map(({ key, minutes }) => ({ key, minutes }))).toEqual([
      { key: "pack:t1", minutes: 20 },
      { key: "pack:p2", minutes: 40 },
      { key: "pack:t3", minutes: 150 },
    ]);
  });

  it("spends plan minutes first, then the oldest pack", () => {
    const allowed = {
      plan: { kind: "weekly", key: "weekly:x", minutes: 20, endsAt: now + DAY },
      packs: [{ key: "pack:a", minutes: 20 }, { key: "pack:b", minutes: 60 }],
    };
    expect(usageKeys(allowed)).toEqual(["weekly:x", "pack:a", "pack:b"]);
    let usage = {};
    expect(balance(usage, allowed)).toEqual({ planSeconds: 1200, packSeconds: 4800, totalSeconds: 6000 });

    let result = debit(usage, allowed, 1000);
    expect(result.increments).toEqual({ "weekly:x": 1000 });
    result = debit(result.usage, allowed, 500);
    expect(result.increments).toEqual({ "weekly:x": 200, "pack:a": 300 });
    usage = result.usage;
    expect(balance(usage, allowed)).toEqual({ planSeconds: 0, packSeconds: 4500, totalSeconds: 4500 });

    // A new week brings the plan minutes back; what was used of a pack stays used.
    const nextWeek = { ...allowed, plan: { ...allowed.plan, key: "weekly:y" } };
    expect(balance(usage, nextWeek)).toMatchObject({ planSeconds: 1200, packSeconds: 4500 });
  });

  it("charges time past the last minute to the plan so none is lost", () => {
    const allowed = { plan: { key: "trial:x", minutes: 10 }, packs: [] };
    const { usage, increments } = debit({ "trial:x": 590 }, allowed, 25);
    expect(increments).toEqual({ "trial:x": 25 });
    expect(balance(usage, allowed).totalSeconds).toBe(0);
    expect(debit({}, { plan: null, packs: [] }, 5).increments).toEqual({});
  });

  it("summarizes minutes left for the app", () => {
    const allowed = { plan: { kind: "yearly", key: "k", minutes: 50, endsAt: now + DAY }, packs: [{ key: "p", minutes: 20 }] };
    expect(summary({ k: 600, p: 60 }, allowed)).toEqual({
      plan: "yearly",
      planMinutes: 50,
      planSecondsLeft: 2400,
      planRenewsAt: iso(now + DAY),
      packSecondsLeft: 1140,
    });
    expect(summary({}, { plan: null, packs: [] })).toMatchObject({ plan: null, planSecondsLeft: 0, planRenewsAt: null });
  });
});

describe("premium setup", () => {
  it("fixes the model, the context limit and the voice list", () => {
    const setup = premiumSetup({
      model: "models/gemini-ultra-expensive",
      generationConfig: { speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Aoede" } } }, temperature: 2 },
      systemInstruction: { parts: [{ text: "You are Bella." }] },
      tools: [{ googleSearch: {} }],
      contextWindowCompression: { slidingWindow: {} },
      sessionResumption: { handle: "resume-1" },
    });
    expect(setup.model).toBe(LIVE_MODEL);
    expect(setup.tools).toBeUndefined();
    expect(setup.generationConfig).toEqual({
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Aoede" } } },
    });
    expect(setup.systemInstruction.parts[0].text).toBe("You are Bella.");
    expect(setup.contextWindowCompression).toEqual({
      triggerTokens: String(CONTEXT_TOKENS.trigger),
      slidingWindow: { targetTokens: String(CONTEXT_TOKENS.target) },
    });
    expect(setup.sessionResumption).toEqual({ handle: "resume-1" });
  });

  it("falls back to Leda for a voice Premium doesn't offer and caps the instructions", () => {
    const setup = premiumSetup({
      generationConfig: { speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Puck" } } } },
      systemInstruction: { parts: [{ text: "x".repeat(100_000) }] },
    });
    expect(setup.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName).toBe(VOICES[0]);
    expect(setup.systemInstruction.parts[0].text.length).toBe(24_000);
    expect(setup.sessionResumption).toEqual({});
    expect(premiumSetup(undefined).model).toBe(LIVE_MODEL);
  });
});

describe("metered relay", () => {
  let clock;
  let toClient;
  let toUpstream;
  let closeBoth;
  let secondsLeft;
  let talked;

  function makeRelay() {
    return new MeteredRelay({
      toClient,
      toUpstream,
      close: closeBoth,
      onTalked: (seconds) => {
        talked += seconds;
        secondsLeft -= seconds;
        return secondsLeft;
      },
      now: () => clock,
      tickMs: 5000,
    });
  }

  beforeEach(() => {
    vi.useFakeTimers();
    clock = 0;
    toClient = vi.fn();
    toUpstream = vi.fn();
    closeBoth = vi.fn();
    secondsLeft = 60;
    talked = 0;
  });
  afterEach(() => vi.useRealTimers());

  const sent = () => toUpstream.mock.calls.map(([data]) => JSON.parse(data));

  it("sends the premium setup once and only realtime input after it", () => {
    const relay = makeRelay();
    relay.clientMessage(JSON.stringify({ realtimeInput: { audio: { data: "early" } } }));
    relay.clientMessage(JSON.stringify({ setup: { model: "x" } }));
    relay.clientMessage(JSON.stringify({ setup: { model: "y" } }));
    relay.clientMessage(JSON.stringify({ realtimeInput: { audio: { data: "a" }, extra: 1 } }));
    relay.clientMessage(JSON.stringify({ toolResponse: {} }));
    relay.clientMessage("not json");
    expect(sent()).toEqual([
      { setup: premiumSetup({ model: "x" }) },
      { realtimeInput: { audio: { data: "a" } } },
    ]);
  });

  it("passes at most one camera frame every two seconds", () => {
    const relay = makeRelay();
    relay.clientMessage(JSON.stringify({ setup: {} }));
    const frame = JSON.stringify({ realtimeInput: { video: { data: "jpg" } } });
    relay.clientMessage(frame);
    clock = 1000;
    relay.clientMessage(frame);
    clock = 2100;
    relay.clientMessage(frame);
    expect(sent().filter((m) => m.realtimeInput?.video)).toHaveLength(2);
  });

  it("meters from setupComplete and ends the conversation when the minutes run out", () => {
    const relay = makeRelay();
    relay.clientMessage(JSON.stringify({ setup: {} }));
    clock = 3000;
    relay.upstreamMessage(JSON.stringify({ setupComplete: {} }));
    expect(toClient).toHaveBeenCalledWith(JSON.stringify({ setupComplete: {} }));

    for (let i = 0; i < 11; i++) {
      clock += 5000;
      vi.advanceTimersByTime(5000);
    }
    expect(talked).toBe(55);
    expect(closeBoth).not.toHaveBeenCalled();

    clock += 5000;
    vi.advanceTimersByTime(5000);
    expect(toClient).toHaveBeenLastCalledWith(notice("out_of_minutes"));
    expect(closeBoth).toHaveBeenCalledWith(4002, "Out of minutes");

    // Nothing passes after the end, and the timer stops.
    relay.clientMessage(JSON.stringify({ realtimeInput: { audio: {} } }));
    clock += 5000;
    vi.advanceTimersByTime(5000);
    expect(talked).toBe(60);
  });

  it("records the last partial interval when the conversation ends", () => {
    const relay = makeRelay();
    relay.upstreamMessage(JSON.stringify({ setupComplete: {} }));
    clock = 7500;
    vi.advanceTimersByTime(5000);
    relay.end();
    relay.end();
    expect(talked).toBe(7.5);
    expect(closeBoth).not.toHaveBeenCalled();
  });

  it("forwards binary frames and counts reported tokens", () => {
    const relay = makeRelay();
    const frame = new TextEncoder().encode(JSON.stringify({ usageMetadata: { promptTokenCount: 10, responseTokenCount: 4, thoughtsTokenCount: 2 } }));
    relay.upstreamMessage(frame.buffer);
    expect(toClient).toHaveBeenCalledWith(frame.buffer);
    expect(relay.tokens).toEqual({ prompt: 10, response: 4, thoughts: 2 });
    expect(talked).toBe(0);
  });
});
