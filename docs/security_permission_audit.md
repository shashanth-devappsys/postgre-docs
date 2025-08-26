## Security, Permissions & Auditing in PostgreSQL

### 1. Roles & Privileges (GRANT, REVOKE)

In PostgreSQL, a **role** is a fundamental concept for managing security. A role can function as either a **user** who can log in to the database or as a **group** that holds a collection of privileges. **Privileges** are specific permissions to perform actions on database objects, such as tables, schemas, or databases.

The two main commands for managing these permissions are `GRANT` and `REVOKE`.

  * **`GRANT`**: This command is used to give a role a specific privilege.
  * **`REVOKE`**: This command is used to remove a privilege from a role.

The best practice when granting privileges is to follow the **principle of least privilege**. This means you should only grant the minimum permissions that a role needs to perform its job.

-----

### Examples

#### 1. Creating a User and a Group

You can create a role that can log in, acting as a user, and a role that acts as a group to hold a set of common permissions.

```sql
-- Create a user role for an application.
CREATE ROLE app_user WITH LOGIN PASSWORD 'your_secure_password';

-- Create a group role for analysts who can only read data.
CREATE ROLE analyst_group;

-- Assign the 'analyst_group' to the 'app_user'.
GRANT analyst_group TO app_user;
```

#### 2. Granting Privileges on Tables

You can grant privileges on specific tables.

```sql
-- Grant SELECT, INSERT, UPDATE, and DELETE privileges on the 'm_customerinfo' table to 'app_user'.
GRANT SELECT, INSERT, UPDATE, DELETE ON m_customerinfo TO app_user;

-- Grant only SELECT privilege on 'm_meterinfo' to the 'analyst_group'.
GRANT SELECT ON m_meterinfo TO analyst_group;
```

With this setup, any member of `analyst_group` (like `app_user`) can read data from `m_meterinfo`, but only `app_user` has the ability to modify `m_customerinfo`.

#### 3. Revoking Privileges

If `app_user` no longer needs to update customer information, you can remove that privilege.

```sql
-- Revoke the UPDATE privilege on the 'm_customerinfo' table from 'app_user'.
REVOKE UPDATE ON m_customerinfo FROM app_user;
```

Now, `app_user` can still read, insert, and delete data from `m_customerinfo` but can no longer update existing records.

---

### 2. Row-Level Security (RLS)

**Row-Level Security (RLS)** is a feature in PostgreSQL that restricts a user's access to specific rows in a table. It provides a more granular level of control than standard table-level permissions. Instead of a user having all-or-nothing access to a table, an RLS policy acts like a hidden `WHERE` clause, automatically filtering the rows a user can see or manipulate based on criteria you define. This is particularly useful for multi-tenant applications where different users need to access the same table but should only see their own data.

-----

### Example: Securing Customer Data

Let's use your provided tables to illustrate how RLS can ensure a customer only sees their own meter readings.

#### 1. Enable RLS on the Table

First, you must explicitly enable RLS for the table you want to protect.

```sql
ALTER TABLE t_dlpdata ENABLE ROW LEVEL SECURITY;
```

By default, with no policies in place, this will prevent all users without a `superuser` status from accessing the table.

#### 2. Create an RLS Policy

Next, you create a policy that defines the filtering rule. In this example, we'll assume your application assigns a unique username to each customer, such as `cust_101`. The policy will use the current user's name to determine which `meter_id`s they are allowed to see.

```sql
CREATE POLICY customer_readings_policy
ON t_dlpdata
FOR SELECT
USING (
    meter_id IN (
        SELECT meter_id
        FROM m_meterinfo
        WHERE customer_id = substring(current_user from 6)::int
    )
);
```

This policy works by:

  * **`FOR SELECT`**: Specifying that the policy applies to `SELECT` queries.
  * **`USING (...)`**: Defining the filtering condition. The `substring(current_user from 6)::int` part extracts the numerical customer ID from a username like `'cust_101'`, allowing the query to filter results based on the `customer_id` in the `m_meterinfo` table.

#### 3. Testing the Policy

You can test this by creating a user and then temporarily switching your session to that user's role.

```sql
-- Create a sample user that follows the naming convention.
CREATE USER cust_101 WITH PASSWORD 'secure_password';

-- Grant the user basic SELECT privileges on the table.
-- The RLS policy will handle the filtering.
GRANT SELECT ON t_dlpdata TO cust_101;

-- Temporarily switch to the 'cust_101' role to test.
SET ROLE cust_101;

-- Now, when 'cust_101' runs this query, they will only see readings for their meters.
SELECT * FROM t_dlpdata;

-- Switch back to your original role.
RESET ROLE;
```

Even though the user was granted `SELECT` on the whole table, the RLS policy ensures they can only see the rows they are entitled to. RLS can also be used for `INSERT`, `UPDATE`, and `DELETE` operations to prevent users from modifying data they don't own.

---

### 3. SSL/TLS Configuration for PostgreSQL

To secure the communication between a PostgreSQL client and server, you can configure **SSL/TLS (Secure Sockets Layer/Transport Layer Security)**. This encrypts the data in transit, protecting it from eavesdropping. The setup involves generating certificates on the server and then configuring both the server and the client to use them.

-----

### Step 1: Generate SSL Certificates on the Server

First, you need to generate a self-signed certificate and a private key for the server. You can do this using the `openssl` command.

```bash
# Create a private key and a self-signed certificate.
openssl req -new -x509 -days 365 -nodes \
  -text -out server.crt -keyout server.key
  
# Set the correct permissions for the key. This is a crucial security step.
chmod 600 server.key

# Move the certificate and key files to the PostgreSQL data directory ($PGDATA).
mv server.key server.crt $PGDATA
```

This process creates two files: `server.crt` (the public certificate) and `server.key` (the private key).

-----

### Step 2: Configure PostgreSQL Server

Next, you need to tell the PostgreSQL server to use these files for SSL. This is done in the `postgresql.conf` and `pg_hba.conf` configuration files.

#### **In `postgresql.conf`**

Open `postgresql.conf` and set the following parameters to enable SSL and specify the paths to your certificate and key.

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
```

#### **In `pg_hba.conf`**

The `pg_hba.conf` file controls client authentication. You need to change the connection method from `host` to **`hostssl`** to enforce SSL for a specific user, database, or all connections.

```conf
# TYPE      DATABASE    USER        ADDRESS       METHOD
hostssl     smartmeterdb  app_user    0.0.0.0/0     md5
```

This line tells PostgreSQL that for the `smartmeterdb` database and `app_user`, all connections must use SSL (`hostssl`).

After making these changes, you must reload the configuration to apply the changes without restarting the entire server.

```sql
SELECT pg_reload_conf();
```

-----

### Step 3: Connect from a Client

Finally, the client needs to be configured to use SSL when connecting. You can do this by specifying the `sslmode` in the connection string.

```bash
psql "host=dbserver dbname=smartmeterdb user=app_user sslmode=require"
```

The **`sslmode=require`** option ensures the client will only connect if it can establish a secure SSL connection. Other SSL modes include `disable` (no SSL), `prefer` (try SSL, but allow a non-SSL connection), and `verify-ca` or `verify-full` for more stringent certificate verification.

---

### 4. Auditing with pgAudit

**pgAudit** is a powerful PostgreSQL extension that provides detailed, configurable auditing. It creates a comprehensive log of database activity, which is essential for security compliance, troubleshooting, and forensic analysis. Unlike simple triggers, `pgAudit` logs directly to the PostgreSQL log files, creating a separate and tamper-proof audit trail.

-----

### Step 1: Install and Enable the Extension

To use `pgAudit`, you must first load it into your PostgreSQL server. You do this by editing the `postgresql.conf` file.

```ini
# Add 'pgaudit' to the list of shared preload libraries.
shared_preload_libraries = 'pgaudit'
```

After saving the file, you must **restart the PostgreSQL server** for the change to take effect. Once the server is back up, connect to your database and create the extension.

```sql
CREATE EXTENSION pgaudit;
```

-----

### Step 2: Configure Auditing

The `pgaudit.log` parameter in `postgresql.conf` controls what types of statements are logged. You can set it to one or more of the following:

  * **`READ`**: Logs `SELECT` and `COPY` statements.
  * **`WRITE`**: Logs `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, and `COPY` from.
  * **`DDL`**: Logs all Data Definition Language statements like `CREATE`, `ALTER`, and `DROP`.
  * **`FUNCTION`**: Logs calls to functions.
  * **`ROLE`**: Logs statements related to roles (`CREATE ROLE`, `ALTER ROLE`, `GRANT`, etc.).

You can combine these options with a comma-separated list.

```ini
# Log all read, write, and DDL statements.
pgaudit.log = 'READ, WRITE, DDL'
```

After modifying `postgresql.conf`, reload the configuration to apply the changes.

```sql
SELECT pg_reload_conf();
```

-----

### Step 3: View the Audit Logs

Once configured, `pgAudit` will write detailed log entries to your PostgreSQL log file. A typical log entry will contain information about the session, user, statement type, and the query itself.

**Example Log Entry:**

```
AUDIT: SESSION,1,1,WRITE,INSERT,,"INSERT INTO m_customerinfo (first_name,last_name,address) VALUES ('Alice','Brown','Zone A')",<none>
```

This log shows that an `INSERT` statement (`WRITE`) was executed, and it records the exact query performed by the user. `pgAudit` provides a crucial level of transparency for all database operations.