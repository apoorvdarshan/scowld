// Checks the static site in public/ before it ships: page metadata, internal
// links and assets, JSON-LD, the sitemap, and markup the Content-Security-Policy
// in public/_headers would block. There is nothing to compile, so this is the
// build step. Prints every problem and exits 1 if there are any.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const SITE = "https://www.scowld.xyz";

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

// Mirrors wrangler.jsonc: html_handling "auto-trailing-slash" serves /privacy
// from privacy.html and / from index.html.
export function resolvePath(root, pathname) {
  const clean = decodeURIComponent(pathname.split(/[?#]/)[0]);
  const candidates = clean.endsWith("/")
    ? [join(root, clean, "index.html")]
    : [join(root, clean), join(root, `${clean}.html`), join(root, clean, "index.html")];
  return candidates.find((path) => existsSync(path) && statSync(path).isFile()) ?? null;
}

const attribute = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];

export function checkSite(root) {
  const problems = [];
  const files = walk(root);
  const pages = files.filter((file) => file.endsWith(".html"));
  const indexable = new Set();

  for (const file of pages) {
    const name = relative(root, file);
    const html = readFileSync(file, "utf8");
    const report = (message) => problems.push(`${name}: ${message}`);
    const noindex = /<meta name="robots" content="noindex/.test(html);

    if (!/^<!doctype html>/i.test(html)) report("missing <!doctype html>");
    if (!/<html lang="en">/.test(html)) report('missing <html lang="en">');
    if (!/<title>[^<]+<\/title>/.test(html)) report("missing <title>");
    if (!/<meta name="description" content="[^"]+">/.test(html)) report("missing meta description");
    if ((html.match(/<h1[\s>]/g) ?? []).length !== 1) report("needs exactly one <h1>");

    const canonical = html.match(/<link rel="canonical" href="([^"]+)">/)?.[1];
    if (noindex) {
      if (canonical) report("a noindex page must not declare a canonical URL");
    } else if (!canonical) {
      report("missing canonical link");
    } else if (!canonical.startsWith(SITE)) {
      report(`canonical ${canonical} is not on ${SITE}`);
    } else {
      const target = resolvePath(root, new URL(canonical).pathname);
      if (target !== file) report(`canonical ${canonical} does not resolve to this page`);
      indexable.add(canonical);
    }

    // The Content-Security-Policy allows only same-origin scripts and styles.
    if (/\sstyle="/.test(html)) report("inline style attribute (blocked by the CSP)");
    if (/<style[\s>]/.test(html)) report("inline <style> element (blocked by the CSP)");
    if (/\son[a-z]+="/.test(html)) report("inline event handler (blocked by the CSP)");
    for (const tag of html.match(/<script\b[^>]*>/g) ?? []) {
      if (!attribute(tag, "src") && attribute(tag, "type") !== "application/ld+json") {
        report("inline <script> (blocked by the CSP)");
      }
    }

    for (const [, json] of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
      try {
        JSON.parse(json);
      } catch (error) {
        report(`JSON-LD does not parse: ${error.message}`);
      }
    }

    for (const [, url] of html.matchAll(/\s(?:href|src|poster)="(\/[^"]*)"/g)) {
      if (!url.startsWith("//") && !url.startsWith("/api/") && !resolvePath(root, url)) {
        report(`broken internal link ${url}`);
      }
    }

    // The scene's look buttons swap in /media/<clip>.mp4 and .jpg at runtime.
    for (const [, clip] of html.matchAll(/data-clip="([^"]+)"/g)) {
      for (const extension of ["mp4", "jpg"]) {
        if (!existsSync(join(root, "media", `${clip}.${extension}`))) {
          report(`missing /media/${clip}.${extension} for data-clip="${clip}"`);
        }
      }
    }
  }

  for (const file of files.filter((path) => path.endsWith(".css"))) {
    const css = readFileSync(file, "utf8");
    for (const [, url] of css.matchAll(/url\("([^"]+)"\)/g)) {
      const target = url.startsWith("/") ? resolvePath(root, url) : resolvePath(root, `/${relative(root, join(file, "..", url))}`);
      if (!target) problems.push(`${relative(root, file)}: broken url("${url}")`);
    }
  }

  const sitemapPath = join(root, "sitemap.xml");
  if (!existsSync(sitemapPath)) {
    problems.push("sitemap.xml is missing");
  } else {
    const listed = new Set([...readFileSync(sitemapPath, "utf8").matchAll(/<loc>([^<]+)<\/loc>/g)].map(([, loc]) => loc));
    for (const loc of listed) {
      if (!indexable.has(loc)) problems.push(`sitemap.xml lists ${loc}, which is not an indexable page`);
    }
    for (const url of indexable) {
      if (!listed.has(url)) problems.push(`sitemap.xml is missing ${url}`);
    }
  }

  if (!existsSync(join(root, "404.html"))) problems.push("404.html is missing (wrangler.jsonc uses it for not_found_handling)");

  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL("../public", import.meta.url));
  const problems = checkSite(root);
  for (const problem of problems) console.error(`FAIL  ${problem}`);
  if (problems.length > 0) process.exit(1);
  console.log(`ok    ${walk(root).filter((file) => file.endsWith(".html")).length} pages checked`);
}
