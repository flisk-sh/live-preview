#!/usr/bin/env bash
# Tests scripts/install-cloudflared.sh with a stubbed machine architecture (UNAME_M).
# Every case runs in dry-run mode, so it needs no network, no root and no installed cloudflared.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/install-cloudflared.sh"
test_version=9.9.9
fails=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

expect_url() { # machine package_suffix
  local machine=$1 pkg=$2 out rc expected
  expected="https://github.com/cloudflare/cloudflared/releases/download/$test_version/cloudflared-linux-$pkg.deb"
  out=$(UNAME_M="$machine" CLOUDFLARED_VERSION="$test_version" bash "$script" --dry-run 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$machine: expected exit 0, got $rc ($out)"
  elif [ "$out" != "$expected" ]; then
    fail "$machine: expected $expected, got $out"
  else
    pass "$machine installs linux-$pkg"
  fi
}

expect_fail() { # machine
  local machine=$1 out rc
  out=$(UNAME_M="$machine" CLOUDFLARED_VERSION="$test_version" bash "$script" --dry-run 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$machine: expected a non-zero exit"
  elif [ "${out#*"$machine"}" = "$out" ]; then
    fail "$machine: the error does not name the architecture ($out)"
  else
    pass "$machine fails and names the architecture"
  fi
}

expect_url x86_64 amd64
expect_url amd64 amd64
expect_url aarch64 arm64
expect_url arm64 arm64
expect_fail riscv64

# Test checksum mismatch aborts before dpkg and curl receives retry/timeout flags
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"
curl_args_file="$tmpdir/curl_args"
dpkg_called_file="$tmpdir/dpkg_called"

cat > "$tmpdir/bin/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$curl_args_file"
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then
    out="\$2"
    shift 2
  else
    shift
  fi
done
printf 'dummy deb content' > "\$out"
EOF
chmod +x "$tmpdir/bin/curl"

cat > "$tmpdir/bin/sudo" <<EOF
#!/usr/bin/env bash
touch "$dpkg_called_file"
exit 0
EOF
chmod +x "$tmpdir/bin/sudo"

out=$(PATH="$tmpdir/bin:/usr/bin:/bin" UNAME_M=x86_64 CLOUDFLARED_VERSION="$test_version" CLOUDFLARED_SHA256="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" RUNNER_TEMP="$tmpdir" bash "$script" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  fail "checksum mismatch: expected non-zero exit"
elif [ -f "$dpkg_called_file" ]; then
  fail "checksum mismatch: dpkg was called despite bad checksum"
elif [ "${out#*checksum}" = "$out" ]; then
  fail "checksum mismatch: expected checksum error message, got: $out"
else
  pass "checksum mismatch aborts before dpkg"
fi

if [ -f "$curl_args_file" ]; then
  curl_args=$(cat "$curl_args_file")
  if [[ "$curl_args" == *"--retry 3"* ]] && [[ "$curl_args" == *"--connect-timeout 10"* ]] && [[ "$curl_args" == *"--max-time 120"* ]]; then
    pass "curl invoked with retry and timeout flags"
  else
    fail "curl missing retry/timeout flags: $curl_args"
  fi
else
  fail "curl was not invoked"
fi

if [ "$fails" -ne 0 ]; then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all tests passed"
