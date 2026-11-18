#!/usr/bin/env bash
# Exercise polling with synthetic logs. No network, tunnel or process killing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/bin"

printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/pkill"
printf '#!/usr/bin/env bash\ncat "$TUNNEL_TEST_LOG"\n' > "$fixture/bin/setsid"
cat > "$fixture/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$LP_DIR/sleeps"
/bin/sleep 0.02
EOF
cat > "$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${@: -1}" >> "$LP_DIR/requests"
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
export ORIGIN='http://127.0.0.1:8080' HEALTH_PATH='/' HOST_HEADER=''

export LP_DIR="$fixture/rate-limited"
export TUNNEL_TEST_LOG="$fixture/error.log"
printf '%s\n' 'ERR Failed to request quick tunnel error="429 from https://api.trycloudflare.com/tunnel"' > "$TUNNEL_TEST_LOG"
status=0
output=$(bash "$here/tunnel.sh" 2>&1) || status=$?
test "$status" -eq 1
test ! -e "$LP_DIR/url"
test ! -e "$LP_DIR/requests"
test "$(wc -l < "$LP_DIR/sleeps")" -lt 10
grep -Fq '429 from https://api.trycloudflare.com/tunnel' <<< "$output"

export LP_DIR="$fixture/success"
export TUNNEL_TEST_LOG="$fixture/ready.log"
url='https://word-word-word-word.trycloudflare.com'
printf '%s\n' "INF |  $url  |" > "$TUNNEL_TEST_LOG"
bash "$here/tunnel.sh"
test "$(cat "$LP_DIR/url")" = "$url"
test "$(cat "$LP_DIR/requests")" = "$url/"
echo 'Both tunnel log cases passed'
