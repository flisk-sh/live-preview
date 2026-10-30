#!/usr/bin/env bash
# Opens the tunnel, prints the link, then keeps the run alive for MINUTES while watching it:
# every 30 s the public link (and HEALTH_CMD, if set) is checked; after 3 failures in a row the tunnel is restarted
# (the URL changes, up to 5 times). With PG_CONTAINER set the database is saved every 2 minutes and on exit.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export LP_DIR="${LP_DIR:-$RUNNER_TEMP/live-preview}"
mkdir -p "$LP_DIR"
minutes="${MINUTES:-60}"
until_s=$(( $(date +%s) + minutes * 60 ))

save() { [ -n "${PG_CONTAINER:-}" ] && [ -n "${STATE_KEY:-}" ] && bash "$here/state.sh" save || true; }
trap 'save' EXIT

bash "$here/tunnel.sh" || exit 1
url=$(cat "$LP_DIR/url")
echo "url=$url" >> "${GITHUB_OUTPUT:-/dev/null}"
{
  echo "### Live preview"
  echo "- Link: $url"
  echo "- Stays up for $minutes minutes (the link is new on every run)"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "LIVE PREVIEW: $url"
# An annotation is readable through the API while the job runs; the log and the summary are only available after it ends.
echo "::notice title=Live preview link::$url"

fails=0; restarts=0; last_save=0
while [ "$(date +%s)" -lt "$until_s" ]; do
  url=$(cat "$LP_DIR/url"); ok=1
  curl -fsS -m 15 -o /dev/null "$url${HEALTH_PATH:-/}" 2>/dev/null || ok=0
  [ -n "${HEALTH_CMD:-}" ] && { bash -c "$HEALTH_CMD" >/dev/null 2>&1 || ok=0; }
  if [ "$ok" = 1 ]; then fails=0; else fails=$((fails + 1)); echo "::warning::check failed ($fails in a row) for $url"; fi
  if [ "$fails" -ge 3 ]; then
    [ "$restarts" -ge 5 ] && { echo "::error::the tunnel failed 5 times; giving up"; exit 1; }
    restarts=$((restarts + 1)); echo "::warning::restarting the tunnel ($restarts); the link changes"
    if bash "$here/tunnel.sh"; then fails=0; echo "NEW LINK: $(cat "$LP_DIR/url")"; echo "::notice title=Live preview link (restart $restarts)::$(cat "$LP_DIR/url")"; echo "- Link after restart $restarts: $(cat "$LP_DIR/url")" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; fi
  fi
  if [ $(( $(date +%s) - last_save )) -ge 120 ]; then save; last_save=$(date +%s); fi
  sleep 30
done
echo "the end time passed after $restarts tunnel restart(s)"
