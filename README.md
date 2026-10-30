# live-preview

Give a Docker stack that runs on a **GitHub Actions runner** a public HTTPS link (Cloudflare quick tunnel), keep it up
for N minutes, watch it, and **keep its Postgres database between runs**. No server, no account other than GitHub.
Good for: showing a work-in-progress to a client, a recruiter test that must be reachable for an afternoon,
pull-request previews. Not for: permanent hosting (a run lives at most 6 hours and the link changes every run).

```yaml
jobs:
  preview:
    runs-on: ubuntu-latest
    permissions: { contents: write }          # only needed for the saved database
    steps:
      - uses: actions/checkout@v4
      - run: docker compose up -d --wait      # your stack; something must listen on a local port
      - uses: flisk-sh/live-preview@v1
        with:
          origin: http://127.0.0.1:8080       # where the app listens on the runner
          minutes: 120
          # optional: keep the database between runs
          pg-container: my-db
          state-key: ${{ secrets.STATE_KEY }} # any long random string; keep it the same between runs
```

The link is printed in the log and the job summary, and is the `url` output.

## What it does
1. Installs `cloudflared`, opens a quick tunnel to `origin` and waits until the public name answers `health-path`.
2. Every 30 s checks the public link (and `health-cmd`, e.g. a `docker exec` probe). After 3 failures in a row it opens
   a new tunnel (new link, up to 5 times).
3. With `pg-container`: restores the last saved database before the app is used, saves it (encrypted with AES-256,
   key `state-key`) every 2 minutes when it changed and when the run ends. The copy is the only commit of branch
   `live-preview-state` of your repository. A wrong key stops the run instead of overwriting data.

## Things to know
- The restore runs when the action starts, **after** your stack is up. If your app caches the schema at start,
  restart it after the restore (or restore from your own step by running `scripts/state.sh restore` first).
- Use the same `state-key` every time. Treat the branch as private data: use it only in private repositories
  unless you accept an encrypted copy being public.
- Quick tunnels are for testing: no uptime promise from Cloudflare, no custom domain.
- Several runs at once: add `concurrency: { group: live-preview, cancel-in-progress: false }` to your job.

The `self-test` workflow in this repository runs the whole thing twice on clean runners and fails if the row written by
the first run is missing in the second.

## Example: a public model API (flisk-wolf)

`.github/workflows/flisk-wolf.yml` runs a small model behind an API portal on a runner and puts this action in front of it. Run it with **Actions → flisk-wolf → Run workflow**, then read the link in the job summary and call it:

```bash
curl https://<the-link>.trycloudflare.com/v1/chat/completions \
  -H "Authorization: Bearer $WOLF_API_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"flisk-wolf","messages":[{"role":"user","content":"Write a Flisk service.json for a worker called emailer in the shop stack."}]}'
```

The repository secret `WOLF_API_KEY` is the only key the portal accepts. The runner has no GPU, so a reply takes tens of seconds, and the model is downloaded again on every run (about 6 GB). The portal comes from [flisk-inference](https://github.com/flisk-sh/flisk-inference).
