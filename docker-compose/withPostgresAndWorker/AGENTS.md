# taoziyoyo n8n deployment: agent instructions

Portable behavior is owned by `~/workspace/.agents/rules/`. The repository
root `AGENTS.md` is upstream's and covers the official artefacts; this file
holds only the facts and constraints of this directory on branch `taoziyoyo`.

## Facts

- This directory runs n8n on host taoziyoyo. The official
  `docker-compose.yml` and `init-data.sh` stay unchanged;
  `docker-compose.override.yml` (loaded automatically) holds every host
  customization; `.env` (ignored) holds the host values, named as in
  `.env.template`. The design and its history:
  [docs/plan-upstream-override-2026-10-29.md](docs/plan-upstream-override-2026-10-29.md).
- Compose project `withpostgresandworker`. Its internal network
  `withpostgresandworker_backend` is shared with the separate
  invoice_automation app, which calls `http://n8n:5678`. n8n listens on
  `127.0.0.1:5678`; the public name `n8n.saberu.com` goes through the host's
  cloudflared tunnel.
- Branches: `origin/main` follows upstream; `taoziyoyo` is upstream plus the
  files in this directory that upstream does not have, minus its sample
  `.env`; `taoziyoyo-legacy` is the layout used before this one and serves as
  its rollback; `security-workflow-prism` is NanoPi-R6S's.
- Run from this directory: `docker compose config` to check the merged
  result, `docker compose pull`, `docker compose up -d --remove-orphans`,
  `docker compose ps`; health at `http://127.0.0.1:5678/healthz`. The
  operator's runbook (Chinese): [OPERATIONS.md](OPERATIONS.md).
- Updating to an official release: `git merge origin/main`, keep the sample
  `.env` deleted after reading its diff for new variables, read the
  `docker-compose.yml` diff against the override, set `N8N_VERSION` in
  `.env`, then pull and bring the stack up.

## Constraints

- Never edit the official files on this branch; put every difference in the
  override, and add new files rather than changing upstream ones.
- Never print values from `.env` or from migration archives.
- Postgres stays on the major version the override pins until a planned dump
  and restore into a fresh volume.
- Keep n8n bound to `127.0.0.1`: the official file publishes it on every
  interface.
- Keep the `backend` and `ingress` network definitions as they are; changing
  them makes Compose recreate `backend` under the invoice app.
- Running containers keep this directory's absolute path. After moving the
  checkout, recreate the stack from the new path.
- A fresh n8n has no owner until setup completes: keep it off public
  hostnames until then.
