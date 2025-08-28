## Performance Optimization & Maintenance

Maintaining a high-performing PostgreSQL database is essential for any application, especially as your data grows. Here's the key performance optimization and maintenance techniques.

-----

### **1. `EXPLAIN` and `EXPLAIN ANALYZE`**

When you write a SQL query, PostgreSQL's query planner creates a plan to execute it in the most efficient way possible. The **`EXPLAIN`** and **`EXPLAIN ANALYZE`** commands are your primary tools for inspecting these plans, helping you identify and fix performance bottlenecks.

-----

### `EXPLAIN`

The `EXPLAIN` command shows you the **planner's intended execution plan** without actually running the query. It's a "dry run" that reveals the sequence of operations (e.g., table scans, joins, sorts) the planner believes will be fastest.

#### **How to Use:**

Simply add `EXPLAIN` before your SQL query.

```sql
EXPLAIN
SELECT *
FROM t_dlpdata
WHERE meter_id = 1234;
```

This command will not return any rows from your `t_dlpdata` table. Instead, it will output the query plan.

#### **Interpreting the Result:**

The result is a hierarchical tree of operations, read from the inside out (or bottom up). Each line represents a **node** in the plan.

  * **`->`**: The arrow indicates the flow of data. The inner operation feeds its results to the outer operation.
  * **`Node Type`**: The name of the operation, such as `Seq Scan` (sequential scan), `Index Scan` (using an index), `Hash Join`, `Merge Join`, or `Sort`.
  * **`cost`**: The estimated cost of the operation. The numbers are arbitrary but provide a relative measure of efficiency. The cost is represented as `(startup_cost..total_cost)`.
      * **`startup_cost`**: The cost to get the first row.
      * **`total_cost`**: The estimated total cost to retrieve all rows.
  * **`rows`**: The estimated number of rows the operation will process or produce.
  * **`width`**: The estimated average size of the rows in bytes.

**Example Plan Output:**

```
                                 QUERY PLAN
-----------------------------------------------------------------------------
 Seq Scan on t_dlpdata  (cost=0.00..18.50 rows=100 width=32)
   Filter: (meter_id = 1234)
```

**Meaning:** The planner expects to perform a **`Seq Scan`** (sequential scan) on the entire `t_dlpdata` table, then filter the results to find rows where `meter_id` equals `1234`. The estimated cost is `18.50` and it expects to find `100` matching rows.

-----

### `EXPLAIN ANALYZE`

**`EXPLAIN ANALYZE`** is much more powerful. It **actually executes the query** and then shows you the **actual execution plan**, including the real-world timings and row counts. This is invaluable for debugging why a query is slow, as it reveals discrepancies between what the planner *estimated* and what actually happened.

#### **How to Use:**

Prefix your query with `EXPLAIN ANALYZE`.

```sql
EXPLAIN ANALYZE
SELECT
    mi.first_name,
    mi.last_name,
    AVG(dlp.kwh_reading)
FROM
    m_customerinfo AS mi
JOIN
    m_meterinfo AS mm ON mi.customer_id = mm.customer_id
JOIN
    t_dlpdata AS dlp ON mm.meter_id = dlp.meter_id
GROUP BY
    mi.first_name, mi.last_name;
```

#### **Interpreting the Result:**

The output includes all the information from `EXPLAIN`, plus two new critical metrics for each node:

  * **`actual time`**: The real-world time the operation took, in milliseconds. It's displayed as `(start_time..end_time)`.
  * **`actual rows`**: The actual number of rows processed by the operation.

**Example Plan Output:**

```
                                            QUERY PLAN
----------------------------------------------------------------------------------------------------
 HashAggregate  (cost=438.25..438.30 rows=5 width=51) (actual time=14.508..14.509 rows=5 loops=1)
   Group Key: mi.first_name, mi.last_name
   ->  Hash Join  (cost=19.46..426.68 rows=2314 width=51) (actual time=2.001..12.315 rows=2314 loops=1)
         Hash Cond: (mm.customer_id = mi.customer_id)
         ->  Hash Join  (cost=0.00..381.87 rows=2314 width=40) (actual time=0.102..9.502 rows=2314 loops=1)
               Hash Cond: (dlp.meter_id = mm.meter_id)
               ->  Seq Scan on t_dlpdata dlp  (cost=0.00..281.42 rows=2314 width=12) (actual time=0.005..4.605 rows=2314 loops=1)
               ->  Hash  (cost=2.30..2.30 rows=130 width=32) (actual time=0.089..0.090 rows=130 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     ->  Seq Scan on m_meterinfo mm  (cost=0.00..2.30 rows=130 width=32) (actual time=0.007..0.045 rows=130 loops=1)
         ->  Hash  (cost=17.77..17.77 rows=777 width=27) (actual time=1.801..1.802 rows=777 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 32kB
               ->  Seq Scan on m_customerinfo mi  (cost=0.00..17.77 rows=777 width=27) (actual time=0.005..0.762 rows=777 loops=1)
 Planning Time: 0.320 ms
 Execution Time: 14.602 ms
```

**Meaning:** The plan shows a nested `Hash Join` to combine the three tables. We can see that the sequential scans (`Seq Scan`) are very fast, and the `Hash Join` operations take most of the time. The `actual rows` values match the estimates, indicating the planner's estimations were accurate. The total execution time was a quick `14.602 ms`.

### Common Performance Problems to Look For:

  * **`Seq Scan` on a large table with a `WHERE` clause**: The planner is scanning the whole table instead of using an index. This often indicates a missing index on the column in the `WHERE` clause.
  * **High `rows` estimate but low `actual rows`**: The planner's estimation is poor, which could lead to it choosing an inefficient plan. This is often due to stale statistics. Running `ANALYZE table_name` can fix this.
  * **Large `actual time` on a single node**: This points to the exact bottleneck in your query.
  * **Unexpected `Hash Join` or `Merge Join`**: Sometimes a simple `Index Scan` and `Nested Loop` join would be more efficient, especially for small result sets.

By carefully comparing the `EXPLAIN` plan (the estimate) with the `EXPLAIN ANALYZE` plan (the reality), you can pinpoint where your query is underperforming and make targeted improvements.

-----

### **2. `VACUUM` and `ANALYZE`**

The **`VACUUM`** and **`ANALYZE`** commands are essential for maintaining the health and performance of your PostgreSQL database. While they are often run together and have related purposes, they serve distinct functions.

-----

### `VACUUM`

The `VACUUM` command is primarily for **reclaiming storage space** and **freezing transaction IDs** to prevent database-wide issues. When you `DELETE` or `UPDATE` a row, PostgreSQL doesn't immediately remove the old version of the row. Instead, it marks it as "dead". These dead rows take up space and can lead to performance degradation.

#### **What it does:**

  * **Reclaims Space:** `VACUUM` scans tables for these "dead" tuples and marks their space as available for reuse. This prevents your database from bloating. It does not immediately return the space to the operating system; it makes it available for new data within the table.
  * **Prevents Transaction ID Wraparound:** PostgreSQL uses a 32-bit counter for transaction IDs. If this counter reaches its limit, the database can shut down to prevent data corruption. `VACUUM` helps to prevent this by "freezing" old transaction IDs, effectively resetting the counter for those rows.

#### **How to Use:**

```sql
VACUUM; -- Vacuums all tables in the current database.
VACUUM m_customerinfo; -- Vacuums a specific table.
VACUUM FULL m_customerinfo; -- A more aggressive form that reclaims space to the OS, but locks the table and is very slow. Use with caution.
```

A regular `VACUUM` is generally non-intrusive and can run concurrently with other operations. For a busy database, it's recommended to have **`autovacuum`** enabled, which runs in the background automatically.

-----

### `ANALYZE`

The **`ANALYZE`** command collects and updates **statistics** about the contents of a table. These statistics, such as the number of distinct values and the distribution of data, are used by the **query planner** to make informed decisions about the most efficient way to execute a query.

#### **What it does:**

  * **Updates Statistics:** It scans a table and populates the system catalogs with information about column data.
  * **Improves Query Plans:** The query planner uses these statistics to choose the best execution plan (e.g., whether to use an index scan or a sequential scan). Without up-to-date statistics, the planner might choose a poor, slow plan.

#### **How to Use:**

```sql
ANALYZE; -- Analyzes all tables in the database.
ANALYZE t_dlpdata; -- Analyzes a specific table.
-- `ANALYZE` does not affect the data or reclaim space. It's a quick, read-only operation.
```
---

### `VACUUM ANALYZE`

Because they are so closely related in purpose (maintaining database health and performance), **`VACUUM`** and **`ANALYZE`** are often run together. The `VACUUM ANALYZE` command performs both tasks in one go.

```sql
VACUUM ANALYZE; -- Vacuums and analyzes all tables.
VACUUM ANALYZE t_dlpdata; -- Vacuums and analyzes a specific table.
```

For most cases, a regular `VACUUM` in combination with `autovacuum` and an occasional `ANALYZE` is sufficient to maintain optimal database performance.

-----

### **3. Table Partitioning**

**Table partitioning** is a database technique that divides a large table into smaller, more manageable pieces called **partitions**. Each partition is a separate, physical table, but from the user's perspective, they all behave as a single logical table. This is extremely useful for improving query performance on very large tables and for simplifying data management tasks.

The main idea is that instead of having to scan a massive table, the database can quickly identify and scan only the relevant partitions, which are much smaller.

-----

### How it Works

PostgreSQL supports a few types of partitioning, but the most common are:

  * **Range Partitioning**: Partitions the table based on a range of values for a specific column (e.g., dates, numeric IDs). This is ideal for time-series data.
  * **List Partitioning**: Partitions the table based on a list of discrete values (e.g., country codes, regions).
  * **Hash Partitioning**: Partitions the table based on a hash of a column's value, which distributes rows evenly across partitions.

PostgreSQL's declarative partitioning makes this process very easy. You define the partitioning scheme on the main table, and the database handles the creation of the partitions and automatically routes data to the correct one.

-----

### Example: Range Partitioning Meter Readings

Given your `t_dlpdata` table, which is likely to grow very large over time, partitioning it by a date range is a great strategy. We'll partition it by month.

#### Step 1: Create the Main Partitioned Table

First, you define the main table. This table will not hold any data itself but will serve as the "parent" for all the partitions. We use `PARTITION BY RANGE` on the `reading_timestamp` column.

```sql
CREATE TABLE t_dlpdata (
    reading_id SERIAL,
    meter_id INT,
    reading_timestamp TIMESTAMP,
    kwh_reading NUMERIC,
    PRIMARY KEY (reading_id, reading_timestamp)
) PARTITION BY RANGE (reading_timestamp);
```

**Note:** The primary key must include the partitioning column (`reading_timestamp`).

#### Step 2: Create Partitions (Child Tables)

Next, you create the individual partitions for each month. The `FOR VALUES FROM...TO` clause specifies the date range for each partition.

```sql
-- Partition for readings in January 2024
CREATE TABLE t_dlpdata_2024_01 PARTITION OF t_dlpdata
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Partition for readings in February 2024
CREATE TABLE t_dlpdata_2024_02 PARTITION OF t_dlpdata
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- You can also create a default partition for data outside defined ranges
CREATE TABLE t_dlpdata_default PARTITION OF t_dlpdata DEFAULT;
```

Now, whenever you insert a new record into `t_dlpdata`, PostgreSQL automatically directs it to the correct partition based on its `reading_timestamp`.

#### Step 3: Querying the Partitioned Table

When you query the main `t_dlpdata` table, PostgreSQL's query planner is smart enough to perform **partition pruning**, meaning it only scans the partitions that are relevant to your query.

```sql
-- This query will only scan the t_dlpdata_2024_02 partition.
SELECT *
FROM t_dlpdata
WHERE reading_timestamp >= '2024-02-15' AND reading_timestamp < '2024-02-20';

-- The EXPLAIN command will confirm this.
EXPLAIN
SELECT *
FROM t_dlpdata
WHERE reading_timestamp >= '2024-02-15';
```

The output of the `EXPLAIN` will show that it only performed a scan on the `t_dlpdata_2024_02` partition, demonstrating the performance benefit.

-----

### **4. Connection Pooling with PgBouncer**

Every time a client application connects to a PostgreSQL database, it creates a new server process, which can be resource-intensive. **Connection pooling** solves this by maintaining a set of ready-to-use database connections that applications can borrow and return.

  * **PgBouncer** is a lightweight, standalone application that sits between your application and your PostgreSQL server.
  * Instead of connecting to PostgreSQL directly, your application connects to PgBouncer, which then gives it a connection from its pool.
  * This greatly reduces the overhead of establishing new connections and allows your database to handle many more concurrent client requests.
