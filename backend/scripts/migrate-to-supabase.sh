#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load DATABASE_* from .env (values with spaces must be quoted in .env)
while IFS='=' read -r key value; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  case "$key" in
    DATABASE_*) export "$key=$value" ;;
  esac
done < .env

if [[ -z "${DATABASE_HOST:-}" ]]; then
  echo "DATABASE_HOST is not set in .env"
  exit 1
fi

echo "==> 1/3 Export local verra_dev (schema + data)"
unset PGSSLMODE
pg_dump -h localhost -U gapple -d verra_dev \
  --schema=public \
  --no-owner \
  --no-privileges \
  -f verra_supabase_migration.sql

echo "==> 2/3 Test Supabase connection"
export PGPASSWORD="${DATABASE_PASSWORD}"
export PGSSLMODE=require
psql -h "$DATABASE_HOST" -p "${DATABASE_PORT:-5432}" \
  -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c "SELECT 1 AS connected;"

echo "==> 3/3 Import into Supabase"
psql -h "$DATABASE_HOST" -p "${DATABASE_PORT:-5432}" \
  -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" \
  -f verra_supabase_migration.sql

echo "Done. Verify row counts:"
psql -h "$DATABASE_HOST" -p "${DATABASE_PORT:-5432}" \
  -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" -c \
  "SELECT 'users' AS t, COUNT(*) FROM users
   UNION ALL SELECT 'clients', COUNT(*) FROM clients
   UNION ALL SELECT 'sessions', COUNT(*) FROM sessions;"
