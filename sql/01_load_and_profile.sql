-- 01_load_and_profile.sql
-- Load the raw transactions and get a first look at the data.
-- Run with: duckdb retail.duckdb < sql/01_load_and_profile.sql

-- 1. Load the raw file into a table. Column names are cleaned to snake_case.
CREATE OR REPLACE TABLE raw_transactions AS
SELECT
    CAST(Invoice AS VARCHAR)       AS invoice,
    CAST(StockCode AS VARCHAR)     AS stock_code,
    Description                    AS description,
    CAST(Quantity AS INTEGER)      AS quantity,
    CAST(InvoiceDate AS TIMESTAMP) AS invoice_date,
    CAST(Price AS DOUBLE)          AS price,
    CAST("Customer ID" AS INTEGER) AS customer_id,
    Country                        AS country
FROM read_csv_auto('data/online_retail_raw.csv', header = true);

-- 2. Size of the data
SELECT
    COUNT(*)                    AS n_rows,
    COUNT(DISTINCT invoice)     AS n_invoices,
    COUNT(DISTINCT customer_id) AS n_customers,
    COUNT(DISTINCT stock_code)  AS n_products,
    COUNT(DISTINCT country)     AS n_countries,
    MIN(invoice_date)           AS first_date,
    MAX(invoice_date)           AS last_date
FROM raw_transactions;

-- 3. Missing values in each column
SELECT
    COUNT(*) - COUNT(invoice)      AS null_invoice,
    COUNT(*) - COUNT(description)  AS null_description,
    COUNT(*) - COUNT(customer_id)  AS null_customer_id,
    COUNT(*) - COUNT(price)        AS null_price
FROM raw_transactions;

-- 4. Odd values worth a closer look before cleaning
-- COUNT(*) FILTER (WHERE ...) counts only the rows that meet the condition.
-- Same result as SUM(CASE WHEN ... THEN 1 ELSE 0 END), but shorter.
SELECT
    COUNT(*) FILTER (WHERE invoice LIKE 'C%')                   AS cancelled_rows,
    COUNT(*) FILTER (WHERE quantity <= 0)                       AS non_positive_qty,
    COUNT(*) FILTER (WHERE price <= 0)                          AS non_positive_price,
    COUNT(*) FILTER (WHERE NOT regexp_full_match(invoice, '[0-9]+')
                       AND invoice NOT LIKE 'C%')               AS other_invoice_codes
FROM raw_transactions;

-- 5. Exact duplicate rows (same invoice, product, quantity, time, price, customer)
SELECT COUNT(*) - COUNT(DISTINCT (invoice, stock_code, description, quantity,
                                  invoice_date, price, customer_id, country))
       AS duplicate_rows
FROM raw_transactions;

-- 6. Where do customers come from? Top 5 countries by rows
SELECT country, COUNT(*) AS n_rows,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_rows
FROM raw_transactions
GROUP BY country
ORDER BY n_rows DESC
LIMIT 5;

-- What this showed (run on 18 Nov 2026):
-- * 1,067,371 rows, 53,628 invoices, 5,942 customers, 5,305 products, 43 countries,
--   1 Dec 2009 to 9 Dec 2011. UK is 91.9% of rows.
-- * 243,007 rows (22.8%) have no customer ID. They can't be used for customer analysis.
-- * 19,494 cancelled rows (invoice starts with 'C'), 6,207 rows with price <= 0.
-- * 6 'A' invoices are bad-debt accounting adjustments, not sales.
-- * 34,335 exact duplicate rows. 22,523 of these come from the two Excel sheets
--   overlapping: 1-9 Dec 2010 is in both sheets (1,088 invoices), so those days
--   would be double counted without de-duplication.
