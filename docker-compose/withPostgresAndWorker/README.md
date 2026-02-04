# n8n with PostgreSQL and Worker

Starts n8n with PostgreSQL as database, and the Worker as a separate container.

## Start

To start n8n simply start docker-compose by executing the following
command in the current folder.

**IMPORTANT:** Create a real `.env` from the template before starting:

```
./generate-env.sh          # generates .env with random secrets
docker compose up -d       # build custom n8n image with Python + start all services (main, worker, runner)
```

To stop it execute:

```
docker compose stop
```

## Configuration

Edit the generated [`.env`](.env) file to change database user/password, Redis password, encryption key, timezone, etc. The template lives in [`.env.template`](.env.template).

Key variables in `.env`:
- `POSTGRES_*`: DB admin/app credentials (used by init and runtime)
- `REDIS_PASSWORD`: Redis/Bull queue auth
- `ENCRYPTION_KEY`: n8n credential encryption (keep safe/backup)
- `WEBHOOK_URL`: External URL (e.g., `https://n8n.yourdomain.com/`) for reverse proxy/tunnel
- `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true`: Avoids deprecation warning
- `N8N_RUNNERS_AUTH_TOKEN`: Shared secret between n8n main/worker and Python runner
- `N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0`: Broker binds to all interfaces so runners can connect
- `N8N_RUNNERS_TASK_BROKER_URI=http://n8n-worker:5679`: Runner connects to the worker’s broker (update host if you add more workers)
- `N8N_PROXY_HOPS=1`: Trust first reverse-proxy hop (Cloudflare/Nginx) so rate limiting sees real client IP

## Services
- `n8n`: main UI/API
- `n8n-worker`: queue worker + task broker
- `n8n-task-runners`: external runner image (Python deps)
- `postgres`, `redis`

## Security & hardening
- Enable first-layer auth for UI (reverse-proxy auth/SSO or `N8N_BASIC_AUTH_*`).
- Keep `.env` outside VCS (already in `.gitignore`). Consider Docker secrets + `_FILE` env variants for credentials.
- Cloud/Reverse proxy: set `WEBHOOK_URL` correctly; keep `N8N_PROXY_HOPS=1` (or a CIDR list via `N8N_TRUSTED_PROXIES`) to avoid Express/XFF warnings and to make rate limiting work.
- SSH command node: workflow input is validated to prevent command injection (username alnum; password 8–64 chars, no quotes/backticks/spaces; display name limited charset). Keep these rules if you edit the workflow.
- Runner image: pinned to `n8nio/runners:2.2.6` to match n8n version and avoid unexpected upgrades.

## Task runner notes
- Queue mode is enabled; broker listens on `0.0.0.0:5679` in `n8n-worker`.
- For additional workers, add a runner sidecar per worker and point each `N8N_RUNNERS_TASK_BROKER_URI` to its paired worker.
- Default task request timeout remains 60s; adjust via `N8N_RUNNERS_TASK_REQUEST_TIMEOUT` if you add long-running code nodes.

## Troubleshooting
- Runner log stuck at “Waiting for task broker to be ready…” → check `N8N_RUNNERS_TASK_BROKER_URI` host/port and that broker listens on `0.0.0.0`.
- n8n log shows `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR` → ensure `N8N_PROXY_HOPS`/`N8N_TRUSTED_PROXIES` matches your reverse proxy hops.
- Credential errors after restart → verify `.env` matches the currently running secrets or switch to Docker secrets to avoid drift.
