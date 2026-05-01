#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${ROOT_DIR}/.env.template"
ENV_PATH="${ROOT_DIR}/.env"

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "Template file not found: ${TEMPLATE_PATH}" >&2
  exit 1
fi

gen_secret() {
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
}

gen_encryption_key() {
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
}

# --- 交互式/参数处理 ---

# WEBHOOK_URL 处理
WEBHOOK_URL_VALUE="${1:-${WEBHOOK_URL:-}}"
if [[ -z "${WEBHOOK_URL_VALUE}" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Enter your WEBHOOK_URL (e.g., https://n8n.example.com/): " WEBHOOK_URL_VALUE
  fi
  if [[ -z "${WEBHOOK_URL_VALUE}" ]]; then
    WEBHOOK_URL_VALUE="https://n8n.example.com/"
    echo "Warning: No WEBHOOK_URL provided, using default: ${WEBHOOK_URL_VALUE}"
  fi
fi

# 确保 URL 以 / 结尾
[[ "${WEBHOOK_URL_VALUE}" != */ ]] && WEBHOOK_URL_VALUE="${WEBHOOK_URL_VALUE}/"

# TIMEZONE 处理
GENERIC_TIMEZONE_VALUE="${GENERIC_TIMEZONE:-$(cat /etc/timezone 2>/dev/null || echo "UTC")}"

# --- 密钥生成 ---
POSTGRES_PASSWORD_VALUE="${POSTGRES_PASSWORD:-$(gen_secret)}"
POSTGRES_NON_ROOT_PASSWORD_VALUE="${POSTGRES_NON_ROOT_PASSWORD:-$(gen_secret)}"
REDIS_PASSWORD_VALUE="${REDIS_PASSWORD:-$(gen_secret)}"
ENCRYPTION_KEY_VALUE="${ENCRYPTION_KEY:-$(gen_encryption_key)}"
N8N_RUNNERS_AUTH_TOKEN_VALUE="${N8N_RUNNERS_AUTH_TOKEN:-$(gen_secret)}"

export POSTGRES_PASSWORD_VALUE POSTGRES_NON_ROOT_PASSWORD_VALUE REDIS_PASSWORD_VALUE ENCRYPTION_KEY_VALUE N8N_RUNNERS_AUTH_TOKEN_VALUE WEBHOOK_URL_VALUE GENERIC_TIMEZONE_VALUE

if [[ -f "${ENV_PATH}" ]]; then
  if [[ "${OVERWRITE:-}" == "true" ]]; then
    :
  elif [[ -t 0 ]]; then
    read -r -p "${ENV_PATH} exists. Overwrite? [y/N] " answer
    if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi
  else
    echo "${ENV_PATH} exists. Re-run with OVERWRITE=true to replace it." >&2
    exit 1
  fi
fi

python3 - "${TEMPLATE_PATH}" "${ENV_PATH}" <<'PY'
import os
import sys

template_path, env_path = sys.argv[1], sys.argv[2]
template = open(template_path, "r", encoding="utf-8").read()

replacements = {
    "__POSTGRES_PASSWORD__": os.environ["POSTGRES_PASSWORD_VALUE"],
    "__POSTGRES_NON_ROOT_PASSWORD__": os.environ["POSTGRES_NON_ROOT_PASSWORD_VALUE"],
    "__REDIS_PASSWORD__": os.environ["REDIS_PASSWORD_VALUE"],
    "__ENCRYPTION_KEY__": os.environ["ENCRYPTION_KEY_VALUE"],
    "__N8N_RUNNERS_AUTH_TOKEN__": os.environ["N8N_RUNNERS_AUTH_TOKEN_VALUE"],
    "__WEBHOOK_URL__": os.environ["WEBHOOK_URL_VALUE"],
    "__GENERIC_TIMEZONE__": os.environ["GENERIC_TIMEZONE_VALUE"],
}

for placeholder, value in replacements.items():
    template = template.replace(placeholder, value)

with open(env_path, "w", encoding="utf-8") as fh:
    fh.write(template)
PY

echo "Wrote ${ENV_PATH}"
echo "------------------------------------------------"
echo "Configuration Summary:"
echo "  WEBHOOK_URL:      ${WEBHOOK_URL_VALUE}"
echo "  TIMEZONE:         ${GENERIC_TIMEZONE_VALUE}"
echo "------------------------------------------------"
echo "Next steps:"
echo "  1) Review ${ENV_PATH}"
echo "  2) docker compose up -d"
