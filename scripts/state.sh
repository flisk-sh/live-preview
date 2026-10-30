#!/usr/bin/env bash
# Keeps a Postgres database between runs. A runner is wiped when the run ends, so the database is dumped,
# encrypted (AES-256, key from STATE_KEY) and stored as the only commit of a branch in THIS repository.
#   state.sh restore | save
# Env: PG_CONTAINER, STATE_KEY, GH_TOKEN, GITHUB_REPOSITORY, STATE_BRANCH (default live-preview-state), LP_DIR,
#      PG_USER / PG_DB (optional; found from the container when empty).
# Never restores into a database it cannot decrypt a copy for; a wrong key stops the run instead of overwriting data.
set -euo pipefail
branch="${STATE_BRANCH:-live-preview-state}"
dir="${LP_DIR:?LP_DIR is required}/state"
pg="${PG_CONTAINER:?PG_CONTAINER is required}"
remote="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
mkdir -p "$dir"
user="${PG_USER:-$(docker exec "$pg" sh -c 'echo "${POSTGRES_USER:-postgres}"')}"
db="${PG_DB:-$(docker exec "$pg" psql -U "$user" -d postgres -Atc "select datname from pg_database order by 1" \
  | grep -vxE 'postgres|template0|template1' | grep -v '_test$' | head -1 || true)}"
[ -n "$db" ] || db=postgres

case "${1:-}" in
  restore)
    rm -rf "$dir/repo"
    git clone -q --depth 1 --branch "$branch" "$remote" "$dir/repo" 2>/dev/null || { echo "no saved state yet"; exit 0; }
    openssl enc -d -aes-256-cbc -pbkdf2 -pass env:STATE_KEY -in "$dir/repo/db.dump.enc" -out "$dir/restore.dump" \
      || { echo "::error::the saved state cannot be decrypted (did STATE_KEY change?); not touching the database"; exit 1; }
    docker exec -i "$pg" pg_restore -U "$user" -d "$db" --clean --if-exists --no-owner < "$dir/restore.dump" \
      || echo "::warning::pg_restore reported warnings (usually harmless)"
    rm -f "$dir/restore.dump"
    echo "state restored from $(git -C "$dir/repo" log -1 --format=%cd)"
    ;;
  save)
    # pg_dump -Fc is not byte-stable, so detect changes on a plain data-only dump.
    sum=$(docker exec "$pg" pg_dump -U "$user" --data-only -Fp "$db" | grep -v '^--' | md5sum | cut -d' ' -f1)
    [ -f "$dir/last.sum" ] && [ "$(cat "$dir/last.sum")" = "$sum" ] && exit 0
    docker exec "$pg" pg_dump -U "$user" -Fc "$db" > "$dir/new.dump"
    rm -rf "$dir/out"; mkdir -p "$dir/out"
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass env:STATE_KEY -in "$dir/new.dump" -out "$dir/out/db.dump.enc"
    git -C "$dir/out" init -q -b "$branch"
    git -C "$dir/out" add db.dump.enc
    git -C "$dir/out" -c user.name=live-preview -c user.email=live-preview@users.noreply.github.com commit -q -m "state $(date -u +%FT%TZ)"
    git -C "$dir/out" push -q --force "$remote" "HEAD:refs/heads/$branch"
    echo "$sum" > "$dir/last.sum"; echo "state saved"
    ;;
  *) echo "usage: state.sh restore|save" >&2; exit 2 ;;
esac
