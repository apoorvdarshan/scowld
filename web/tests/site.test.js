import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { checkSite, resolvePath } from "../scripts/check-site.js";

const root = fileURLToPath(new URL("../public", import.meta.url));

describe("static site", () => {
  it("passes every page, link, JSON-LD and sitemap check", () => {
    expect(checkSite(root)).toEqual([]);
  });

  it("resolves paths the way the assets binding serves them", () => {
    expect(resolvePath(root, "/")).toMatch(/public\/index\.html$/);
    expect(resolvePath(root, "/privacy")).toMatch(/public\/privacy\.html$/);
    expect(resolvePath(root, "/blog")).toMatch(/public\/blog\.html$/);
    expect(resolvePath(root, "/blog/bring-your-own-key-ai-app")).toMatch(/bring-your-own-key-ai-app\.html$/);
    expect(resolvePath(root, "/media/bella.mp4")).toMatch(/media\/bella\.mp4$/);
    expect(resolvePath(root, "/no-such-page")).toBeNull();
  });
});
