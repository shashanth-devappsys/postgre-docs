## Monitoring & Extensions Ecosystem in PostgreSQL

Below is a practical, copy-paste-ready tour of key monitoring views/tools and a popular extension, plus how to build/install your own.

---

## 1. `pg_stat_statements` — query-level performance profiling

### What it is

An extension that tracks **normalized** SQL (literals replaced by `$1`, `$2`, …) and aggregates counters: calls, total time, I/O, temp usage, shared/local blocks read/hit, and error counts. It’s the single most useful “what’s slow and why?” lens.

### Enable it

In `postgresql.conf` (requires restart):

```conf
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000           # how many distinct normalized queries to track
pg_stat_statements.track = top           # top | all | none
pg_stat_statements.save = on             # persist stats across restarts
```

Then:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Everyday queries

Top cumulative time:

```sql
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 20;
```

High average latency with few calls (great for targeted tuning):

```sql
SELECT query, calls, mean_time, rows
FROM pg_stat_statements
WHERE calls >= 10
ORDER BY mean_time DESC
LIMIT 20;
```

CPU vs. cache behavior (hits vs. reads):

```sql
SELECT query, calls,
       shared_blks_hit, shared_blks_read,
       ROUND(100.0*shared_blks_hit/GREATEST(shared_blks_hit+shared_blks_read,1),2) AS hit_pct
FROM pg_stat_statements
ORDER BY shared_blks_read DESC
LIMIT 20;
```

Temp file abusers (sort/hash spilling):

```sql
SELECT query, calls, temp_blks_written
FROM pg_stat_statements
ORDER BY temp_blks_written DESC
LIMIT 20;
```

Reset stats (e.g., before/after a change):

```sql
SELECT pg_stat_statements_reset();   -- superuser or owner of extension
```

### Example workflow (smart-meter dataset)

1. Find slow aggregation:

```sql
SELECT query, mean_time, calls
FROM pg_stat_statements
WHERE query ILIKE '%FROM trans.t_dlpdata%'
ORDER BY mean_time DESC
LIMIT 1;
```

2. EXPLAIN the normalized query with your actual parameters:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, date_trunc('day', ts) AS d, AVG(kwh)
FROM trans.t_dlpdata
WHERE ts >= now() - interval '30 days'
GROUP BY customer_id, d;
```

3. If it seq-scans billions of rows, create partitions and/or an index on `(ts)` (or `(customer_id, ts)`), then re-check `pg_stat_statements`.

---

## 2. `pg_stat_activity` — live session/process view

### What it is

A system view of **current** connections: backend PID, user, db, current query, state, wait events, locks, and when a statement started.

### Core queries

Active queries (long-running first):

```sql
SELECT pid, usename, datname, state, wait_event_type, wait_event,
       now() - query_start AS running_for,
       left(query, 120) AS query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start ASC;
```

Who’s blocking whom (lightweight lock insight):

```sql
-- Blocked PIDs (waiting) and their blockers
WITH locks AS (
  SELECT pid, locktype, mode, granted
  FROM pg_locks
),
pairs AS (
  SELECT w.pid AS waiting_pid, b.pid AS blocking_pid
  FROM pg_locks w
  JOIN pg_locks b
    ON w.locktype = b.locktype
   AND w.mode     = b.mode
   AND w.granted  = false
   AND b.granted  = true
)
SELECT a_wait.pid   AS waiting_pid,
       a_block.pid  AS blocking_pid,
       a_wait.query AS waiting_query,
       a_block.query AS blocking_query,
       a_block.state AS blocking_state
FROM pairs
JOIN pg_stat_activity a_wait ON a_wait.pid = pairs.waiting_pid
JOIN pg_stat_activity a_block ON a_block.pid = pairs.blocking_pid;
```

Gently cancel (asks the backend to abort current query):

```sql
SELECT pg_cancel_backend(<pid>);
```

Hard kill a backend (last resort; it drops the connection):

```sql
SELECT pg_terminate_backend(<pid>);
```

Spot idle-in-transaction (classic source of lock contention):

```sql
SELECT pid, usename, now()-xact_start AS xact_age, query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_start ASC;
```

---

## 3. Monitoring tools

### pgAdmin (GUI, built-in)

* **Pros:** Easy graphs for sessions, locks, I/O; explain visualizer; ad-hoc query tool; server-side dashboard.
* **Cons:** Not a time-series store; limited historical trends; desktop UI can be heavy.
* **Use it for:** Quick visibility, manual tuning sessions, explain plans, role/DDL management.

### pgwatch2 (time-series metrics + dashboards)

* **What it does:** Periodically scrapes dozens of views/functions into a TSDB (InfluxDB/TimescaleDB); ships with Grafana dashboards.
* **Strengths:** Historical trends, slow queries, bloat, vacuum/autovacuum, WAL, CPU/mem (via exporters).
* **Gotchas:** Requires a metrics DB and Grafana; choose sensible scrape intervals to avoid overhead.

**Minimal Docker Compose (self-contained stack):**

```yaml
version: "3.8"
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]

  pgwatch2:
    image: cybertec/pgwatch2:latest
    depends_on: [postgres]
    environment:
      PW2_TESTDB: "postgresql://postgres:postgres@postgres:5432/postgres"
    ports: ["8080:8080"]   # pgwatch2 web UI
    # Visit the UI, add your monitored DB with "autoconfig" to seed default metrics

  grafana:
    image: grafana/grafana:10.4.2
    ports: ["3000:3000"]
```

Once running, open pgwatch2 UI on `:8080`, add your DB with **autoconfig** (which creates a monitoring role and assigns a preset), then open Grafana on `:3000` and import pgwatch2 dashboards. Start with **"DB Overview"** and **"Top Queries"**.

**Operational tips**

* Start with 30–60s intervals for heavy views and 5–10s for cheap ones.
* Track vacuum/analyze, dead tuples, bloat, WAL volume, and temp file usage.
* Keep `pg_stat_statements` enabled; pgwatch2 can chart its metrics over time.

---

## 4. Popular extension: `pg_partman` — automated partition management

### Why use it

Time- or serial-based partitioning with **automatic creation**, **retention**, and **index template** management. Reduces table bloat, speeds up scans by pruning, and keeps maintenance lightweight.

### Install (package manager or source)

On Debian/Ubuntu (apt repository available via PGDG):

```bash
sudo apt-get install postgresql-16-partman
# or build from source if needed
```

Enable in the database:

```sql
CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
```

### Create a partitioned table (time-based, 1-day intervals)

Imagine smart-meter readings in `trans.t_dlpdata(customer_id INT, ts TIMESTAMPTZ, kwh NUMERIC, ... )`.

**Step 1: Create parent and configure partman**

```sql
-- Parent table (empty; will become the partitioned root)
CREATE TABLE trans.t_dlpdata_parent
(
  customer_id INT NOT NULL,
  ts          TIMESTAMPTZ NOT NULL,
  kwh         NUMERIC(12,4) NOT NULL,
  metadata    JSONB
);

-- Let partman manage it: time-based, daily
SELECT partman.create_parent(
    p_parent_table => 'trans.t_dlpdata_parent',
    p_control      => 'ts',
    p_type         => 'native',         -- native declarative partitions
    p_interval     => 'daily',
    p_start_partition => now()::date,   -- start today
    p_premake      => 7                 -- create 7 future partitions
);
```

**Step 2: Index templates (auto-applied to each child)**

```sql
-- Set default indexes for all future partitions:
INSERT INTO partman.part_config_sub
(parent_table, sub_partition_set, idxname, idxdef)
VALUES
('trans.t_dlpdata_parent', 0,
 't_dlpdata_ts_idx',
 'CREATE INDEX ON %_child_table_% (ts)'),
('trans.t_dlpdata_parent', 0,
 't_dlpdata_customer_ts_idx',
 'CREATE INDEX ON %_child_table_% (customer_id, ts)');
```

**Step 3: Move data**

* New inserts target `trans.t_dlpdata_parent`; partman routes to the correct child.
* For legacy data, use `partman.partition_data_proc('trans.t_dlpdata_parent')`.

**Partition pruning in action**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT AVG(kwh)
FROM trans.t_dlpdata_parent
WHERE ts >= date_trunc('day', now()) - interval '3 days';
```

You should see only the last few daily partitions scanned.

**Retention (automatic drop of old partitions)**

```sql
UPDATE partman.part_config
SET retention           = '90 days',
    retention_keep_table = false,      -- drop old partitions
    optimize_constraint  = true
WHERE parent_table = 'trans.t_dlpdata_parent';
```

**Maintenance scheduling**
Call regularly (cron/K8s job):

```sql
SELECT partman.run_maintenance();
```

Daily or hourly is typical. This creates future partitions and enforces retention.

**Notes**

* Foreign keys referencing a partitioned parent require PG 15+ care; often you FK to dimension tables (e.g., `m_customerinfo`) and not to the partitioned fact.
* Non-time partitioning (e.g., `customer_id` by hash/range) is supported via `p_type='native'` with `p_interval` numeric; time is simpler.

---

## 5. Installing custom extensions (from “hello” to production)

### A. SQL-only “extension” (no C code)

You can package views/functions into an extension for versioned deployment.

**Files (convention):**

* `myext.control`
* `sql/myext--1.0.sql`
* optional upgrade scripts: `sql/myext--1.0--1.1.sql`

**`myext.control`**

```conf
comment = 'My utilities: safety wrappers & views'
default_version = '1.0'
relocatable = true
schema = myext
requires = 'plpgsql'
```

**`sql/myext--1.0.sql`**

```sql
CREATE SCHEMA IF NOT EXISTS myext;

CREATE OR REPLACE FUNCTION myext.safe_avg(n NUMERIC[])
RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN
  RETURN CASE WHEN n IS NULL OR array_length(n,1) IS NULL THEN NULL
              ELSE (SELECT AVG(x) FROM unnest(n) AS t(x))
         END;
END$$;

CREATE OR REPLACE VIEW myext.top_waiters AS
SELECT pid, usename, wait_event_type, wait_event, query_start, query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;
```

**Install**

```sql
CREATE EXTENSION myext SCHEMA myext FROM '/path/to'; -- if in extension path
-- Typical install: copy files into PostgreSQL share/extension dir; then:
CREATE EXTENSION myext;  -- uses control + sql file automatically
```

### B. C extension (compiled)

When you need new SQL functions calling Postgres internals or fast math/string ops.

**Build skeleton (on server with PG dev headers):**

```bash
sudo apt-get install postgresql-server-dev-16 build-essential
# directory has mycext.c and Makefile
make
sudo make install
# then in psql:
CREATE EXTENSION mycext;
```

**Minimal `Makefile`**

```make
EXTENSION = mycext
MODULES = mycext
DATA = mycext--1.0.sql
PG_CONFIG = pg_config
OBJS = mycext.o
```

**Minimal `mycext.c`**

```c
#include "postgres.h"
#include "fmgr.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(hello_pg);

Datum hello_pg(PG_FUNCTION_ARGS) {
  PG_RETURN_TEXT_P(cstring_to_text("hello from C extension"));
}
```

**`mycext--1.0.sql`**

```sql
CREATE FUNCTION hello_pg() RETURNS text
AS 'MODULE_PATHNAME', 'hello_pg'
LANGUAGE C STRICT;
```

Now:

```sql
SELECT hello_pg(); -- "hello from C extension"
```

**Security & ops**

* Prefer SQL-only or trusted PLs for portability.
* For C code, lock down build chain, review for memory safety, test on staging, version upgrades with `ALTER EXTENSION ... UPDATE`.

---

## Operational playbook (quick wins)

1. **Turn on `pg_stat_statements`** and check top 20 by `total_time` and `mean_time`.
2. **Use `pg_stat_activity`** to catch idle-in-transaction and blockers; fix app code holding open transactions.
3. **Add pgwatch2** for trend lines (WAL, temp files, dead tuples, autovacuum timings).
4. **Partition big facts with `pg_partman`**, add retention, schedule `run_maintenance()`.
5. **Codify local utilities as an extension**, so your cluster setup is reproducible and versioned.

