# Updating Hermes

This fork auto-tracks the **latest Hermes release**. The Dockerfile defaults
`HERMES_REF=latest`, which resolves the newest published GitHub release at build
time, and an `ADD .../releases/latest` line busts the build cache whenever a new
release ships. **There is no version string to edit.**

Updating = triggering a **fresh build**. A plain Railway *Redeploy* reuses the
existing image and will **not** pull a newer release — you need an actual rebuild
so the Dockerfile re-runs.

## One-action update

From this directory:

```bash
./update.sh
```

That pushes an empty commit, which Railway auto-deploys as a fresh build on the
latest release. Then wait ~8 min (Railway keeps the old version live until the
new one passes its health check — no downtime).

Alternative, no commit, builds straight from your local tree:

```bash
railway up --detach
```

## Verify the deployed version

```bash
railway logs --build | grep "hermes-agent=="
```

You should see `hermes-agent==<new version>`. Cross-check "latest" at
<https://github.com/NousResearch/hermes-agent/releases>.

## Rollback (if a release breaks something)

1. Pin the last-good tag (overrides `latest`):
   ```bash
   railway variables --set "HERMES_REF=v2026.7.20"
   ```
2. Rebuild: `./update.sh` (or `railway up --detach`).
3. When upstream is fixed, remove the pin to resume auto-latest:
   ```bash
   railway variables --set "HERMES_REF=latest"
   ```

## Update the running container without a rebuild (optional)

Open `/tui` in the WebUI and run:

```bash
hermes update
```

Pulls the latest into the *running* container immediately (works because the
image chowns `/opt/hermes` to `hermes` and sets `safe.directory`). Reverts to the
built-in version on the next rebuild — which also lands on latest, so that's fine.

## Notes

- **WebUI is pinned** (`HERMES_WEBUI_REF=v0.51.310`) to avoid a UI/agent mismatch.
  To float it too, change its default to `latest` and add a matching
  `ADD .../releases/latest` cache-bust for `nesquena/hermes-webui`.
- The GitHub release tag (e.g. `v2026.7.20`) and the Python package version
  (e.g. `0.19.0`) are the same release, just two numbering schemes.
