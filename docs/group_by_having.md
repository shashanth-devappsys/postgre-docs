### **GROUP BY and HAVING**

The **`GROUP BY`** and **`HAVING`** clauses are used to summarize and filter data in a way that goes beyond simple row-by-row operations. They are always used with **aggregate functions** like `SUM()`, `COUNT()`, `AVG()`, `MIN()`, and `MAX()`.

-----

### The `GROUP BY` Command

The **`GROUP BY`** clause organizes rows with identical values into summary groups. It's the first step in performing calculations on these groups, rather than on individual records.

**Example 1: Find the total energy consumption for each meter.**

This is the most direct use of `GROUP BY`. By grouping by `meter_id`, you can calculate the total `kwh_reading` for each specific meter from the `t_dlpdata` table.

```sql
SELECT
    meter_id,
    SUM(kwh_reading) AS total_kwh
FROM
    t_dlpdata
GROUP BY
    meter_id;
```

This query returns a single row for each unique `meter_id`, showing its total consumption.

**Example 2: Find the total energy consumption for each customer.**

To get a summary for each customer instead of each meter, you need to join the `t_dlpdata` and `m_meterinfo` tables, and then group by `customer_id`.

```sql
SELECT
    mi.customer_id,
    SUM(dlp.kwh_reading) AS total_kwh
FROM
    t_dlpdata AS dlp
JOIN
    m_meterinfo AS mi ON dlp.meter_id = mi.meter_id
GROUP BY
    mi.customer_id;
```

This query first links meter readings to their respective customers, then groups the results by `customer_id` to calculate each customer's total consumption.

-----

### The `HAVING` Command

The **`HAVING`** clause is used to filter the groups created by `GROUP BY`. While `WHERE` filters individual rows *before* grouping, `HAVING` filters the summary rows *after* the grouping and aggregation have occurred. You can't use an aggregate function directly in a `WHERE` clause.

**Example: Find customers with high energy consumption.**

Building on the previous example, what if you only want to see the customers whose total energy consumption is over a certain amount? This is a perfect use case for `HAVING`.

```sql
SELECT
    mi.customer_id,
    SUM(dlp.kwh_reading) AS total_kwh
FROM
    t_dlpdata AS dlp
JOIN
    m_meterinfo AS mi ON dlp.meter_id = mi.meter_id
GROUP BY
    mi.customer_id
HAVING
    SUM(dlp.kwh_reading) > 50000;
```

This query first calculates the total consumption for every customer, and then the `HAVING` clause filters the results to only include customers whose total consumption (`SUM(dlp.kwh_reading)`) is greater than 50,000 kWh.

-----

### **Window Functions**

**Window functions** in PostgreSQL perform calculations across a set of table rows that are related to the current row. Unlike aggregate functions (`SUM`, `COUNT`) which collapse rows into a single summary row, window functions retain the individual rows in the output. They "look through" a specified "window" of data to perform their calculations.

The syntax for a window function is `function_name() OVER ([PARTITION BY ...] [ORDER BY ...])`.

  * **`PARTITION BY`**: This clause divides the rows into smaller groups or partitions, similar to how `GROUP BY` works. The window function is then applied to each partition independently.
  * **`ORDER BY`**: This clause defines the order of the rows within each partition. This is crucial for functions like `ROW_NUMBER()` and for calculating running totals.

-----

### `ROW_NUMBER()`

The **`ROW_NUMBER()`** window function assigns a unique, sequential integer to each row within its partition, starting from 1. The numbering is based on the `ORDER BY` clause. This is incredibly useful for ranking or finding the "Nth" row.

**Example: Find the most recent meter reading for each meter.**

We can use `ROW_NUMBER()` to assign a rank to each meter reading based on its timestamp, partitioned by `meter_id`. The row with rank 1 will be the most recent reading for each meter.

```sql
SELECT
    reading_id,
    meter_id,
    reading_timestamp,
    kwh_reading,
    ROW_NUMBER() OVER(PARTITION BY meter_id ORDER BY reading_timestamp DESC) as rn
FROM
    t_dlpdata;
```

To get only the most recent reading, you can wrap this query in a subquery:

```sql
SELECT
    reading_id,
    meter_id,
    reading_timestamp,
    kwh_reading
FROM (
    SELECT
        reading_id,
        meter_id,
        reading_timestamp,
        kwh_reading,
        ROW_NUMBER() OVER(PARTITION BY meter_id ORDER BY reading_timestamp DESC) as rn
    FROM
        t_dlpdata
) AS ranked_readings
WHERE
    rn = 1;
```

-----

### `AVG() OVER()`

You can use aggregate functions like `AVG()`, `SUM()`, and `COUNT()` as window functions by adding the `OVER` clause. This allows you to calculate an average, total, or count for a group of rows without collapsing the result set.

**Example: Compare each meter's reading to its average.**

This query uses `AVG()` as a window function to calculate the average `kwh_reading` for each `meter_id`. The result includes the individual reading and the overall average for that meter on the same row, which is not possible with a simple `GROUP BY`.

```sql
SELECT
    reading_id,
    meter_id,
    reading_timestamp,
    kwh_reading,
    AVG(kwh_reading) OVER(PARTITION BY meter_id) AS average_kwh_for_meter
FROM
    t_dlpdata;
```

This is especially useful for quickly identifying readings that are significantly higher or lower than the average for that specific meter.

**Example 2: Find the running total of a customer's consumption.**

You can use `AVG() OVER()` without a `PARTITION BY` clause to get an average across the entire dataset. However, a more powerful application is using `ORDER BY` within a partition to calculate running totals or moving averages.

```sql
SELECT
    dlp.reading_id,
    mi.customer_id,
    dlp.reading_timestamp,
    dlp.kwh_reading,
    SUM(dlp.kwh_reading) OVER (
        PARTITION BY mi.customer_id
        ORDER BY dlp.reading_timestamp
    ) AS running_total_kwh
FROM
    t_dlpdata AS dlp
JOIN
    m_meterinfo AS mi ON dlp.meter_id = mi.meter_id
ORDER BY
    mi.customer_id, dlp.reading_timestamp;
```

This query first partitions the data by `customer_id` and then, for each customer, calculates a running `SUM` of `kwh_reading`s ordered by `reading_timestamp`. This lets you see how a customer's total consumption grows over time.

-----

### **Views & Materialized Views**

A **`VIEW`** is a virtual table that is created by a query. It does not store data itself; instead, it's a saved SQL statement that you can query as if it were a real table. Views are useful for simplifying complex queries, restricting data access, and creating a consistent interface for your data.

**Example: A "Meters with Readings" View**
This view joins the `m_meterinfo` and `t_dlpdata` tables to create a simple, reusable object for finding all meters that have at least one reading.

```sql
CREATE VIEW active_meters_with_readings AS
SELECT
    m.msn,
    m.install_date,
    d.reading_timestamp,
    d.kwh_reading
FROM
    master.m_meterinfo m
JOIN
    trans.t_dlpdata d ON m.meter_id = d.meter_id;
```

You can now query this view just like a regular table:

```sql
SELECT msn, reading_timestamp FROM active_meters_with_readings WHERE msn = 'MSN1001';
```

A **`MATERIALIZED VIEW`** is similar to a view, but it actually **stores the data on disk**. The results of the query are pre-calculated and saved, which makes querying the view much faster. However, the data in a materialized view is not real-time; you must manually or automatically `REFRESH` it to get the latest data.

**Example: A "Meter Summary" Materialized View**
This materialized view stores a pre-calculated summary of each meter's total consumption, which can be queried instantly without recalculating the sum every time.

```sql
CREATE MATERIALIZED VIEW meter_monthly_summary AS
SELECT
    meter_id,
    EXTRACT(YEAR FROM reading_timestamp) AS reading_year,
    EXTRACT(MONTH FROM reading_timestamp) AS reading_month,
    SUM(kwh_reading) AS total_kwh
FROM
    t_dlpdata
GROUP BY
    meter_id, reading_year, reading_month;
```

To update the data in this view:

```sql
REFRESH MATERIALIZED VIEW meter_monthly_summary;
```