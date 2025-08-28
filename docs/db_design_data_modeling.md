## 1. Schemas & Tables (Master and Transactional)

In a PostgreSQL database, schemas and tables are the primary organizational units for data. Think of a database as a large building, a schema as a specific floor or department within that building, and a table as a filing cabinet within that department.

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

In database design, **master tables** and **transaction tables** are two fundamental types of data that serve distinct purposes. They are often linked together to provide a complete picture of a system's data.

---

### Master Tables (Static Data)

A master table contains core, foundational data that is relatively static and defines the main entities in your system. This data rarely changes and is used as a reference point for other tables.

* **Role:** Defines the "who" and "what" of your business.
* **Characteristics:**
    * **Stable:** Data is created once and updated infrequently.
    * **Relatively small:** The number of records is usually much smaller than transaction tables.
    * **Contains unique entities:** Each row represents a single, unique item or person.
* **Example:** Your `m_customerinfo` table is a perfect example of a master table. It holds information about each customer—data that doesn't change with every single meter reading.

---

### Transaction Tables (Dynamic Data)

A transaction table records events or activities that happen in your system. This data is dynamic, grows constantly, and often references master tables using foreign keys.

* **Role:** Records the "when," "where," and "how" of business activities.
* **Characteristics:**
    * **Dynamic:** Data is frequently added (and sometimes updated or deleted).
    * **Very large:** The number of records can grow indefinitely over time.
    * **References master tables:** Contains foreign keys that link back to the master tables.
* **Example:** Your `t_dlpdata` table is a classic transaction table. It logs a new record for every meter reading, with a foreign key (`meter_id`) linking back to a master table that contains information about that specific meter.

### The Relationship

The relationship between these two types of tables is key to good database design. Transaction tables store the *events*, while master tables provide the *context* for those events. This design principle, known as **normalization**, prevents data redundancy and ensures data integrity.

For instance, instead of storing a customer's full name and address with every single meter reading, you simply store their `customer_id` in the meter reading's master table. This makes your database more efficient and easier to manage.

### Differences

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

**Indexing** is a database technique used to speed up data retrieval operations. Think of an index like the index in the back of a book. Instead of reading the entire book to find a specific topic, you can go to the index, find the page number for that topic, and go directly to it. Similarly, a database index allows the database to quickly find data without scanning every single row in a table.

-----

### How Indexes Work

When you create an index on one or more columns, the database creates a separate data structure (often a B-tree) that stores the values of the indexed columns along with pointers to the corresponding rows in the main table. This structure is highly optimized for fast lookups.

There's a trade-off, however. While indexes speed up data reads, they can slow down data writes (insert, update, delete) because the database has to also update the index every time the data in the main table changes.

-----

### Single-Column Index

A **single-column index** is an index created on just one column of a table. This is the simplest and most common type of index. You use it when you frequently query or sort data based on a single column.

#### **Example: Indexing a Customer's Last Name**

If you frequently search for customers by their last name, creating an index on the `last_name` column in your `m_customerinfo` table would be a great idea.

```sql
CREATE INDEX idx_customer_last_name ON m_customerinfo(last_name);
```

With this index, a query like `SELECT * FROM m_customerinfo WHERE last_name = 'Smith';` will be much faster because the database can use the index to find all the "Smith" records instantly, without scanning the entire table.

-----

### Composite Index (Multi-Column)

A **composite index** is an index created on two or more columns of a table. The order of the columns in the index matters, as it determines how the data is sorted and searched. You use a composite index when your queries frequently filter or sort data on multiple columns together.

#### **Example: Indexing a Customer's Full Name**

If you often search for customers by both their `first_name` and `last_name`, a composite index is a better choice than two separate single-column indexes.

```sql
CREATE INDEX idx_customer_full_name ON m_customerinfo(last_name, first_name);
```

This index is particularly useful for queries that filter on both columns:

```sql
SELECT *
FROM m_customerinfo
WHERE last_name = 'Smith' AND first_name = 'John';
```

The database can use this single index to quickly locate all rows for "John Smith."

**Important Note:** The order of the columns in a composite index is crucial. An index on `(last_name, first_name)` is great for queries filtering on `last_name` or on `last_name` and `first_name`. However, it's not useful for a query that only filters on `first_name` (e.g., `WHERE first_name = 'John'`) because the data is first sorted by `last_name`.

To alter or drop indexes, you use the `ALTER INDEX` and `DROP INDEX` commands. Altering an index is rare; it's more common to drop and recreate it if needed.

-----

### `DROP INDEX`

To remove an index, you use the `DROP INDEX` command, followed by the name of the index you want to delete.

```sql
DROP INDEX idx_customer_last_name;
```

Like with `DROP TABLE`, you can add `IF EXISTS` to avoid an error if the index doesn't exist:

```sql
DROP INDEX IF EXISTS idx_customer_full_name;
```

-----

### `ALTER INDEX`

`ALTER INDEX` is used to change the properties of an existing index. A common use is to rename an index. You can't use it to add or remove columns from a composite index—for that, you have to drop the old index and create a new one.

#### **Renaming an Index**

If you want to rename your `idx_customer_full_name` index to something more descriptive like `idx_customer_name`, you would use this command:

```sql
ALTER INDEX idx_customer_full_name RENAME TO idx_customer_name;
```

**Rule of Thumb:**

* If you filter on one column → Single-column index.
* If you filter **often** on two or more columns → Composite index.
* Don’t overuse indexes → slows down inserts/updates.