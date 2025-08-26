## PL/pgSQL & Server-Side Programming

### 1. PL/pgSQL Syntax and Structure

**PL/pgSQL** (Procedural Language/PostgreSQL SQL) is a procedural language that allows you to create functions, stored procedures, and triggers within the PostgreSQL database. It extends the standard SQL capabilities by adding programming language features such as variables, loops, conditional logic, and error handling.

The basic structure of a PL/pgSQL code block is organized into three main sections: **declaration**, **body**, and **exception handling** (optional).

-----

#### 1. Declaration Section

The `DECLARE` section is where you define all the variables, aliases, and cursors that you will use in your function or block. This section is optional but highly recommended for clear code.

**Syntax:**

```sql
[ DECLARE
    variable_name datatype [ := initial_value ];
    ...
]
```

**Example:**

```sql
DECLARE
    meter_count INTEGER; -- Declares a variable to hold an integer.
    customer_id_val INT := 123; -- Declares and initializes a variable.
```

-----

#### 2. Body Section

The `BEGIN...END` block is the core of your PL/pgSQL code. This is where you write the executable statements, including SQL commands and procedural logic. Every PL/pgSQL function or code block must have a body section.

**Syntax:**

```sql
BEGIN
    -- Your executable statements go here.
    ...
END;
```

**Example:**

```sql
BEGIN
    -- This is a simple executable statement.
    SELECT COUNT(*) INTO meter_count FROM m_meterinfo;

    -- This is an example of a conditional statement.
    IF meter_count > 0 THEN
        -- Do something here.
        RAISE NOTICE 'The number of meters is %', meter_count;
    END IF;
END;
```

-----

#### 3. Exception Handling Section

The `EXCEPTION` section is optional and is used to handle errors that occur during the execution of the code. This prevents the entire transaction from failing and allows you to gracefully manage potential issues.

**Syntax:**

```sql
[ EXCEPTION
    WHEN condition [ OR another_condition... ] THEN
        statement;
    ...
]
```

**Example:**

```sql
BEGIN
    -- Code that might cause an error, like a division by zero.
    total_reading := kwh_reading / meter_count;

EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Caught a division by zero error!';
        total_reading := 0; -- Assign a default value.
END;
```

-----

### Putting It All Together: Function Structure

When you create a function in PostgreSQL, the entire PL/pgSQL block is contained within the function definition.

**Full Function Syntax:**

```sql
CREATE [OR REPLACE] FUNCTION function_name (parameters)
RETURNS return_datatype AS $$
[ DECLARE
    -- Declaration section
    ...
]
BEGIN
    -- Body section
    ...

    [ EXCEPTION
        -- Exception handling section
        ...
    ]
END;
$$ LANGUAGE plpgsql;
```

-----

Here is a an example of a **PL/pgSQL** function that incorporates all the key elements of its syntax and structure, using your provided meter reading and customer data.

The function `calculate_customer_avg_kwh` will:

1.  **Declare** variables to store intermediate results.
2.  Use a **`SELECT ... INTO`** query to retrieve and aggregate data.
3.  Employ an **`IF...THEN`** block for conditional logic to handle a case where no readings are found.
4.  Use an **`EXCEPTION`** block to gracefully handle an error if the specified customer ID does not exist.

This example shows how PL/pgSQL combines standard SQL with procedural programming concepts for robust data processing.

```sql
CREATE OR REPLACE FUNCTION calculate_customer_avg_kwh(p_customer_id INT)
RETURNS NUMERIC AS $$
-- 1. Declaration Section: Define variables and aliases.
DECLARE
    v_total_kwh     NUMERIC := 0;
    v_reading_count INTEGER := 0;
    v_avg_kwh       NUMERIC;
    v_customer_name VARCHAR(100);

BEGIN
    -- 2. Body Section: The main executable code block.

    -- First, check if the customer exists and get their name.
    -- If no row is found, a NO_DATA_FOUND exception will be raised.
    SELECT first_name || ' ' || last_name
    INTO v_customer_name
    FROM m_customerinfo
    WHERE customer_id = p_customer_id;

    -- Aggregate the total kwh and count the readings for the customer.
    SELECT
        SUM(dlp.kwh_reading),
        COUNT(dlp.reading_id)
    INTO
        v_total_kwh,
        v_reading_count
    FROM
        t_dlpdata AS dlp
    JOIN
        m_meterinfo AS mi ON dlp.meter_id = mi.meter_id
    WHERE
        mi.customer_id = p_customer_id;

    -- 3. Conditional Logic: Check if there are any readings.
    IF v_reading_count > 0 THEN
        v_avg_kwh := v_total_kwh / v_reading_count;
        RAISE NOTICE 'Average KWH for % (ID: %): %', v_customer_name, p_customer_id, v_avg_kwh;
    ELSE
        RAISE NOTICE 'No meter readings found for customer % (ID: %)', v_customer_name, p_customer_id;
        v_avg_kwh := 0;
    END IF;

    -- Return the calculated average.
    RETURN v_avg_kwh;

-- 4. Exception Handling Section: Catch and manage specific errors.
EXCEPTION
    -- Handles the case where the initial customer lookup failed.
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION 'Customer with ID % does not exist.', p_customer_id;
    -- Catches any other unexpected error.
    WHEN OTHERS THEN
        RAISE EXCEPTION 'An error occurred during calculation for customer ID %: %', p_customer_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;
```

### How to Use the Function

You can call the function like any other SQL function.

**Example 1: A valid customer with readings**

```sql
SELECT calculate_customer_avg_kwh(1);
```

**Example 2: A valid customer with no readings**

```sql
-- Assuming a customer with ID 2 has no data in t_dlpdata
SELECT calculate_customer_avg_kwh(2);
```

**Example 3: A customer that does not exist**

```sql
SELECT calculate_customer_avg_kwh(999);
```

-----

### 2. Triggers and Event-Driven Programming

**Triggers** are a fundamental part of **event-driven programming** in a database context. They are special functions that are automatically executed in response to a specific database event, such as an `INSERT`, `UPDATE`, or `DELETE` command on a table.

Think of it like this: an event (e.g., a new row being added to a table) "triggers" a pre-defined action (e.g., logging that event to a separate audit table). This allows you to enforce business rules, maintain data integrity, and automate tasks without requiring the application to handle them explicitly.

-----

### Key Components

1.  **Event**: The database operation that fires the trigger (`INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`).
2.  **Timing**: When the trigger fires relative to the event (`BEFORE` or `AFTER`). `BEFORE` triggers are often used to validate or modify data before the operation, while `AFTER` triggers are used for logging or cascade actions after the operation is complete.
3.  **Trigger Function**: The PL/pgSQL function that contains the logic to be executed. The function receives special variables like `NEW` (the new row) and `OLD` (the old row).
4.  **Trigger**: The database object that links the event, timing, and trigger function to a specific table.

-----

### Example: Auditing Meter Readings

Let's use your `t_dlpdata` and `t_dlp_audit_log` tables to create a trigger that logs every `INSERT`, `UPDATE`, and `DELETE` operation on the `t_dlpdata` table.

#### Step 1: Create the Trigger Function

This PL/pgSQL function will be called whenever a change occurs. It checks the type of event and inserts a new row into the `t_dlp_audit_log` table with the relevant data.

```sql
CREATE OR REPLACE FUNCTION log_dlp_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO t_dlp_audit_log (action_type, new_row_data)
        VALUES ('INSERT', to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO t_dlp_audit_log (action_type, old_row_data, new_row_data)
        VALUES ('UPDATE', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO t_dlp_audit_log (action_type, old_row_data)
        VALUES ('DELETE', to_jsonb(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

  * `TG_OP`: A special variable that contains the operation type (`'INSERT'`, `'UPDATE'`, `'DELETE'`).
  * `NEW` and `OLD`: Special variables that represent the new and old rows, respectively. We convert them to `JSONB` to store the full row data.

#### Step 2: Create the Trigger

Now, we create the trigger on the `t_dlpdata` table that will fire the function.

```sql
CREATE TRIGGER dlp_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON t_dlpdata
FOR EACH ROW
EXECUTE FUNCTION log_dlp_changes();
```

  * **`AFTER INSERT OR UPDATE OR DELETE`**: Specifies the events and timing. The trigger will fire after any of these operations.
  * **`ON t_dlpdata`**: The table the trigger is attached to.
  * **`FOR EACH ROW`**: The trigger will fire once for every single row affected by the operation.
  * **`EXECUTE FUNCTION log_dlp_changes()`**: The trigger function that is called when the event occurs.

With this setup, any change to your `t_dlpdata` table will automatically be logged to the `t_dlp_audit_log` table, creating a complete and reliable audit trail. The application doesn't have to do anything—the database handles the event automatically.

-----

### 3. Exception Handling

**Exception handling** in PL/pgSQL is a crucial mechanism for gracefully managing errors and warnings that occur during the execution of your code. Instead of allowing a runtime error to halt the entire script or transaction, a well-structured exception block gives you the control to catch the error, log it, and take a corrective action, ensuring the function completes in a controlled manner.

The exception handling section is an optional part of a PL/pgSQL `BEGIN...END` block. It starts with the `EXCEPTION` keyword and contains one or more `WHEN...THEN` clauses to handle specific error conditions.

-----

### The Structure

The basic structure is as follows:

```sql
BEGIN
    -- This is the code that might raise an exception.
    -- If an error occurs here, control jumps to the EXCEPTION section.

EXCEPTION
    WHEN condition_1 [OR condition_2 ...] THEN
        -- Actions to take for condition_1 or condition_2.
        -- For example, you can log the error or set a variable.

    WHEN condition_3 THEN
        -- Actions to take for a different type of error.

    WHEN OTHERS THEN
        -- A catch-all for any other unhandled errors.
        -- This should be the last WHEN clause.
END;
```

-----

### Example with Meter Reading Data

Let's create a function that calculates the average reading for a given meter. We will use exception handling to cover several cases:

  * **Case 1: `NO_DATA_FOUND`**: If the provided `meter_id` doesn't exist, the `SELECT...INTO` statement will fail.
  * **Case 2: `division_by_zero`**: If a meter has no readings, the `v_reading_count` will be 0, causing a division by zero error.
  * **Case 3: `OTHERS`**: A generic catch-all for any other unforeseen error.

<!-- end list -->

```sql
CREATE OR REPLACE FUNCTION get_avg_kwh_for_meter(p_meter_id INT)
RETURNS NUMERIC AS $$
DECLARE
    v_total_kwh     NUMERIC;
    v_reading_count INTEGER;
    v_avg_kwh       NUMERIC;

BEGIN
    -- Attempt to get the total readings and count for the specified meter.
    -- This will raise NO_DATA_FOUND if the meter_id is invalid.
    SELECT
        SUM(kwh_reading),
        COUNT(reading_id)
    INTO
        v_total_kwh,
        v_reading_count
    FROM
        t_dlpdata
    WHERE
        meter_id = p_meter_id;

    -- This calculation will raise a division_by_zero error if v_reading_count is 0.
    v_avg_kwh := v_total_kwh / v_reading_count;

    -- If no exception is raised, return the calculated average.
    RETURN v_avg_kwh;

-- Exception Handling Section
EXCEPTION
    -- Case 1: Handle a non-existent meter.
    WHEN NO_DATA_FOUND THEN
        RAISE NOTICE 'Meter with ID % was not found. Returning 0.', p_meter_id;
        RETURN 0;

    -- Case 2: Handle a meter with no readings.
    WHEN division_by_zero THEN
        RAISE NOTICE 'Meter with ID % has no readings. The average is 0.', p_meter_id;
        RETURN 0;

    -- Case 3: A generic handler for any other error.
    WHEN OTHERS THEN
        RAISE NOTICE 'An unexpected error occurred: %', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

#### How to Call and Test the Function

You can call this function and see how it handles different scenarios:

  * **Valid Meter ID with Data:**
    ```sql
    -- Assuming meter 1 has readings
    SELECT get_avg_kwh_for_meter(1);
    ```
  * **Valid Meter ID with No Data:**
    ```sql
    -- Assuming a meter with ID 2 exists but has no readings in t_dlpdata
    SELECT get_avg_kwh_for_meter(2);
    ```
    This will trigger the `division_by_zero` exception and return `0`.
  * **Invalid Meter ID:**
    ```sql
    SELECT get_avg_kwh_for_meter(999);
    ```
    This will trigger the `NO_DATA_FOUND` exception and return `0`.
  * **Other Errors:**
    The `WHEN OTHERS` clause would catch errors like a data type mismatch, ensuring the function doesn't crash unexpectedly.