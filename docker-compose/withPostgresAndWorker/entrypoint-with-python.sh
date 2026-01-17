#!/bin/sh
set -eu

# Ensure python venv exists inside the n8n data dir (persisted volume)
if [ ! -x /home/node/.n8n/python/bin/python3 ]; then
  mkdir -p /home/node/.n8n
  python3 -m venv /home/node/.n8n/python
fi

# Prioritize the venv's python/pip
export PATH="/home/node/.n8n/python/bin:${PATH}"

exec tini -- /docker-entrypoint.sh "$@"
