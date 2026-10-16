// One Durable Object for every Premium purchase's usage: seconds talked per
// plan period and per minute pack, keyed by App Store purchase rather than by
// app install (see allowance() in premium.js). PremiumAccount objects read and
// add to it over RPC.
import { DurableObject } from "cloudflare:workers";

const BATCH = 128; // storage.get/put accept at most 128 keys at a time

function chunks(items) {
  const result = [];
  for (let i = 0; i < items.length; i += BATCH) result.push(items.slice(i, i + BATCH));
  return result;
}

export class PremiumLedger extends DurableObject {
  /** Seconds used for each key (0 when there is no record yet). */
  async usage(keys) {
    const result = {};
    for (const batch of chunks(keys)) {
      const stored = await this.ctx.storage.get(batch);
      for (const key of batch) result[key] = stored.get(key) ?? 0;
    }
    return result;
  }

  /** Adds seconds to each key. */
  async add(increments) {
    const keys = Object.keys(increments);
    for (const batch of chunks(keys)) {
      const stored = await this.ctx.storage.get(batch);
      const next = {};
      for (const key of batch) next[key] = (stored.get(key) ?? 0) + increments[key];
      await this.ctx.storage.put(next);
    }
  }
}
