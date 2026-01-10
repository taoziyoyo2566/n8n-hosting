# n8n with PostgreSQL and Worker

Starts n8n with PostgreSQL as database, and the Worker as a separate container.

## Start

To start n8n simply start docker-compose by executing the following
command in the current folder.

**IMPORTANT:** Create a real `.env` from the template before starting:

```
./generate-env.sh          # generates .env with random secrets
docker compose up -d       # start the stack
```

To stop it execute:

```
docker compose stop
```

## Configuration

Edit the generated [`.env`](.env) file to change database user/password, Redis password, encryption key, timezone, etc. The template lives in [`.env.template`](.env.template).
