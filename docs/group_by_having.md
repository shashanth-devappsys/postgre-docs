### **GROUP BY and HAVING**

The **`GROUP BY`** clause is used to arrange identical data into groups. It aggregates rows that have the same values into summary rows, like a count, average, or sum for each group.

The **`HAVING`** clause is used to filter those aggregated groups, similar to how `WHERE` filters individual rows. You use `HAVING` to apply conditions to the results of a `GROUP BY` operation.

Here's a practical example using your `t_dlpdata` table to find the average energy consumption for each meter.

**Example: Average Reading Per Meter**
This query groups all readings by `meter_id` and calculates the average `kwh_reading` for each group.

```sql
SELECT
    meter_id,
    AVG(kwh_reading) AS average_kwh
FROM
    t_dlpdata
GROUP BY
    meter_id;
```

**Example: Filtering Groups with `HAVING`**
This query builds on the previous one. It first groups the data by `meter_id`, then uses `HAVING` to only show the meters where the average reading is greater than 10 kWh.

```sql
SELECT
    meter_id,
    AVG(kwh_reading) AS average_kwh
FROM
    t_dlpdata
GROUP BY
    meter_id
HAVING
    AVG(kwh_reading) > 10;
```

-----

### **Window Functions**

Window functions perform calculations across a set of table rows that are related to the current row. Unlike `GROUP BY`, a window function doesn't collapse the rows; it simply adds a new column with the calculated value to each row in the result set. The key is the **`OVER()`** clause, which defines the "window" or set of rows the function operates on.

#### **`ROW_NUMBER()`**

**`ROW_NUMBER()`** assigns a unique, sequential integer to each row within a window, starting from 1. This is perfect for ranking or numbering rows based on a specific order.

**Example: Rank Meters by Join Date**
This query assigns a rank to each customer based on their `join_date`, with the newest customers ranked first.

```sql
SELECT
    customer_id,
    first_name,
    last_name,
    join_date,
    ROW_NUMBER() OVER (ORDER BY join_date DESC) AS rank
FROM
    m_customerinfo;
```

#### **`AVG() OVER()`**

You can use aggregate functions like `AVG`, `SUM`, `COUNT`, and `MIN`/`MAX` as window functions. `AVG() OVER()` calculates the average of a specific column for all rows in the defined window.

**Example: Compare Reading to Average**
This query is a great way to compare each individual `kwh_reading` against the overall average reading for a specific meter. It calculates the average reading for each `meter_id` and displays it on every row for that meter, without collapsing the data.

```sql
SELECT
    reading_timestamp,
    meter_id,
    kwh_reading,
    AVG(kwh_reading) OVER (PARTITION BY meter_id) AS average_kwh_for_meter
FROM
    t_dlpdata;
```

  * `PARTITION BY meter_id` divides the rows into groups (or partitions) based on the `meter_id`, so the average is calculated separately for each meter.

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