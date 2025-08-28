## Bulk Data Loading & File Handling

### 1. The `COPY` Command for CSV Ingestion

The `COPY` command in PostgreSQL is the most efficient and robust way to import data from a file, such as a CSV, directly into a database table. Unlike `INSERT` statements, which process one row at a time, `COPY` is designed for bulk operations, making it significantly faster for large datasets.

-----

### How It Works

The `COPY` command reads data from a file on the server's filesystem and loads it directly into a table. You must have the necessary file system permissions on the server to use this command.

The basic syntax is as follows:

```sql
COPY table_name (column1, column2, ...)
FROM 'path/to/your/file.csv'
DELIMITERS ','
CSV HEADER;
```

  * **`table_name (column1, ...)`**: Specifies the target table and, optionally, the columns you want to import data into. It's a good practice to list the columns to ensure the data from the CSV file is mapped correctly, even if the file's column order changes.
  * **`FROM 'path/to/your/file.csv'`**: The full path to the CSV file on the server.
  * **`DELIMITERS ','`**: Specifies the character that separates values in the file. The default is a tab character, so you must explicitly specify a comma for CSV files.
  * **`CSV HEADER`**: This crucial option tells PostgreSQL that the first row of your CSV file is a header row and should be ignored during the import. This is a very common requirement for CSV files.

-----

### Clear Examples

Let's imagine you have a CSV file named `meter_readings.csv` with the following content:

```csv
meter_id,reading_timestamp,kwh_reading
101,2025-08-28 08:00:00,500.25
102,2025-08-28 08:00:00,450.75
103,2025-08-28 08:01:00,601.50
```

You want to import this data into your `t_dlpdata` table, which has a similar structure.

**Scenario 1: Simple Ingestion**

If the column order in your CSV file matches your table, you can use a simple `COPY` command.

```sql
COPY t_dlpdata (meter_id, reading_timestamp, kwh_reading)
FROM '/path/to/your/data/meter_readings.csv'
DELIMITER ','
CSV HEADER;
```

**Scenario 2: Skipping a Column**

What if your CSV file has an extra column you don't need, like `location_id`?

```csv
meter_id,reading_timestamp,kwh_reading,location_id
101,2025-08-28 08:00:00,500.25,A1
102,2025-08-28 08:00:00,450.75,B2
```

You simply list only the columns you want to import, and `COPY` will handle the rest.

```sql
COPY t_dlpdata (meter_id, reading_timestamp, kwh_reading)
FROM '/path/to/your/data/meter_readings.csv'
DELIMITER ','
CSV HEADER;
```

By explicitly listing the column names in the command, you ensure that the extra `location_id` column is ignored. This makes your ingestion process more resilient to changes in the source file format.

-----

To load a local file to a remote PostgreSQL database, you need to use the `\COPY` command, which is a feature of the `psql` command-line tool.

-----

### The `\COPY` Command

The `\COPY` command is a client-side utility that reads a file from your local machine and sends it to the remote server as a stream of data. This bypasses the need for the file to exist on the server's filesystem. It's essentially a client-side wrapper around the server's `COPY` command.

### Example

To use `\COPY`, you need to be in your local terminal and connect to your remote database using the `psql` command. Once connected, you can run `\COPY` directly.

Let's say you have a CSV file named `new_readings.csv` on your local desktop at `C:\Users\YourUser\Desktop\` and you want to import it into the `t_dlpdata` table on a remote server.

1.  First, open your command-line terminal.

2.  Connect to your remote database using `psql`. You'll need the hostname, username, database name, and port.

    ```bash
    psql -h your_remote_host -p 5432 -U your_username -d your_database
    ```

3.  Once the `psql` shell starts and you see the `your_database=>` prompt, you can run the `\COPY` command. The path here is the path on your **local** machine.

    ```bash
    \COPY t_dlpdata (meter_id, reading_timestamp, kwh_reading)
    FROM 'C:\Users\YourUser\Desktop\new_readings.csv'
    DELIMITER ','
    CSV HEADER;
    ```

    After running the command, you will see output indicating the number of rows copied.

-----

### Key Difference: `COPY` vs. `\COPY`

  * **`COPY` (Server-Side):** This is a SQL command executed by the database server. The file must exist on the server's file system, and you need special permissions to use it.
  * **`\COPY` (Client-Side):** This is a command-line utility provided by the `psql` client. It reads the file from your local machine and streams the data to the server via the database connection. This is the correct and most common way to load data from your computer to a remote database.

-----

## 2. Reading JSON, CSV in psql 

We can't "read" a JSON or CSV file directly within the `psql` command prompt and manipulate it in-memory like a script. The `\COPY` command is the standard way to load data from these files into a table. For JSON, PostgreSQL's built-in functions allow you to read a JSON-formatted string (which you can get from a file) and process it within a query.

-----

### Ingesting Data into a Table with `\COPY`

As we discussed before, the `\COPY` command is the primary method for getting data from a file into a table.

#### **Example: CSV File**

Let's use the `\COPY` command to ingest data from a CSV file into a table named `t_dlpdata`.

  * **File:** `meter_readings.csv`

    ```csv
    meter_id,reading_timestamp,kwh_reading
    101,2025-08-28 08:00:00,500.25
    102,2025-08-28 08:00:00,450.75
    103,2025-08-28 08:01:00,601.50
    ```

  * **psql Command:**

    ```bash
    \COPY t_dlpdata (meter_id, reading_timestamp, kwh_reading)
    FROM 'C:\Users\YourUser\Desktop\meter_readings.csv'
    DELIMITER ','
    CSV HEADER;
    ```

This command reads the data, handles the CSV format, and inserts each row into the specified columns of the `t_dlpdata` table.

-----

### Reading and Processing JSON

Unlike CSV, you can't simply `\COPY` a JSON file into a relational table without transforming it. PostgreSQL has powerful native **JSON functions** and **JSONB data types** that let you handle JSON data directly within queries. The common pattern is to first load a JSON file into a table as a single text or JSONB column, then use functions to extract and transform the data.

#### **Example: Loading and Querying JSON**

Let's assume you have a JSON file `user_data.json` that contains an array of JSON objects.

  * **File:** `user_data.json`
    ```json
    [
      {"name": "Alice", "city": "New York", "interests": ["hiking", "coding"]},
      {"name": "Bob", "city": "San Francisco", "interests": ["gaming", "reading"]}
    ]
    ```

Here's how you would handle this:

**1. Create a Staging Table**
First, create a temporary table to hold the raw JSON data.

```sql
CREATE TABLE temp_json (
    data JSONB
);
```

**2. Load the JSON Data**
Use `\COPY` to load the entire JSON file into the single `data` column.

```bash
\COPY temp_json FROM 'C:\Users\YourUser\Desktop\user_data.json';
```

Now, your `temp_json` table has one row containing the entire JSON array as a single value.

**3. Process and Transform the Data**
Use PostgreSQL's JSON functions to flatten the data and insert it into a structured table. `jsonb_array_elements` is a powerful function that expands a JSON array into a set of rows.

Let's assume you want to insert this data into a `users` table:

```sql
CREATE TABLE users (
    user_name TEXT,
    city TEXT,
    interests TEXT[]
);
```

Now, you can use an `INSERT` statement with a `SELECT` query to transform the JSON data.

```sql
INSERT INTO users (user_name, city, interests)
SELECT
    elem->>'name' AS user_name,
    elem->>'city' AS city,
    jsonb_array_elements_text(elem->'interests') AS interests
FROM temp_json, jsonb_array_elements(data) AS elem;
```

This query:

  * Uses `jsonb_array_elements(data)` to turn the JSON array into multiple rows, with each row containing a single JSON object (e.g., `{"name": "Alice", ...}`).
  * Uses the `->>` operator to extract the `name` and `city` values as text.
  * Uses `jsonb_array_elements_text` to extract the `interests` array as a set of text values, which are then collected into a PostgreSQL array (`TEXT[]`).

**Important Note:** The **JSONB** data type is highly recommended over **JSON** because it stores the data in a decomposed binary format, which is much faster for processing and querying.