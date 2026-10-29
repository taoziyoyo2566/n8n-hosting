# Upstream-based n8n deployment on taoziyoyo plan

Status: APPROVED (2026-10-29) for the direction and the baseline commit; the
cut-over needs its own approval with an action brief.

## Goal

Run this host's n8n from the official `docker-compose/withPostgresAndWorker`
files unchanged, with every host customization in files the official tree
does not have, so that taking an official release means merging `origin/main`
and changing `N8N_VERSION`.

## Current state (2026-10-29)

- Running: the legacy layout committed as `taoziyoyo-legacy` (`b6bd3e7`,
  whose config hashes equal the running containers'): n8n and worker 2.45.5,
  one custom runner image (extra Python packages) attached to the worker,
  `db-init`, Postgres 17, Redis 6.2.14 with a password, networks `backend`
  (internal, shared with invoice_automation) and `ingress`, n8n on
  `127.0.0.1:5678`.
- Official `origin/main` (`3dda2e1`): one `N8N_VERSION` for n8n and runners;
  a runner sidecar each for main and worker on `n8nio/runners`; Postgres 18
  with `PGDATA` pinned to `/var/lib/postgresql/data`; Redis 7 without a
  password; the default network only; n8n published on all interfaces
  (`5678:5678`); a tracked sample `.env` with placeholders.
- Docker Compose v5.1.1, tested offline: `docker-compose.override.yml` loads
  automatically next to `docker-compose.yml`; `!override` replaces a list;
  `environment` merges by key; `COMPOSE_FILE` set in `.env` is honored,
  `COMPOSE_ENV_FILES` set in `.env` is not.

## Design

- Branch `taoziyoyo` is `origin/main` plus added files, minus the official
  sample `.env`; the real `.env` is host-local and ignored.
- `docker-compose.override.yml` holds every difference: n8n bound to
  `127.0.0.1`; Postgres 17 for the existing volume; the Redis password
  (command and health check); SMTP, `N8N_WEBHOOK_URL`, time zone, proxy hops,
  secure cookie, settings-file permissions, diagnostics off; user 1000:1000;
  `no-new-privileges`; the `backend` (internal) and `ingress` networks with
  today's definitions, so invoice_automation keeps
  `withpostgresandworker_backend`.
- `.env` uses the official variable names, adds `N8N_VERSION=2.45.5` and
  `RUNNERS_AUTH_TOKEN`, and keeps the legacy names so `taoziyoyo-legacy`
  still runs as the rollback.
- Runners use the official `n8nio/runners` image without extra Python
  packages; `db-init` is dropped.
- `AGENTS.md`, `CLAUDE.md`, `.env.template`, and the operator's runbook
  `OPERATIONS.md` in this directory document the host layer; the repository
  root files stay upstream's.

## Steps

1. Commit the running layout as `taoziyoyo-legacy` (done, `b6bd3e7`).
2. Build `taoziyoyo` in the worktree
   `~/workspace/.worktrees/n8n-hosting-taoziyoyo`.
3. Compare the resolved configs of both layouts offline and dry-run Compose
   against the running project. Done: only the intended differences, no
   network or volume recreation.
4. Cut-over (own approval): in the deployment checkout switch to `taoziyoyo`,
   add the new `.env` variables, run `docker compose up -d --remove-orphans`,
   and verify health, versions, runners, and an isolated invoice test.
   Rollback: switch back to `taoziyoyo-legacy`, empty the `redis_storage`
   volume (Redis 6.2 cannot read data written by Redis 7; it holds only the
   job queue), and run the same command.
5. Push `taoziyoyo` and remove the worktree.

## Updating to an official release

`git fetch origin && git merge origin/main`; keep the sample `.env` deleted
and read its upstream diff for new variables; read the `docker-compose.yml`
diff against the override; set `N8N_VERSION` in `.env`; then
`docker compose pull && docker compose up -d`.

## Risks

- Redis 7 opens the 6.2 data; it holds only the queue.
- Network definitions that differ from today's make Compose recreate
  `backend`, which invoice_automation uses.
- Each official merge can still rename services, add required variables, or
  move Postgres to a new major version; read the diff before deploying.

## Operator decisions

- 2026-10-29, operator: "按照推荐的来". Adopt this structure, use the official
  runners image, and commit the running layout as a baseline first.
