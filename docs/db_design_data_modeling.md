## 1. Schemas & Tables (Master and Transactional)

### What is a Schema?

A schema is a logical container for database objects like tables, views, indexes, and stored procedures. It's essentially a blueprint or a way to organize and group related objects within a single database. Think of a schema as a folder that holds files, where the database is the entire computer and the files are the tables. This allows for better organization, security, and management.

* Example: `master` schema for metadata, `trans` schema for transactional data.

```sql
-- Create schemas
CREATE SCHEMA master;
CREATE SCHEMA trans;
```

### What is a Table?

A table is a collection of related data organized in a structured format with rows and columns. It's the most basic unit for storing data in a relational database. Each row represents a single record, and each column represents a specific attribute of that record.

### Master Tables

Master tables contain relatively static, descriptive data about the entities in your business. This data is the "who, what, and where." It acts as a reference for the transaction tables and changes infrequently. When it does change, it's typically an update to an existing record, not a new record.

* Example: Meter information.

```sql
CREATE TABLE master.m_meterinfo (
    meter_id UUID PRIMARY KEY,
    msn TEXT UNIQUE,
    ip_address INET,
    install_date DATE,
    location TEXT,
    is_active BOOLEAN DEFAULT TRUE
);
```

### Transaction Tables

Transactional tables store dynamic, event-based data that is created frequently and continuously. They capture the "when and how much" of business activities. Each row represents a single event or transaction, often containing foreign keys that link back to the master table.

* Example: Smart meter readings.

```sql
CREATE TABLE trans.t_dlpdata (
    id BIGSERIAL PRIMARY KEY,
    meter_id UUID REFERENCES master.m_meterinfo(meter_id),
    timestamp TIMESTAMP NOT NULL,
    reading_kwh NUMERIC(10,2) NOT NULL
);
```

**Master–Transaction relationship:**

* `master.m_meterinfo` defines **what the meter is**.
* `trans.t_dlpdata` defines **what the meter records over time**.

---

## 2. Master vs. Transaction Tables

| Feature     | Master Table (`m_meterinfo`) | Transaction Table (`t_dlpdata`)       |
| ----------- | ---------------------------- | ------------------------------------- |
| **Purpose** | Stores metadata / reference  | Stores real-time or historical events |
| **Size**    | Small, limited rows          | Large, grows continuously             |
| **Changes** | Occasional updates           | Frequent inserts, deletes, updates    |
| **Usage**   | Lookup, joins                | Reporting, analytics, history         |

**Example Query (Join Master & Transaction):**

```sql
SELECT m.msn, m.location, d.timestamp, d.reading_kwh
FROM master.m_meterinfo m
JOIN trans.t_dlpdata d ON m.meter_id = d.meter_id
WHERE m.is_active = true
  AND d.timestamp >= CURRENT_DATE - INTERVAL '7 days';
```

---

## 3. Indexing (Single-column & Composite)

In a database, an index is a data structure that speeds up data retrieval operations. It works like a table of contents in a book, allowing the database to quickly find specific data without having to scan every single row of a table.

They’re like **book indexes** – instead of reading all pages, you jump directly to the right one.

### 🔹 Single-column Index

A single-column index is an index created on just one column of a table. It's useful when your queries frequently search, filter, or sort data based on that specific column.

```sql
-- Search faster by meter_id
CREATE INDEX idx_dlp_meterid ON trans.t_dlpdata(meter_id);

-- Search faster by timestamp
CREATE INDEX idx_dlp_timestamp ON trans.t_dlpdata(timestamp);
```

Helps when queries use `WHERE meter_id = ...` or `WHERE timestamp BETWEEN ...`.

---

### 🔹 Composite Index

A composite index (also known as a multi-column index) is an index created on two or more columns of a table. It is most effective when your queries frequently filter or sort data based on a combination of those columns. The order of the columns in a composite index is crucial, as the index can only be used for searches that begin with the first column (the "leftmost prefix").

```sql
-- Optimize queries filtering by meter_id + timestamp
CREATE INDEX idx_dlp_meterid_ts
ON trans.t_dlpdata(meter_id, timestamp);
```

Helps queries like:

```sql
SELECT * 
FROM trans.t_dlpdata
WHERE meter_id = 'uuid-here' 
  AND timestamp BETWEEN '2025-08-01' AND '2025-08-10';
```

**Rule of Thumb:**

* If you filter on one column → Single-column index.
* If you filter **often** on two or more columns → Composite index.
* Don’t overuse indexes → slows down inserts/updates.