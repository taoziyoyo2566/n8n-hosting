#!/usr/bin/env bash
set -euo pipefail

# --- 配置 ---
PGHOST="${POSTGRES_HOST:-postgres}"
# 使用 POSTGRES_USER 作为管理账户，如果环境变量未定义则默认为 'postgres'
ADMIN_USER="${POSTGRES_USER:-postgres}"
# 管理账户密码由 PGPASSWORD 环境变量提供 (在 docker-compose 中已定义)

echo "Waiting for PostgreSQL at ${PGHOST} to be ready..."
until pg_isready -h "${PGHOST}" -U "${ADMIN_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
  sleep 1
done

echo "PostgreSQL is ready. Starting initialization..."

# 变量转义处理
app_user_esc=$(printf "%s" "$POSTGRES_NON_ROOT_USER" | sed "s/'/''/g")
app_pass_esc=$(printf "%s" "$POSTGRES_NON_ROOT_PASSWORD" | sed "s/'/''/g")
db_name_esc=$(printf "%s" "$POSTGRES_DB" | sed "s/'/''/g")

# 执行初始化逻辑
# 使用 -v ON_ERROR_STOP=1 确保出错时立即停止
psql -h "${PGHOST}" -U "${ADMIN_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<EOSQL
DO \$do\$
DECLARE
  app_user text := '${app_user_esc}';
  app_pass text := '${app_pass_esc}';
  db_name text := '${db_name_esc}';
BEGIN
  -- 1. 处理应用用户
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = app_user) THEN
    EXECUTE format('CREATE USER %I WITH PASSWORD %L', app_user, app_pass);
    RAISE NOTICE 'Created user %', app_user;
  ELSE
    EXECUTE format('ALTER USER %I WITH PASSWORD %L', app_user, app_pass);
    RAISE NOTICE 'Updated password for user %', app_user;
  END IF;

  -- 2. 处理数据库权限
  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', db_name, app_user);
  
  -- 3. 处理公共模式权限 (适用于新版 Postgres)
  EXECUTE format('GRANT CREATE ON SCHEMA public TO %I', app_user);
  
  RAISE NOTICE 'Initialization completed for database %', db_name;
END
\$do\$;
EOSQL

echo "Database initialization script finished successfully."
