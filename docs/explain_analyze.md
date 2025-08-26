## Performance Optimization & Maintenance

Maintaining a high-performing PostgreSQL database is essential for any application, especially as your data grows. Here's the key performance optimization and maintenance techniques.

-----

### **1. `EXPLAIN` and `EXPLAIN ANALYZE`**

These commands are your most powerful tools for understanding how PostgreSQL executes a query. They help you pinpoint performance bottlenecks by showing you the **query plan**.

  * **`EXPLAIN`**: Shows the *estimated* query plan without running the query. It's a quick way to see how the database *thinks* it will retrieve data.
  * **`EXPLAIN ANALYZE`**: Runs the query and provides the *actual* execution plan, including real-world timing and row counts for each step. This is the best way to determine where a query is truly spending its time.

**Example**: To see the plan for a query that joins your tables, you'd run:

```sql
EXPLAIN ANALYZE
SELECT
    c.first_name,
    m.msn,
    d.kwh_reading
FROM
    m_customerinfo c
JOIN
    m_meterinfo m ON c.customer_id = m.customer_id
JOIN
    t_dlpdata d ON m.meter_id = d.meter_id
WHERE
    d.reading_timestamp > NOW() - INTERVAL '1 day';
```

The output will show you if the database is performing an expensive sequential scan or an efficient index scan, and help you decide if you need to add an index.

-----

### **2. `VACUUM` and `ANALYZE`**

PostgreSQL's **MVCC (Multi-Version Concurrency Control)** model means that `UPDATE` or `DELETE` operations don't immediately remove old data. Instead, they leave behind "dead tuples." These can bloat your tables and slow down queries.

  * **`VACUUM`**: Reclaims the space from dead tuples. It doesn't shrink the table file on disk but makes the space available for new data.
  * **`ANALYZE`**: Collects statistics about your table data. The query planner uses these statistics to create an efficient execution plan. Without up-to-date statistics, the planner might make bad decisions.
  * **`autovacuum`**: This is a background process that automatically runs `VACUUM` and `ANALYZE` for you. For most cases, relying on `autovacuum` is the best practice.

**Example**: While `autovacuum` handles most of this, you might need to run these commands manually after a large data import.

```sql
VACUUM t_dlpdata; -- Reclaims space in the readings table
ANALYZE t_dlpdata; -- Updates statistics for the query planner
```

-----

### **3. Table Partitioning**

For very large tables like `t_dlpdata`, which can contain billions of rows, **partitioning** is a game-changer. It involves splitting one large table into smaller, more manageable physical pieces called partitions. This is most effective when your queries typically only access a subset of the data.

  * For your `t_dlpdata` table, partitioning by `reading_timestamp` is an excellent strategy. This allows you to create separate partitions for each day, month, or year.
  * A query for a specific time range will then only need to scan the relevant partition, rather than the entire massive table.

**Example**: Creating a partitioned table and its partitions.

```sql
-- Create the master partitioned table
CREATE TABLE t_dlpdata_partitioned (
    reading_id BIGSERIAL,
    meter_id INT NOT NULL,
    reading_timestamp TIMESTAMPTZ NOT NULL,
    kwh_reading NUMERIC(10, 4) NOT NULL
) PARTITION BY RANGE (reading_timestamp);

-- Create a partition for January 2025 data
CREATE TABLE t_dlpdata_2025_01 PARTITION OF t_dlpdata_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Now, when you insert a record, it will automatically go to the correct partition
INSERT INTO t_dlpdata_partitioned (meter_id, reading_timestamp, kwh_reading)
VALUES (1, '2025-01-15 10:00:00+00', 123.45);
```

-----

### **4. Connection Pooling with PgBouncer**

Every time a client application connects to a PostgreSQL database, it creates a new server process, which can be resource-intensive. **Connection pooling** solves this by maintaining a set of ready-to-use database connections that applications can borrow and return.

  * **PgBouncer** is a lightweight, standalone application that sits between your application and your PostgreSQL server.
  * Instead of connecting to PostgreSQL directly, your application connects to PgBouncer, which then gives it a connection from its pool.
  * This greatly reduces the overhead of establishing new connections and allows your database to handle many more concurrent client requests.
