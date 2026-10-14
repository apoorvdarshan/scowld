#!/bin/bash
# Serves the OpenNext build in the local Workers runtime (wrangler dev, no
# Cloudflare account needed) and checks that every page in the sitemap renders.
# A build can succeed and still fail every request at runtime, as next 16.4 did
# under @opennextjs/cloudflare 1.20.11. Run after `npm run build`. Never deploys.
set -euo pipefail
cd "$(dirname "$0")/.."

port="${SMOKE_PORT:-8789}"
base="http://localhost:$port"
log="$(mktemp)"

# Job control gives the preview its own process group, so cleanup also stops
# the workerd processes wrangler starts.
set -m
npx opennextjs-cloudflare preview --port "$port" > "$log" 2>&1 &
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
    echo "The preview server exited before it served a request." >&2
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
# Without a GITHUB_TOKEN the star history serves its designed fallback card.
check /api/star-history.svg 503 image/svg+xml

if [[ "$failed" != 0 ]]; then
  grep -iE 'error|exception' "$log" | head -40 || true
  exit 1
fi
