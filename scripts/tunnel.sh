#!/usr/bin/env bash
# Starts (or restarts) a Cloudflare quick tunnel to ORIGIN and writes its public URL to $LP_DIR/url.
# Env: ORIGIN (default http://127.0.0.1:8080), HOST_HEADER (optional), HEALTH_PATH (default /), LP_DIR.
set -euo pipefail
origin="${ORIGIN:-http://127.0.0.1:8080}"
health="${HEALTH_PATH:-/}"
dir="${LP_DIR:?LP_DIR is required}"
mkdir -p "$dir"
pkill -x cloudflared 2>/dev/null || true
sleep 1
: > "$dir/tunnel.log"
args=(tunnel --no-autoupdate --url "$origin")
[ -n "${HOST_HEADER:-}" ] && args+=(--http-host-header "$HOST_HEADER")
setsid nohup cloudflared "${args[@]}" > "$dir/tunnel.log" 2>&1 < /dev/null &
url=""
for _ in $(seq 60); do
  url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$dir/tunnel.log" | head -1 || true)
  [ -n "$url" ] && break
  sleep 2
done
[ -n "$url" ] || { echo "::error::no tunnel URL"; tail -20 "$dir/tunnel.log"; exit 1; }
echo "$url" > "$dir/url"
# A fresh quick-tunnel name can take a while to resolve, so wait up to 3 minutes.
for _ in $(seq 60); do
  curl -fsS -m 10 -o /dev/null "$url$health" 2>/dev/null && { echo "tunnel up: $url"; exit 0; }
  sleep 3
done
echo "::error::the tunnel $url did not answer $health within 3 minutes"
exit 1
