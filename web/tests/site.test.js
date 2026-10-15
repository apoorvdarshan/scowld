import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

  it("rejects a lookalike canonical host and inline scripts in any case", () => {
    const dir = mkdtempSync(join(tmpdir(), "scowld-site-"));
    try {
      writeFileSync(join(dir, "index.html"), `<!DOCTYPE html>
<html lang="en"><head><title>T</title><meta name="description" content="D">
<link rel="canonical" href="https://www.scowld.xyz.example.com/"></head>
<body><h1>T</h1><SCRIPT>alert(1)</SCRIPT><p STYLE="color:red" onClick="x()">x</p></body></html>`);
      writeFileSync(join(dir, "404.html"), "");
      writeFileSync(join(dir, "sitemap.xml"), "<urlset></urlset>");
      const problems = checkSite(dir).join("\n");
      expect(problems).toContain("is not on https://www.scowld.xyz");
      expect(problems).toContain("inline <script>");
      expect(problems).toContain("inline style attribute");
      expect(problems).toContain("inline event handler");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
