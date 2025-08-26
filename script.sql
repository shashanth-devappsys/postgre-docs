-- Create a dedicated schema to keep our project organized
CREATE SCHEMA IF NOT EXISTS smart_metering;
SET search_path TO smart_metering;

-- ======== TABLE DEFINITIONS ========

-- Module 1: Master table for customer information
CREATE TABLE m_customerinfo (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    address TEXT,
    join_date DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Module 1: Master table for meter metadata
CREATE TABLE m_meterinfo (
    meter_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES m_customerinfo(customer_id),
    msn VARCHAR(20) NOT NULL UNIQUE, -- Meter Serial Number
    ip_address INET,
    install_date DATE,
    status VARCHAR(15) DEFAULT 'active', -- e.g., active, inactive, maintenance
    metadata JSONB -- Module 5: For storing flexible metadata
);

-- Module 1: Transactional table for Data Load Profile (DLP) readings
CREATE TABLE t_dlpdata (
    reading_id BIGSERIAL PRIMARY KEY,
    meter_id INT NOT NULL REFERENCES m_meterinfo(meter_id),
    reading_timestamp TIMESTAMPTZ NOT NULL,
    kwh_reading NUMERIC(10, 4) NOT NULL, -- Kilowatt-hour reading
    CONSTRAINT positive_reading CHECK (kwh_reading >= 0)
);

-- Module 9: Audit table for logging changes
CREATE TABLE t_dlp_audit_log (
    log_id SERIAL PRIMARY KEY,
    action_type VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    action_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_performing_action NAME NOT NULL DEFAULT CURRENT_USER,
    old_row_data JSONB,
    new_row_data JSONB
);


-- ======== INDEXING FOR PERFORMANCE ========
-- Module 1 & 6: Create a composite index for efficient time-series lookups
CREATE INDEX idx_dlpdata_meter_timestamp ON t_dlpdata (meter_id, reading_timestamp DESC);
CREATE INDEX idx_meterinfo_customer_id ON m_meterinfo (customer_id);

-- ======== DATA GENERATION ========
-- Generate 100 customers
INSERT INTO m_customerinfo (first_name, last_name, address)
SELECT
    'Customer_First_' || s,
    'Customer_Last_' || s,
    s || ' Main St, Anytown'
FROM generate_series(1, 100) s;

-- Generate 100 meters, assigning each to a customer
INSERT INTO m_meterinfo (customer_id, msn, ip_address, install_date, metadata)
SELECT
    s,
    'SM-' || (10000 + s)::text,
    ('192.168.1.' || (s % 254 + 1))::inet,
    (CURRENT_DATE - (random() * 365)::int),
    ('{"manufacturer": "Generic Inc.", "model": "Model ' || (s % 3 + 1) || '"}')::JSONB
FROM generate_series(1, 100) s;

-- Generate 10-minute interval readings for all 100 meters for the past 90 days
-- This will generate a large dataset: 100 meters * 90 days * 24 hours/day * 6 readings/hour = 1,296,000 rows
INSERT INTO t_dlpdata (meter_id, reading_timestamp, kwh_reading)
SELECT
    m.meter_id,
    ts.reading_time,
    -- Simulate a reading, e.g., between 0.01 and 0.5 kWh per 10 mins
    round((random() * 0.49 + 0.01)::numeric, 4)
FROM
    m_meterinfo m,
    generate_series(
        NOW() - INTERVAL '90 days',
        NOW(),
        INTERVAL '10 minutes'
    ) AS ts(reading_time)
ORDER BY m.meter_id, ts.reading_time;

-- Verify the data generation
SELECT
    (SELECT COUNT(*) FROM m_customerinfo) AS total_customers,
    (SELECT COUNT(*) FROM m_meterinfo) AS total_meters,
    (SELECT COUNT(*) FROM t_dlpdata) AS total_readings;