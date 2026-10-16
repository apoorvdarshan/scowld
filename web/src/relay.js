// Relays one Premium conversation between the app and Gemini Live, metering
// the time and holding the client to what Premium allows. Sockets, storage
// and the clock are passed in, so this runs (and is tested) outside Workers.
import { FRAME_INTERVAL_MS, premiumSetup } from "./premium.js";

/** A control message Scowld adds to the stream; the app reads `scowld.event`. */
export function notice(event) {
  return JSON.stringify({ scowld: { event } });
}

const INPUT_FIELDS = ["audio", "video", "text", "audioStreamEnd", "activityStart", "activityEnd"];
const decoder = new TextDecoder();

function parse(data) {
  try {
    return JSON.parse(typeof data === "string" ? data : decoder.decode(data));
  } catch {
    return null;
  }
}

export class MeteredRelay {
  /**
   * @param {object} options
   * @param {(data: string | ArrayBuffer) => void} options.toClient
   * @param {(data: string) => void} options.toUpstream
   * @param {(code: number, reason: string) => void} options.close closes both sides
   * @param {(seconds: number) => number} options.onTalked records talk time, returns seconds left
   * @param {() => number} [options.now] milliseconds
   * @param {number} [options.tickMs] how often time is recorded
   */
  constructor({ toClient, toUpstream, close, onTalked, now = Date.now, tickMs = 5000 }) {
    this.toClient = toClient;
    this.toUpstream = toUpstream;
    this.closeBoth = close;
    this.onTalked = onTalked;
    this.now = now;
    this.tickMs = tickMs;
    this.setupSent = false;
    this.lastFrameAt = -Infinity;
    this.lastTick = null;
    this.timer = null;
    this.ended = false;
    this.tokens = { prompt: 0, response: 0, thoughts: 0 };
  }

  /** A message from the app. Only a setup and realtime input are passed on. */
  clientMessage(data) {
    if (this.ended) return;
    const message = parse(data);
    if (!message || typeof message !== "object") return;

    if (message.setup) {
      if (this.setupSent) return;
      this.setupSent = true;
      this.toUpstream(JSON.stringify({ setup: premiumSetup(message.setup) }));
      return;
    }

    const input = message.realtimeInput;
    if (!this.setupSent || !input || typeof input !== "object") return;
    const forwarded = {};
    for (const field of INPUT_FIELDS) {
      if (input[field] !== undefined) forwarded[field] = input[field];
    }
    if (forwarded.video !== undefined) {
      const now = this.now();
      if (now - this.lastFrameAt < FRAME_INTERVAL_MS) {
        delete forwarded.video;
      } else {
        this.lastFrameAt = now;
      }
    }
    if (Object.keys(forwarded).length > 0) {
      this.toUpstream(JSON.stringify({ realtimeInput: forwarded }));
    }
  }

  /** A message from Gemini: passed through unchanged; metering starts at setupComplete. */
  upstreamMessage(data) {
    if (this.ended) return;
    this.toClient(data);
    const message = parse(data);
    if (!message) return;
    if (message.setupComplete !== undefined && this.lastTick === null) {
      this.lastTick = this.now();
      this.timer = setInterval(() => this.tick(), this.tickMs);
    }
    const usage = message.usageMetadata;
    if (usage) {
      this.tokens.prompt += usage.promptTokenCount ?? 0;
      this.tokens.response += usage.responseTokenCount ?? 0;
      this.tokens.thoughts += usage.thoughtsTokenCount ?? 0;
    }
  }

  /** Records the time since the last tick and ends the conversation when no minutes are left. */
  tick() {
    if (this.ended) return;
    if (this.record() <= 0) {
      this.toClient(notice("out_of_minutes"));
      this.close(4002, "Out of minutes");
    }
  }

  /** Records talk time since the last record; returns the seconds left. */
  record() {
    if (this.lastTick === null) return Infinity;
    const now = this.now();
    const seconds = Math.max(0, (now - this.lastTick) / 1000);
    this.lastTick = now;
    return this.onTalked(seconds);
  }

  /** Ends the conversation from Scowld's side. */
  close(code, reason) {
    if (this.ended) return;
    this.end();
    this.closeBoth(code, reason);
  }

  /** Stops metering after recording the last partial interval. Safe to call twice. */
  end() {
    if (this.ended) return;
    this.ended = true;
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
    this.record();
  }
}
