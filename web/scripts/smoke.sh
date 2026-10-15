#!/bin/bash
# Serves the site in the local Workers runtime (wrangler dev, no Cloudflare
# account needed) and checks every sitemap page, the 404 page, the security
# headers from public/_headers and the star-history endpoint. Never deploys.
set -euo pipefail
cd "$(dirname "$0")/.."

port="${SMOKE_PORT:-8789}"
base="http://localhost:$port"
log="$(mktemp)"

# Job control gives wrangler its own process group, so cleanup also stops the
# workerd processes it starts.
set -m
npx wrangler dev --port "$port" --show-interactive-dev-session=false > "$log" 2>&1 &
server=$!
set +m
cleanup() {
  kill -- "-$server" 2> /dev/null || true
  wait "$server" 2> /dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 90); do
  if curl -s -o /dev/null "$base/"; then break; fi
  if ! kill -0 "$server" 2> /dev/null; then
    cat "$log"
    echo "wrangler dev exited before it served a request." >&2
    exit 1
  fi
  sleep 1
done

failed=0
check() { # path, expected status, expected content type
  local result
  result="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$base$1")"
  if [[ "$result" == "$2 $3"* ]]; then
    echo "ok    $result $1"
  else
    echo "FAIL  $result $1 (expected $2 $3)"
    failed=1
  fi
}

check /sitemap.xml 200 application/xml
pages="$(curl -s "$base/sitemap.xml" | grep -o '<loc>[^<]*</loc>' | sed -E 's#</?loc>##g; s#^https://(www\.)?scowld\.xyz##; s#^$#/#')"
if [[ -z "$pages" ]]; then
  echo "FAIL  the sitemap lists no pages"
  failed=1
fi
for page in $pages; do
  check "$page" 200 text/html
done
check /robots.txt 200 text/plain
check /assets/site.css 200 text/css
check /assets/scene.js 200 text/javascript
check /media/bella.mp4 200 video/mp4
check /no-such-page 404 text/html
# Without a GITHUB_TOKEN the star history serves its designed fallback card.
check /api/star-history.svg 503 image/svg+xml

if curl -s -D - -o /dev/null "$base/" | grep -qi "^content-security-policy: default-src 'self'"; then
  echo "ok    Content-Security-Policy on /"
else
  echo "FAIL  / has no Content-Security-Policy header from public/_headers"
  failed=1
fi

if [[ "$failed" != 0 ]]; then
  grep -iE 'error|exception' "$log" | head -40 || true
  exit 1
fi
