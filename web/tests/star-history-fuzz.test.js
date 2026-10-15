import fc from "fast-check";
import { XMLValidator } from "fast-xml-parser";
import { describe, expect, it } from "vitest";
import {
  parseStargazerPage,
  renderError,
  renderStarHistory,
} from "../src/star-history.js";

// The README embeds /api/star-history.svg, which renders whatever GitHub's
// stargazers API returns. These properties fuzz that path with generated input.
// fast-check prints a seed and shrunk counterexample on failure for exact replay.
const options = { numRuns: 1000 };
const themes = fc.constantFrom("light", "dark");
// Any render time from GitHub's launch to 2100.
const renderTime = fc.integer({ min: Date.UTC(2008, 0, 1), max: Date.UTC(2100, 0, 1) });
// Date strings JavaScript can parse, from the earliest to the latest valid Date,
// mixed with arbitrary text that may not parse at all.
const starredAt = fc.oneof(
  fc.date({ min: new Date(-8.64e15), max: new Date(8.64e15), noInvalidDate: true }).map((date) => date.toISOString()),
  fc.date({ min: new Date("2008-01-01"), max: new Date("2100-01-01"), noInvalidDate: true }).map((date) => date.toISOString()),
  fc.string(),
);

function expectValidSvg(svg) {
  expect(XMLValidator.validate(svg)).toBe(true);
  // A coordinate that is NaN or Infinity produces an SVG browsers refuse to draw.
  expect(svg).not.toMatch(/NaN|Infinity/);
}

describe("stargazer page parsing", () => {
  it("accepts any JSON value without unexpected exceptions", () => {
    fc.assert(fc.property(fc.jsonValue(), (payload) => {
      if (!Array.isArray(payload)) {
        expect(() => parseStargazerPage(payload)).toThrow("unexpected response");
        return;
      }
      const { starredAt: values, pageSize } = parseStargazerPage(payload);
      expect(pageSize).toBe(payload.length);
      expect(values.every((value) => typeof value === "string")).toBe(true);
    }), options);
  });

  it("keeps every starred_at string in order", () => {
    fc.assert(fc.property(fc.array(fc.record({ starred_at: fc.string() })), (payload) => {
      expect(parseStargazerPage(payload).starredAt).toEqual(payload.map((item) => item.starred_at));
    }), options);
  });
});

describe("star history rendering", () => {
  it("renders well-formed SVG for any stargazer dates", () => {
    fc.assert(fc.property(fc.array(starredAt, { maxLength: 200 }), themes, renderTime, (values, theme, now) => {
      expectValidSvg(renderStarHistory(values, theme, now));
    }), options);
  });

  it("reports one star per parseable date", () => {
    fc.assert(fc.property(fc.array(starredAt, { maxLength: 200 }), renderTime, (values, now) => {
      const parseable = values.filter((value) => Number.isFinite(new Date(value).getTime())).length;
      const svg = renderStarHistory(values, "light", now);
      expect(svg).toContain(`<desc id="description">${parseable} GitHub stars over time`);
      expect(svg).toContain(`font-weight="800">${parseable}</text>`);
    }), options);
  });

  it("renders the error card for both themes", () => {
    expectValidSvg(renderError("light"));
    expectValidSvg(renderError("dark"));
  });
});
