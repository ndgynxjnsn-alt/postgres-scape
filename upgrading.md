# Moving an existing TimescaleDB container to this setup

You have a TimescaleDB container with data, its data volume mounted at `/var/lib/postgresql/data`, and no log
volume shared with Alloy. This guide replaces it with the `postgresdata` service from `docker-compose.yaml`
and keeps the data. The old container's logs are not carried over.

Both paths below were rehearsed on a copy of the setup (`timescale/timescaledb:2.24.0-pg18` with a
hypertable, a plain table and a role).

## What changes

| | Old container | `postgresdata` |
|---|---|---|
| Image | e.g. `lnf9s35w2/my-offline-timescale:pg18` | `postgres/Dockerfile`: `BASE_IMAGE` + pg_tracing |
| Data volume | mounted at `/var/lib/postgresql/data` | mounted at `/var/lib/postgresql`, `PGDATA` points into it |
| Configuration | `$PGDATA/postgresql.conf` | `config/postgres/postgresql.conf` (`config_file`); `$PGDATA/postgresql.conf` is **ignored** |
| `pg_hba.conf`, `postgresql.auto.conf` | `$PGDATA` | unchanged, still read from `$PGDATA` |
| Logs | stderr | JSON files in volume `postgreslogs`, read by the Alloy sidecar |
| Network | probably a Docker network, port published | **host network, `listen_addresses = 'localhost'`** |

Check the last row before you start. Clients in other containers that connect to the old container by its
name won't reach the new one. Either run them with `network_mode: host` too, or set `listen_addresses` to
an address they can reach.

## Background: where the data really is

The PG18 images contain a symlink `/var/lib/postgresql/data -> .`. Docker follows it, so a volume
"mounted at `/var/lib/postgresql/data`" ends up at `/var/lib/postgresql`. `docker inspect` still shows the
old path. The data directory is wherever `PGDATA` points inside that volume, for example `18/docker/`.

So **don't go by the mount path. Find the file `PG_VERSION` inside the volume** (step 1). Its directory is
the data directory. Never start a container on the volume with a guessed `PGDATA`. If the guess points to
an empty directory, the entrypoint runs `initdb` there and starts a new, empty cluster next to your data.

## 1. Inspect the old container

```bash
OLD=<old container name>

docker inspect "$OLD" --format 'image={{.Config.Image}}{{println}}{{range .Mounts}}{{.Type}} {{.Name}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
docker exec "$OLD" psql -U postgres -X -At -c 'SHOW server_version' -c 'SHOW data_directory' -c 'SHOW shared_preload_libraries'
docker exec "$OLD" id postgres
```

Find the data directory in each **named volume** listed above (`VOL` = the name). For a bind mount, run
`sudo find <source> -maxdepth 4 -name PG_VERSION` on the host instead.

```bash
VOL=<volume name>
docker run --rm -v "$VOL":/d:ro alpine sh -c 'for f in $(find /d -maxdepth 4 -name PG_VERSION); do echo "$f: $(cat $f)"; done'
# e.g.  /d/18/docker/PG_VERSION: 18   ->  data directory "18/docker", PostgreSQL 18
```

Write down the volume, the directory (`DATADIR`, relative to the volume, e.g. `18/docker`; empty if
`PG_VERSION` is at the top) and the major version. Then pick the path:

| `PG_VERSION` | uid of `postgres` (`id postgres`) | Path |
|---|---|---|
| 18 | 70 (TimescaleDB/Alpine images) | **A**: reuse the volume |
| 18 | 999 (Debian-based images) | **A**, with the ownership change in A.1 |
| 17 or older | any | **B**: dump and restore (the data files of another major version can't be opened) |

Two more checks:

* **Extensions.** Build the new image on the old image, so every extension of the old data is there in
  the same version: `BASE_IMAGE` in `postgres/Dockerfile`, or
  `docker compose build --build-arg BASE_IMAGE=<old image>`. Compare:
  ```bash
  docker exec "$OLD" psql -U postgres -X -At -d <db> -c "SELECT extname, extversion FROM pg_extension"
  ```
  The TimescaleDB version in the new image must be **the same or newer** (A), or **the same** (B).
* **Settings.** Everything the old server had in `$PGDATA/postgresql.conf` (e.g. timescaledb-tune's
  memory settings, `max_connections`) must go into `config/postgres/postgresql.conf`:
  ```bash
  docker exec "$OLD" psql -U postgres -X -At -c "SELECT name || ' = ' || quote_literal(setting) || coalesce(' -- ' || unit, '') FROM pg_settings WHERE source = 'configuration file' ORDER BY 1"
  ```
  `shared_preload_libraries` must include `timescaledb`. Keep `pg_stat_statements,pg_tracing` and add
  whatever else the old server preloaded.

## 2. Safety backup (pg_dump, on the Docker host)

Run it while the old container is still running:

```bash
scripts/pg-backup.sh "$OLD" /srv/pg-backups      # default target: ~/pg-backups
```

It writes `/srv/pg-backups/<container>-<timestamp>/`:

* `globals.sql`: roles and tablespaces.
* One `<db>.dump` per database (`pg_dump -Fc`). Each is read back with `pg_restore --list`.
* `inventory.txt`: versions, extensions and the exact row count of every table.
* `SHA256SUMS`.

The tools run inside the old container, so their version matches the server. With password
authentication: `PGPASSWORD=... scripts/pg-backup.sh ...`. TimescaleDB prints warnings about circular
foreign keys between hypertables and their chunks. These are expected, and the restore in B handles them.

Copy the directory off the host too if the data matters (`rsync -a /srv/pg-backups/... backup-host:`).
Check it with `cd <dir> && sha256sum -c SHA256SUMS`.

## 3. Stop the old container, and keep it

```bash
docker update --restart=no "$OLD"           # don't let Docker start it again
docker stop -t 120 "$OLD"                   # clean shutdown (checkpoint)
docker logs --tail 3 "$OLD"                 # last line: "database system is shut down"
docker rename "$OLD" "$OLD-retired"         # frees the name, keeps the container for a rollback
```

**Don't** use `docker rm -v`, `docker compose down -v` or `docker volume prune`. If the data sits in an
anonymous volume, these delete it. If the old container belongs to a compose project, use
`docker compose stop` there.

Path A only, optional: a file copy of the stopped volume restores faster than a dump.

```bash
docker run --rm -v "$VOL":/d:ro -v /srv/pg-backups:/b alpine tar -C /d -czf /b/"$VOL"-$(date +%F).tar.gz .
```

## 4A. Same major version: reuse the volume

**A.1, Debian-based old image (uid 999) only.** This image runs PostgreSQL as uid 70:

```bash
docker run --rm -v "$VOL":/d alpine chown -R 70:70 /d/"$DATADIR"
```

**A.2.** Next to `docker-compose.yaml`, create `docker-compose.override.yaml`, which Compose reads
automatically:

```yaml
services:
  postgresdata:
    environment:
      PGDATA: /var/lib/postgresql/18/docker   # /var/lib/postgresql/<DATADIR> from step 1

volumes:
  postgresdata:
    external: true
    name: <VOL>                               # the existing volume
```

For a bind mount instead of a named volume, replace the mount (Compose merges volume entries by their
target path) and leave out the `volumes:` block:

```yaml
services:
  postgresdata:
    environment:
      PGDATA: /var/lib/postgresql/<DATADIR>
    volumes:
      - /srv/old/pgdata:/var/lib/postgresql
```

The log volume `postgreslogs` is new. Docker copies the owner of the image's `/var/log/postgresql`
(postgres, uid 70, mode 0755) into it, so there's nothing to do. If you bind-mount a host directory for the
logs instead: `sudo install -d -o 70 -g 70 -m 0755 /srv/pglogs`.

**A.3. Start PostgreSQL only, and read the log.**

```bash
docker compose up -d --build postgresdata
docker compose logs postgresdata | head -20
```

You must see `Database directory appears to contain a database; Skipping initialization`.
**If you see `initdb` / `PostgreSQL init process complete` instead, stop the container immediately**
(`docker compose stop postgresdata`). `PGDATA` points to the wrong directory, and a new, empty cluster was
created there. Your data is untouched. Remove the new cluster directory, fix `PGDATA` and start again.

**A.4. Finish.**

```bash
P="docker exec -i postgresdata psql -U postgres -h localhost -X -v ON_ERROR_STOP=1"
# Extensions of the new setup (the init scripts only run on an empty data directory). Alloy connects to "postgres".
$P -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" -c "CREATE EXTENSION IF NOT EXISTS pg_tracing"
# Only if the new image has a newer TimescaleDB: in every database that uses it, as the first command of the session
$P -d <db> -c "ALTER EXTENSION timescaledb UPDATE"
```

Then continue with step 5.

## 4B. Different major version: dump and restore

The old volume stays untouched, which is also your rollback. `postgresdata` starts on its own empty
volume, without an override file.

```bash
B=/srv/pg-backups/<container>-<timestamp>      # from step 2
(cd "$B" && sha256sum -c SHA256SUMS)

docker compose up -d --build postgresdata      # new, empty cluster
R="docker exec -i postgresdata"

$R psql -U postgres -h localhost -X -q -d postgres < "$B/globals.sql"    # "role postgres already exists" is fine

for f in "$B"/*.dump; do
  db=$(basename "$f" .dump)
  [ "$db" = postgres ] || $R createdb -U postgres -h localhost "$db"
  $R psql -U postgres -h localhost -X -q -d "$db" -c "CREATE EXTENSION IF NOT EXISTS timescaledb" -c "SELECT timescaledb_pre_restore()"
  $R pg_restore -U postgres -h localhost -d "$db" < "$f"
  $R psql -U postgres -h localhost -X -q -d "$db" -c "SELECT timescaledb_post_restore()"
done
```

`timescaledb_pre_restore()` / `timescaledb_post_restore()` stop TimescaleDB's background jobs and
catalog triggers during the restore. Databases created with a different owner need
`createdb -O <owner>`. `globals.sql` has created the roles by then.

## 5. Verify, then start the rest

Take a second backup of the new server: it doubles as the first backup of the new setup. Then compare the
row counts:

```bash
scripts/pg-backup.sh postgresdata /srv/pg-backups
diff <(sed 1,3d /srv/pg-backups/<old>/inventory.txt) \
     <(sed 1,3d /srv/pg-backups/postgresdata-<timestamp>/inventory.txt)     # skips timestamp, version, data directory
```

No output means the same extensions and the same number of rows in every table. In path A, only the
extensions added in A.4 differ.

```bash
docker compose up -d      # Alloy sidecar, central stack, ...
```

The Alloy sidecar connects as `postgres:postgres` (`config/alloy/config.alloy`, `custom-metrics.alloy`).
`POSTGRES_PASSWORD` only applies to a new cluster, so put the real password (better: a monitoring user
with `pg_monitor`) there.

## Rollback

**A:**

```bash
docker compose stop postgresdata
# only if you ran A.1: give the files back to uid 999
docker run --rm -v "$VOL":/d alpine chown -R 999:999 /d/"$DATADIR"
docker rename "$OLD-retired" "$OLD" && docker update --restart=unless-stopped "$OLD" && docker start "$OLD"
```

If the files are damaged, unpack the tar copy from step 3 into an empty volume, or restore the dump as in 4B.

**B:** the old volume was never touched. Stop `postgresdata` and start the old container as above.

## Clean up, after a few days without problems

```bash
docker rm "$OLD-retired"            # without -v
docker volume rm <old volume>       # B only: in A, postgresdata uses it (keep docker-compose.override.yaml too)
```

Keep the dumps from step 2 according to your retention rules. They contain all the data.
