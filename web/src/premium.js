// Scowld Premium: talk without your own API key. The app's subscription and
// minute packs are App Store purchases tracked by RevenueCat; this file holds
// the rules for what they allow. It has no I/O so it can be tested directly.

export const PRODUCTS = {
  weekly: "com.apoorvdarshan.Scowld.premium.weekly",
  yearly: "com.apoorvdarshan.Scowld.premium.yearly",
};

/** Scowld's RevenueCat project, and its product IDs for the App Store products. */
export const REVENUECAT_PROJECT = "projd94ef4c3";
export const REVENUECAT_PRODUCTS = {
  prod99628106a0: "com.apoorvdarshan.Scowld.premium.yearly",
  prod8d789d474c: "com.apoorvdarshan.Scowld.premium.weekly",
  prod4362784d98: "com.apoorvdarshan.Scowld.minutes.20",
  prod5f8bbc1eb2: "com.apoorvdarshan.Scowld.minutes.60",
  prod813c87edce: "com.apoorvdarshan.Scowld.minutes.150",
};

/** Minute packs (consumables) and how many minutes each adds. They never expire. */
export const MINUTE_PACKS = {
  "com.apoorvdarshan.Scowld.minutes.20": 20,
  "com.apoorvdarshan.Scowld.minutes.60": 60,
  "com.apoorvdarshan.Scowld.minutes.150": 150,
};

/**
 * Minutes included with each plan: weekly per week, yearly per month of the
 * subscription year, and the yearly plan's free trial for the whole trial.
 */
export const PLAN_MINUTES = { weekly: 20, yearly: 50, trial: 10 };

const MONTH_MS = (365.25 / 12) * 24 * 60 * 60 * 1000;

/** Premium conversations always use this model. */
export const LIVE_MODEL = "models/gemini-3.8-live";

/** The female Gemini voices the app offers (AIProvider.gemini.voices). */
export const VOICES = [
  "Leda", "Aoede", "Zephyr", "Achernar", "Vindemiatrix", "Sulafat", "Laomedeia",
  "Kore", "Callirrhoe", "Despina", "Autonoe", "Erinome", "Pulcherrima", "Gacrux",
];

/**
 * Gemini bills the whole conversation again on every turn, so the context is
 * kept small: past this many tokens the oldest turns are dropped down to the
 * target. Measured cost stays near $0.08 a minute instead of growing.
 */
export const CONTEXT_TOKENS = { trigger: 8000, target: 4000 };

/** At most one camera frame this often (Gemini keeps only the latest one anyway). */
export const FRAME_INTERVAL_MS = 2000;

/** Longest system instruction accepted (characters). */
export const MAX_INSTRUCTIONS = 24000;

/** RevenueCat's anonymous app user IDs, the only IDs the app uses. */
export function isValidUserID(id) {
  return typeof id === "string" && /^\$RCAnonymousID:[0-9a-f]{32}$/.test(id);
}

/**
 * What a RevenueCat customer's purchases allow at `now` (milliseconds): the
 * current plan period, if any, and each minute pack bought. `customer` holds
 * RevenueCat API v2 `subscriptions` and `purchases` lists. Usage is counted per
 * App Store purchase (the subscription's original transaction and each pack's
 * transaction), not per app install, so reinstalling the app and restoring
 * purchases can't reset it.
 */
export function allowance(customer, now) {
  const storeID = (item) => REVENUECAT_PRODUCTS[item?.product_id] ?? item?.product_id;
  const active = (sub) =>
    sub.gives_access !== false &&
    sub.status !== "expired" &&
    typeof sub.current_period_starts_at === "number" &&
    typeof sub.current_period_ends_at === "number" &&
    sub.current_period_starts_at <= now &&
    sub.current_period_ends_at > now;
  const subscriptions = (customer?.subscriptions ?? []).filter(active);
  const yearly = subscriptions.find((sub) => storeID(sub) === PRODUCTS.yearly);
  const weekly = subscriptions.find((sub) => storeID(sub) === PRODUCTS.weekly);

  let plan = null;
  if (yearly) {
    const chain = yearly.store_subscription_identifier ?? yearly.id;
    if (yearly.status === "trialing") {
      plan = { kind: "trial", key: `trial:${chain}`, minutes: PLAN_MINUTES.trial, endsAt: yearly.current_period_ends_at };
    } else {
      const periodStart = yearly.current_period_starts_at;
      const month = Math.floor((now - periodStart) / MONTH_MS);
      const start = periodStart + month * MONTH_MS;
      plan = {
        kind: "yearly",
        key: `yearly:${chain}:${periodStart}:${month}`,
        minutes: PLAN_MINUTES.yearly,
        endsAt: Math.min(start + MONTH_MS, yearly.current_period_ends_at),
      };
    }
  } else if (weekly) {
    const chain = weekly.store_subscription_identifier ?? weekly.id;
    plan = {
      kind: "weekly",
      key: `weekly:${chain}:${weekly.current_period_starts_at}`,
      minutes: PLAN_MINUTES.weekly,
      endsAt: weekly.current_period_ends_at,
    };
  }

  const packs = [];
  for (const purchase of customer?.purchases ?? []) {
    const minutes = MINUTE_PACKS[storeID(purchase)];
    if (!minutes || purchase.status === "refunded") continue;
    packs.push({
      key: `pack:${purchase.store_purchase_identifier ?? purchase.id}`,
      minutes: minutes * Math.max(1, purchase.quantity ?? 1),
      purchasedAt: purchase.purchased_at ?? 0,
    });
  }
  // The oldest pack is used first.
  packs.sort((a, b) => a.purchasedAt - b.purchasedAt);

  return { plan, packs };
}

/** The usage records an allowance needs. */
export function usageKeys(allowance) {
  return [...(allowance.plan ? [allowance.plan.key] : []), ...allowance.packs.map((pack) => pack.key)];
}

const left = (minutes, used) => Math.max(0, minutes * 60 - (used ?? 0));

/** Seconds of talking left, from the plan first and then from minute packs. */
export function balance(usage, allowance) {
  const planSeconds = allowance.plan ? left(allowance.plan.minutes, usage[allowance.plan.key]) : 0;
  const packSeconds = allowance.packs.reduce((sum, pack) => sum + left(pack.minutes, usage[pack.key]), 0);
  return { planSeconds, packSeconds, totalSeconds: planSeconds + packSeconds };
}

/**
 * Records `seconds` of talking: from the plan first, then the oldest packs.
 * Returns the new usage and the seconds added to each record. Time beyond
 * everything left is charged to the plan (or the last pack) so it isn't lost.
 */
export function debit(usage, allowance, seconds) {
  const next = { ...usage };
  const increments = {};
  let remaining = seconds;
  const take = (key, available) => {
    const amount = Math.min(available, remaining);
    if (amount <= 0) return;
    next[key] = (next[key] ?? 0) + amount;
    increments[key] = (increments[key] ?? 0) + amount;
    remaining -= amount;
  };
  if (allowance.plan) take(allowance.plan.key, left(allowance.plan.minutes, next[allowance.plan.key]));
  for (const pack of allowance.packs) take(pack.key, left(pack.minutes, next[pack.key]));
  const overflow = allowance.plan?.key ?? allowance.packs.at(-1)?.key;
  if (remaining > 0 && overflow) take(overflow, Infinity);
  return { usage: next, increments };
}

/** What the app shows: minutes left and when the plan's minutes renew. */
export function summary(usage, allowance) {
  const { planSeconds, packSeconds } = balance(usage, allowance);
  return {
    plan: allowance.plan?.kind ?? null,
    planMinutes: allowance.plan?.minutes ?? 0,
    planSecondsLeft: Math.floor(planSeconds),
    planRenewsAt: allowance.plan ? new Date(allowance.plan.endsAt).toISOString() : null,
    packSecondsLeft: Math.floor(packSeconds),
  };
}

/**
 * The setup Gemini receives for a Premium conversation. Only the voice, the
 * instructions and a resumption handle come from the app; the model, the
 * context limit and everything else are fixed here so a client can't run up
 * the bill.
 */
export function premiumSetup(setup) {
  const voice = setup?.generationConfig?.speechConfig?.voiceConfig?.prebuiltVoiceConfig?.voiceName;
  const instructions = (setup?.systemInstruction?.parts ?? [])
    .map((part) => (typeof part?.text === "string" ? part.text : ""))
    .join("\n")
    .slice(0, MAX_INSTRUCTIONS);
  const handle = setup?.sessionResumption?.handle;
  return {
    model: LIVE_MODEL,
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICES.includes(voice) ? voice : VOICES[0] } } },
    },
    systemInstruction: { parts: [{ text: instructions }] },
    inputAudioTranscription: {},
    outputAudioTranscription: {},
    contextWindowCompression: {
      triggerTokens: String(CONTEXT_TOKENS.trigger),
      slidingWindow: { targetTokens: String(CONTEXT_TOKENS.target) },
    },
    sessionResumption: typeof handle === "string" && handle.length < 4096 ? { handle } : {},
  };
}
