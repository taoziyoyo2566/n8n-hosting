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
