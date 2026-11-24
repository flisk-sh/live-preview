#!/usr/bin/env bash
# Exercise the actual run and tunnel scripts without network access or a real tunnel.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/live-preview-run.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/bin"
echo 0 > "$fixture/clock"

printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/pkill"
cat > "$fixture/bin/setsid" <<'EOF'
#!/usr/bin/env bash
echo 'INF | https://ready-preview.trycloudflare.com |'
EOF
cat > "$fixture/bin/date" <<'EOF'
#!/usr/bin/env bash
cat "$LP_DIR/clock"
EOF
cat > "$fixture/bin/sleep" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = 30 ]; then
  echo "$(( $(cat "$LP_DIR/clock") + 30 ))" > "$LP_DIR/clock"
else
  /bin/sleep 0.02
fi
EOF
cat > "$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
test "${@: -1}" = 'https://ready-preview.trycloudflare.com/' || exit 1
if [ ! -e "$LP_DIR/requests" ]; then
  echo 90 > "$LP_DIR/clock"
fi
echo probe >> "$LP_DIR/requests"
EOF
chmod +x "$fixture/bin/"*

env -i PATH="$fixture/bin:/usr/bin:/bin" LP_DIR="$fixture" MINUTES=1 bash "$here/run.sh"
probes=$(wc -l < "$fixture/requests")
if [ "$probes" -ne 3 ]; then
  echo "expected one readiness probe and two monitoring probes, got $probes total" >&2
  exit 1
fi
test "$(cat "$fixture/clock")" -eq 150
echo 'The preview stays up for a full minute after readiness'
