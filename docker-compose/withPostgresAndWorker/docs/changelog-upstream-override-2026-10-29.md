# Upstream-based n8n deployment on taoziyoyo changelog

Plan: [plan-upstream-override-2026-10-29.md](plan-upstream-override-2026-10-29.md)

## Outcome — 2026-10-29

- `taoziyoyo-legacy` (`b6bd3e7`) recorded the previous layout as the rollback
  target; before the cut-over its config hashes matched the running
  containers.
- `taoziyoyo` (`b3534b7`) is official `3dda2e1` plus this directory's override,
  `.env.template`, runbook, agent files, and plan, minus the sample `.env`.
- The host `.env` gained `N8N_VERSION=2.45.5` and `RUNNERS_AUTH_TOKEN`, which
  refers to the existing token; the legacy names stayed for rollback until the
  cleanup below.
- Cut-over, 21:57 to 21:58 JST: postgres, redis, n8n, and the worker were
  recreated; the official `n8n-runner` and `n8n-worker-runner` were created;
  `db-init` and `n8n-task-runners` were removed. n8n answered `/healthz`
  about one minute after the start; all volumes and networks were kept.

## Verification

- Before the cut-over: the resolved configs of both layouts differed only as
  intended, and a Compose dry run showed no network or volume recreation.
- After: the running config hashes equal `docker compose config --hash` for
  all six services; the working directory is unchanged; n8n 2.45.5; the
  worker registered the JavaScript and Python runners; no errors in the n8n
  logs; the `WEBHOOK_URL` and `N8N_RUNNERS_ENABLED` notices are gone; Redis 7
  loaded the 6.2 data; `Invoice-prod` is published with the `.env.prod` path;
  the owner keeps MFA; the invoice app reaches n8n; `n8n.saberu.com` answers
  200 and a public probe reached this n8n; `invoice.saberu.com` still
  redirects to Cloudflare Access.
- Functional: a POST without files to `Invoice-prod` (execution 3) stopped at
  "Validate Files and Extract Month" with "Missing multipart file field:
  worksheet", so the JavaScript ran on the worker's runner; the email node did
  not run.

## After the cut-over

By the operator's decision, no rollback layout is kept:

- `taoziyoyo-legacy` was deleted on `origin` (race-safe, at `b6bd3e7`) and
  locally.
- The host `.env` was rebuilt in `.env.template`'s order without the
  legacy-only names (`N8N_RUNNERS_ENABLED`,
  `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS`,
  `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS`, `N8N_RUNNERS_AUTH_TOKEN`, whose
  value now sits in `RUNNERS_AUTH_TOKEN`); all six config hashes still equal
  the running containers'.
- The old images (legacy runner build, Redis 6.2, Postgres 16, n8n 2.2.6) and
  the old migration files were removed.
- `OPERATIONS.md` now recovers from a bad upgrade by restoring the pre-upgrade
  database dump; that restore command was rehearsed over existing data in a
  throwaway Postgres 17 container and reproduced the source's object counts.
- `origin` stays public; the documentation no longer names the SSH user or
  the tunnel ID.

## Notes and follow-ups

- `n8n-runner` waits for a broker indefinitely: with
  `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true` the main instance starts none
  (`commands/start.js` in n8n 2.45.5). It is kept as upstream ships it and is
  explained in `OPERATIONS.md`.
- n8n still announces default changes for `N8N_UNVERIFIED_PACKAGES_ENABLED`,
  `N8N_RUNNERS_TASK_TIMEOUT`, and the two `N8N_COMPRESSION_NODE_MAX_*`
  settings.
- `origin` is public. Earlier commits on `taoziyoyo` keep host details that
  the documentation has since dropped; the public history was not rewritten.
