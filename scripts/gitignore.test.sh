#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ ! -f .gitignore ]]; then
  echo "missing root .gitignore" >&2
  exit 1
fi

ignored_examples=(
  .DS_Store
  logs/debug.log
  .env
  .env.local
  cloudflared
  cloudflared-linux-amd64.deb
  node_modules/package/index.js
  .idea/workspace.xml
  .vscode/settings.json
)

for path in "${ignored_examples[@]}"; do
  if ! git check-ignore -q --no-index "$path"; then
    echo "expected $path to be ignored" >&2
    exit 1
  fi
done

while IFS= read -r -d '' path; do
  if git check-ignore -q --no-index "$path"; then
    echo "tracked file is ignored: $path" >&2
    exit 1
  fi
done < <(git ls-files -z)

echo "gitignore checks passed"
