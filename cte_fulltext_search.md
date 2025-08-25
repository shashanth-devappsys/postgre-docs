## Advanced SQL Techniques

### 1. Common Table Expressions (CTEs) & Recursive Queries

A **Common Table Expression (CTE)** is a temporary, named result set defined within a `WITH` clause. It acts like a temporary table that exists only for the duration of a single query. CTEs make complex queries much more readable and manageable by breaking them down into logical, named parts.

**Example: CTE for Total Meter Readings**
Let's find the total energy consumption for each meter and then join that with the `m_meterinfo` table to get the meter's serial number.

```sql
WITH meter_totals AS (
    SELECT
        meter_id,
        SUM(kwh_reading) AS total_kwh
    FROM
        t_dlpdata
    GROUP BY
        meter_id
)
SELECT
    m.msn,
    m.install_date,
    mt.total_kwh
FROM
    meter_totals mt
JOIN
    m_meterinfo m ON mt.meter_id = m.meter_id;
```

  * The `meter_totals` CTE first aggregates the data.
  * The main `SELECT` statement then uses this CTE as if it were a regular table, making the final query much cleaner.

A **Recursive Query** is a type of CTE that can reference itself. This is used to query hierarchical or tree-like data structures, such as organizational charts, bill-of-materials, or, in a less common case for your tables, a chain of connected meters.

**Example: A Conceptual Recursive Query**
While your current schema isn't built for it, here’s how a recursive query works in principle, demonstrating a simple chain.

```sql
WITH RECURSIVE meter_chain AS (
    -- Anchor member: Starts the recursion with a specific meter
    SELECT
        meter_id,
        msn,
        1 AS level
    FROM
        m_meterinfo
    WHERE
        msn = 'MSN1001'

    UNION ALL

    -- Recursive member: Finds the "next" meter in the chain
    SELECT
        m.meter_id,
        m.msn,
        mc.level + 1
    FROM
        m_meterinfo m
    JOIN
        meter_chain mc ON m.meter_id = mc.meter_id + 1 -- A conceptual link
)
SELECT
    meter_id,
    msn,
    level
FROM
    meter_chain;
```

  * The "anchor" query selects the starting point (`MSN1001`).
  * The `UNION ALL` adds the "recursive" part, which joins the CTE to the main table to find the next item in the sequence. It continues this process until no more rows are found.

-----

### 2. Full-Text Search

**Full-Text Search** is a powerful feature for querying unstructured text data more intelligently than with simple `LIKE` statements. It handles nuances like stemming (e.g., searching for "running" also finds "run" and "ran") and ranking results by relevance.

In PostgreSQL, you use the `to_tsvector` function to convert text into a special searchable format and `to_tsquery` to create a search query. The `@@` operator then checks if the vector matches the query.

**Example: Searching for Customer Addresses**
Let's use the `address` field in `m_customerinfo` to find customers on "Main St" or "Park Ave."

```sql
SELECT
    customer_id,
    first_name,
    last_name,
    address
FROM
    m_customerinfo
WHERE
    to_tsvector('english', address) @@ to_tsquery('english', 'Main & (Street | Avenue)');
```

  * `to_tsvector` converts the `address` text into a tokenized vector.
  * `to_tsquery` parses the search string. The `&` symbol means "AND" and `|` means "OR."
  * This approach is far more robust and performant for text searches than using `LIKE '%Main Street%'`.

-----

### 3. JSONB Functions

The `JSONB` data type in PostgreSQL is an optimized way to store JSON data, allowing for efficient indexing and manipulation of semi-structured information. Your `metadata` column in `m_meterinfo` is a perfect use case for this.

**Example: Querying and Updating `JSONB` Data**
Let's assume your `metadata` column contains information like `{"manufacturer": "Acme Corp", "firmware_version": "1.2.3"}`.

**Querying `JSONB` Data**
You can use `->` to get a JSON object or array, and `->>` to get a text string. The `?` operator checks for the existence of a key.

```sql
-- Find meters from a specific manufacturer
SELECT
    msn,
    metadata ->> 'firmware_version' AS firmware
FROM
    m_meterinfo
WHERE
    metadata ->> 'manufacturer' = 'Acme Corp';

-- Find meters with a specific key in their metadata
SELECT
    msn
FROM
    m_meterinfo
WHERE
    metadata ? 'warranty_info';
```

**Updating `JSONB` Data**
You can update `JSONB` data using the `||` operator, which merges new key-value pairs into the existing JSON object.

```sql
-- Update the firmware version for a specific meter
UPDATE
    m_meterinfo
SET
    metadata = metadata || '{"firmware_version": "1.3.0"}'
WHERE
    msn = 'MSN1001';
```

This statement takes the existing `metadata` and merges in the new `firmware_version` key, overwriting the old value.