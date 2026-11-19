#!/usr/bin/env bash
# Logical safety backup of a running PostgreSQL/TimescaleDB container, written to the Docker host.
#
#   scripts/pg-backup.sh <container> [backup-root]        (default root: ~/pg-backups)
#
# Creates <backup-root>/<container>-<timestamp>/ with
#   globals.sql      roles and tablespaces              (pg_dumpall --globals-only)
#   <db>.dump        one file per database, custom format (pg_dump -Fc), checked with pg_restore --list
#   inventory.txt    server version, extensions per database, row counts per table (to compare after restore)
#   SHA256SUMS
# The tools inside the container are used, so their version always matches the server.
# Password: PGPASSWORD is passed into the container if set. Restore: see upgrading.md.
set -euo pipefail

container=${1:?usage: $0 <container> [backup-root]}
root=${2:-$HOME/pg-backups}
user=${PGUSER:-postgres}
dir="$root/$container-$(date +%Y%m%d-%H%M%S)"

run() { docker exec -i ${PGPASSWORD:+-e PGPASSWORD} "$container" "$@"; }
sql() { run psql -U "$user" -X -At -v ON_ERROR_STOP=1 "$@"; }

umask 077   # dumps contain all data
mkdir -p "$dir"
echo "Backup of $container -> $dir"

run pg_dumpall -U "$user" --globals-only > "$dir/globals.sql"

mapfile -t dbs < <(sql -d postgres -c "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1")
{
  echo "# $(date -Is)  container=$container"
  sql -d postgres -c "SELECT version()"
  sql -d postgres -c "SHOW data_directory"
} > "$dir/inventory.txt"

for db in "${dbs[@]}"; do
  echo "  $db"
  # TimescaleDB prints warnings about circular foreign keys between hypertables and chunks: expected
  run pg_dump -U "$user" -Fc -d "$db" > "$dir/$db.dump"
  run pg_restore --list < "$dir/$db.dump" > /dev/null   # fails if the file is truncated or not a dump
  {
    echo; echo "## database $db: extensions"
    sql -d "$db" -c "SELECT extname, extversion FROM pg_extension ORDER BY 1"
    echo "## database $db: rows per table (exact)"
    sql -d "$db" -c "
      SELECT format('%s.%s %s', n.nspname, c.relname,
             (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM %I.%I', n.nspname, c.relname), false, true, '')))[1]::text)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        AND n.nspname NOT LIKE '\_timescaledb%' AND n.nspname NOT LIKE 'pg\_toast%'
      ORDER BY 1"
  } >> "$dir/inventory.txt"
done

(cd "$dir" && sha256sum -- * > SHA256SUMS)
ls -lh "$dir"
echo "OK: $dir"
