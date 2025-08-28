## Backup & Restore

Here’s a guide to PostgreSQL logical backups using `pg_dump`, `pg_restore`, and formats, filters, roles/ACLs, parallelism, huge DBs, etc.

* **`pg_dump`** creates a *logical* backup of a single database (DDL+data). It **does not** back up cluster-wide objects like roles and tablespaces.
* **`pg_dumpall`** backs up **globals** (roles, tablespaces) and can also dump all databases if you ask.
* **Formats** matter:

  * **Plain SQL** (`-Fp`): human-readable, restore with `psql`. No parallel restore, but simplest.
  * **Custom** (`-Fc`): compressed, selective restore, **parallelizable** with `pg_restore`.
  * **Directory** (`-Fd`): a folder of files, best for **fast, parallel** dump/restore.
  * **Tar** (`-Ft`): single file tarball; selective restore possible, not parallel on restore.

---

# pg\_dump: essential recipes

## 1) Full database dump (all objects, data)

```bash
# Plain SQL
pg_dump -h localhost -p 5432 -U appuser -d appdb -Fp -f appdb.sql

# Custom format (recommended for production)
pg_dump -h localhost -p 5432 -U appuser -d appdb -Fc -f appdb.dump

# Directory format (best for big DBs + parallel restore)
pg_dump -h localhost -p 5432 -U appuser -d appdb -Fd -f appdb_dir --jobs=4
```

Notes:

* `pg_dump` runs in a single transaction snapshot for consistency (no partial rows).
* It takes **ACCESS SHARE** locks while reading-won’t block writers, but can be blocked by schema changes.

## 2) Schema-only or data-only

```bash
# Only DDL (no rows)
pg_dump -d appdb -Fc --schema-only -f appdb_schema.dump

# Only data (assumes objects already exist)
pg_dump -d appdb -Fc --data-only -f appdb_data.dump
```

## 3) Include / exclude specific schemas or tables

```bash
# Only two schemas
pg_dump -d appdb -Fc -n public -n analytics -f pick_schemas.dump

# Exclude a noisy schema
pg_dump -d appdb -Fc -N staging -f no_staging.dump

# Only these tables (repeat -t as needed; supports patterns)
pg_dump -d appdb -Fc -t public.orders -t public.customers -f two_tables.dump

# Exclude heavy table
pg_dump -d appdb -Fc -T public.event_log -f no_eventlog.dump
```

## 4) Large Objects (BLOBs)

By default, LO data is included. To be explicit:

```bash
pg_dump -d appdb -Fc --blobs -f appdb_with_blobs.dump
```

## 5) Ownership, privileges, and security filters

```bash
# Keep ownership/GRANTs exactly (default): best for same target cluster/users
pg_dump -d appdb -Fc -f appdb_exact.dump

# Strip owners (useful when restoring as a different user)
pg_dump -d appdb -Fc --no-owner -f appdb_no_owner.dump

# Strip privileges; let you GRANT later
pg_dump -d appdb -Fc --no-privileges -f appdb_no_acl.dump
```

## 6) Data format tweaks for tricky migrations

```bash
# INSERT per row (more portable, slower restores; good when constraints/order matter)
pg_dump -d appdb -Fc --column-inserts -f appdb_column_inserts.dump

# Disable triggers during restore (for data-only repl into existing schema)
pg_dump -d appdb -Fc --disable-triggers --data-only -f appdb_data_notrig.dump
```

## 7) Minimizing churn / managing load

```bash
# Use a consistent MVCC snapshot across multiple dumps (rare, advanced):
pg_dump -d appdb --snapshot='pg_export_snapshot()' ...   # invoked from same session

# Throttle I/O using pv or ionice (Linux) if needed
pg_dump -d appdb -Fc | pv > appdb.dump
```

---

# pg\_dumpall: globals and “dump everything”

## 1) Back up cluster-wide **globals** (roles, tablespaces)

```bash
pg_dumpall -h localhost -p 5432 -U postgres --globals-only > globals.sql
```

Run this **once per cluster** alongside your per-database dumps. This saves CREATE ROLE/ALTER ROLE and tablespaces.

## 2) Back up **all databases** (one big SQL)

```bash
pg_dumpall -h localhost -p 5432 -U postgres > all_databases.sql
```

- Pros: dead simple. 
- Cons: huge single SQL file, no parallel restore, all-or-nothing vibe. For big environments, prefer per-DB `pg_dump -Fc/-Fd` + `pg_dumpall --globals-only`.

---

# Restores

## Plain SQL (`-Fp`) → restore with psql

```bash
# Create target DB manually (or let the dump do it if it has CREATE DATABASE)
createdb -h localhost -U postgres appdb_new

# Apply dump
psql -h localhost -U postgres -d appdb_new -f appdb.sql
```

## Custom/Tar (`-Fc`/`-Ft`) → restore with pg\_restore

```bash
# Create empty DB (unless dump includes --create and you want it to create for you)
createdb -h localhost -U postgres appdb_new

# Full restore
pg_restore -h localhost -U postgres -d appdb_new appdb.dump
```

## Directory (`-Fd`) → restore with pg\_restore (parallel!)

```bash
createdb -h localhost -U postgres appdb_new
pg_restore -h localhost -U postgres -d appdb_new --jobs=4 appdb_dir
```

## Let the dump create and drop objects

```bash
# If dump was made with no --create, you can still ask pg_restore to:
pg_restore -h localhost -U postgres --create --clean --if-exists appdb.dump
# --clean drops objects before recreate; --if-exists avoids noisy errors
```

## Selective restore (specific schema/table)

```bash
# List contents of a dump
pg_restore -l appdb.dump | less

# Restore just one schema
pg_restore -d appdb_new -n analytics appdb.dump

# Restore specific table
pg_restore -d appdb_new -t public.customers appdb.dump
```

## Fixing owners/ACLs during restore

```bash
# Remap all objects to a target role
pg_restore -d appdb_new --no-owner --role=appuser appdb.dump

# Skip ACLs entirely and grant later
pg_restore -d appdb_new --no-privileges appdb.dump
```

## Sections: pre-data / data / post-data

Useful for phased restores or when DDL must be reviewed.

```bash
# Only create types/tables/etc.
pg_restore -d appdb_new --section=pre-data appdb.dump
# Only load rows
pg_restore -d appdb_new --section=data appdb.dump
# Only apply constraints, indexes, triggers
pg_restore -d appdb_new --section=post-data appdb.dump
```

---

# End-to-end, production-ish playbooks

## A) Nightly production backup (per-DB + globals), compressed & parallelizable

```bash
# ENV (use .pgpass instead of PGPASSWORD in CI/CD where possible)
export PGHOST=prod-db.internal
export PGPORT=5432
export PGUSER=backup
export PGDATABASE=appdb

# 1) Globals
pg_dumpall --globals-only > /backups/$(date +%F)_globals.sql

# 2) Database dump in directory format for speed
pg_dump -Fd -f /backups/$(date +%F)_appdb -j 8

# Optional: rotate & checksum
cd /backups && tar -cf $(date +%F)_appdb.tar $(date +%F)_appdb && sha256sum *.tar *.sql > SHA256SUMS
```

## B) Disaster recovery to a new server (same major version)

```bash
# 1) Restore globals (roles/tablespaces) first
psql -h new-host -U postgres -f 2025-08-28_globals.sql

# 2) Create DB (if your dump doesn’t have --create)
createdb -h new-host -U postgres appdb

# 3) Restore data with parallelism
pg_restore -h new-host -U postgres -d appdb -j 8 2025-08-28_appdb

# 4) Post-restore: ANALYZE for stats
psql -h new-host -U postgres -d appdb -c "VACUUM (ANALYZE);"
```

## C) Migrating only a subset of objects to a new schema or DB

```bash
# Dump just the needed parts
pg_dump -d appdb -Fc -n public -t public.customers -t public.orders -f cust_orders.dump

# Restore into a different schema name (create it first)
psql -d targetdb -c "CREATE SCHEMA staging;"
pg_restore -d targetdb --schema=staging --use-list <(pg_restore -l cust_orders.dump) cust_orders.dump
# (Alternative: use sed on the list file to remap schemas; for big rewrites, consider pg_restore --no-owner and search/replace in a plain SQL dump.)
```

---

# Performance & sizing notes

* **Dump time** \~ size of data scanned; **restore time** \~ constraints & indexes. Restoring many indexes is slow—consider:

  * Restore **pre-data**, then **data**, then **post-data** with `--jobs` to parallelize index builds.
  * On very large tables, temporarily **drop FKs** or defer constraints; let `post-data` add them after load.
* **Directory format + `-j`** on both dump and restore is the standard speed path.
* **Compression**: `-Fc` applies internal compression; for maximum reduction, you can still wrap in `lz4`/`zstd` at the file level, but restore must decompress first.

---

# Version compatibility & safety

* You can `pg_dump` from **old server → restore to newer** server reliably (forward-compatible). The reverse (new → old) is not guaranteed.
* Prefer using the **`pg_dump` from the target (newer) client version** against the old server when migrating “up.”
* For **major version upgrades**, `pg_upgrade` is faster than dump/restore, but dump/restore is the portability champ.

---

# Credentials & automation hygiene

* Use **`~/.pgpass`** to avoid interactive passwords:

  ```
  # hostname:port:database:username:password
  prod-db.internal:5432:appdb:backup:CorrectHorseBatteryStaple
  ```

  File must be `chmod 600`.
* Avoid hardcoding `PGPASSWORD` in scripts; use restricted service accounts.

---

# Quick verification checklist (don’t skip)

```sql
-- Object counts match?
SELECT schemaname, relkind, count(*) 
FROM pg_catalog.pg_class c 
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog','information_schema')
GROUP BY 1,2 ORDER BY 1,2;

-- Row counts for critical tables
SELECT 'customers', count(*) FROM customers
UNION ALL
SELECT 'orders', count(*) FROM orders;

-- Constraints/indexes present?
SELECT conname, contype, conrelid::regclass FROM pg_constraint WHERE contype IN ('p','f','u') ORDER BY 3,1;

-- Analyze after restore
VACUUM (ANALYZE);
```

---

# Common failure modes (and fast fixes)

* **“permission denied for schema X” on restore**
  Dump had owners you don’t have in target. Use `pg_restore --no-owner --role=target_role …` or create the missing roles first (restore `globals.sql`).
* **Foreign key violations during data-only restore**
  Load order matters. Use a `-Fc` dump and restore `--section=pre-data`, then `--section=data`, then `--section=post-data`. Or use `--disable-triggers` during data dump/restore (requires superuser).
* **Huge indexes make restore crawl**
  Use directory format + `pg_restore -j N`, or temporarily drop/skip some indexes and recreate after data load.
* **“could not execute query: ERROR: extension X missing”**
  Create required extensions before restore: `CREATE EXTENSION ...;` (list from `pg_restore -l`).

---

# Tiny cheat-sheet

```bash
# Fast, flexible backup
pg_dump -d appdb -Fd -f /backups/appdb_$(date +%F) --jobs=8
pg_dumpall --globals-only > /backups/globals_$(date +%F).sql

# Fast restore
createdb appdb_new
pg_restore -d appdb_new -j 8 /backups/appdb_2025-08-28
psql -d appdb_new -f /backups/globals_2025-08-28.sql  # if needed
```
