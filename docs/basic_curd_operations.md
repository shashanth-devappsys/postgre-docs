## Basic SQL Operations in PostgreSQL

This document covers fundamental SQL operations for creating, reading, updating, and deleting data (CRUD), along with different types of joins, all with examples from your smart meter dataset.

---

### 1. INSERT (Create New Records)
The `INSERT` statement adds new rows of data to a table.

```sql
-- Insert a new meter record
INSERT INTO master.m_meterinfo (meter_id, msn, ip_address, install_date, location)
VALUES (gen_random_uuid(), 'MSN1001', '192.168.1.10', '2025-01-01', 'Zone A');

-- Insert a new reading
INSERT INTO trans.t_dlpdata (meter_id, timestamp, reading_kwh)
VALUES ('<uuid-of-meter>', '2025-08-25 10:00:00', 2.45);
```

---

### 2. SELECT (Read Data)

The `SELECT` statement retrieves data from a table. You can specify which columns to retrieve (`*` for all) and use clauses like `ORDER BY` to sort results and `LIMIT` to restrict the number of rows.

```sql
-- Select all meters
SELECT * FROM master.m_meterinfo;

-- Select specific meter details
SELECT msn, location, install_date FROM master.m_meterinfo;

-- Select the 10 most recent readings
SELECT meter_id, timestamp, reading_kwh
FROM trans.t_dlpdata
ORDER BY timestamp DESC
LIMIT 10;
```

---

### 3. UPDATE (Modify Existing Records)

The `UPDATE` statement modifies existing rows. Always use a `WHERE` clause to specify which rows to change to avoid updating the entire table.

```sql
-- Update a meter's IP address
UPDATE master.m_meterinfo
SET ip_address = '192.168.1.20'
WHERE msn = 'MSN1001';

-- Mark old meters as inactive
UPDATE master.m_meterinfo
SET is_active = false
WHERE install_date < '2020-01-01';
```

---

### 4. DELETE (Remove Records)

The `DELETE` statement removes rows from a table. Just like `UPDATE`, always use a `WHERE` clause to avoid deleting all data.

```sql
-- Delete readings older than 30 days
DELETE FROM trans.t_dlpdata
WHERE timestamp < NOW() - INTERVAL '30 days';

-- Delete a specific meter
DELETE FROM master.m_meterinfo
WHERE msn = 'MSN1001';
```

---

### 5. Filtering with WHERE

The `WHERE` clause filters rows based on a specific condition.

```sql
-- Find active meters in Zone A
SELECT * FROM master.m_meterinfo
WHERE location = 'Zone A' AND is_active = true;

-- Find readings above a threshold
SELECT * FROM trans.t_dlpdata
WHERE reading_kwh > 4.5;
```

---

### 6. Sorting with ORDER BY

The `ORDER BY` clause sorts the results in ascending (`ASC`, default) or descending (`DESC`) order.

```sql
-- Sort meters by install date
SELECT msn, install_date
FROM master.m_meterinfo
ORDER BY install_date ASC;

-- Sort readings (latest first)
SELECT meter_id, timestamp, reading_kwh
FROM trans.t_dlpdata
ORDER BY timestamp DESC;
```

---

### 7. JOINs

`JOIN`s combine data from multiple tables based on a related column.

#### INNER JOIN (Matching Rows Only)

Returns rows only when there is a match in both tables.

```sql
SELECT m.msn, m.location, d.timestamp, d.reading_kwh
FROM master.m_meterinfo m
INNER JOIN trans.t_dlpdata d
  ON m.meter_id = d.meter_id
WHERE d.timestamp >= CURRENT_DATE - INTERVAL '1 day';
```

Result: Only meters with recent readings are shown.

---

#### LEFT JOIN (All from Left, Even if No Match)

Returns all rows from the left table and matching rows from the right. If no match, right-table columns are `NULL`.

```sql
SELECT m.msn, m.location, d.timestamp, d.reading_kwh
FROM master.m_meterinfo m
LEFT JOIN trans.t_dlpdata d
  ON m.meter_id = d.meter_id
  AND d.timestamp >= CURRENT_DATE - INTERVAL '1 day';
```

Result: All meters are returned. Meters without recent readings show NULL.

---

#### RIGHT JOIN (All from Right, Even if No Match)

Returns all rows from the right table and matching rows from the left. If no match, left-table columns are `NULL`.

```sql
SELECT m.msn, d.timestamp, d.reading_kwh
FROM master.m_meterinfo m
RIGHT JOIN trans.t_dlpdata d
  ON m.meter_id = d.meter_id;
```

Result: All readings are returned. Readings without a matching meter show NULL.

---

#### FULL OUTER JOIN (All Rows from Both Sides)

Returns all rows from both tables, filling in `NULL` for unmatched columns.

```sql
SELECT m.msn, d.timestamp, d.reading_kwh
FROM master.m_meterinfo m
FULL OUTER JOIN trans.t_dlpdata d
  ON m.meter_id = d.meter_id;
```

Result: A complete list of all meters and all readings, regardless of a match.