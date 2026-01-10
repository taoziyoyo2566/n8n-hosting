#!/usr/bin/env bash
set -euo pipefail

PGHOST="${POSTGRES_HOST:-postgres}"

until pg_isready -h "${PGHOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
  sleep 1
done

app_user_esc=$(printf "%s" "$POSTGRES_NON_ROOT_USER" | sed "s/'/''/g")
app_pass_esc=$(printf "%s" "$POSTGRES_NON_ROOT_PASSWORD" | sed "s/'/''/g")
db_name_esc=$(printf "%s" "$POSTGRES_DB" | sed "s/'/''/g")

psql -h "${PGHOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<EOSQL
DO \$do\$
DECLARE
  app_user text := '${app_user_esc}';
  app_pass text := '${app_pass_esc}';
  db_name text := '${db_name_esc}';
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = app_user) THEN
    EXECUTE format('CREATE USER %I WITH PASSWORD %L', app_user, app_pass);
  ELSE
    EXECUTE format('ALTER USER %I WITH PASSWORD %L', app_user, app_pass);
  END IF;
  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', db_name, app_user);
  EXECUTE format('GRANT CREATE ON SCHEMA public TO %I', app_user);
END
\$do\$;
EOSQL
