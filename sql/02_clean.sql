-- 02_clean.sql
-- Turn raw_transactions into clean_transactions: one row per real product sale
-- to a known customer. Each rule is a view, so we can count what every rule removes.
-- Run with: python scripts/run_sql.py sql/02_clean.sql

-- Stock codes that are fees or bookkeeping entries, not products.
-- Found by checking every stock code that doesn't start with 5 digits.
-- Kept in one table so every query uses the same list.
CREATE OR REPLACE TABLE non_product_codes AS
SELECT * FROM (VALUES
    ('POST', 'postage'), ('DOT', 'dotcom postage'), ('C2', 'carriage'),
    ('M', 'manual entry'), ('D', 'discount'),
    ('ADJUST', 'adjustment'), ('ADJUST2', 'adjustment'),
    ('BANK CHARGES', 'bank charges'), ('CRUK', 'charity commission'),
    ('TEST001', 'test product'), ('TEST002', 'test product')
) AS t(stock_code, reason);

-- Rule 1: drop exact duplicate rows.
-- Most come from 1-9 Dec 2010 appearing in both Excel sheets (see step 1).
CREATE OR REPLACE VIEW s1_dedup AS
SELECT DISTINCT * FROM raw_transactions;

-- Rule 2: drop rows with no customer ID. We can't tie them to a customer.
CREATE OR REPLACE VIEW s2_has_customer AS
SELECT * FROM s1_dedup
WHERE customer_id IS NOT NULL;

-- Rule 3: keep only normal sales invoices (all digits).
-- This removes cancellations ('C...') and accounting adjustments ('A...').
CREATE OR REPLACE VIEW s3_sales_only AS
SELECT * FROM s2_has_customer
WHERE regexp_full_match(invoice, '[0-9]+');

-- Rule 4: drop rows with zero or negative price or quantity.
CREATE OR REPLACE VIEW s4_valid_values AS
SELECT * FROM s3_sales_only
WHERE price > 0 AND quantity > 0;

-- Rule 5: drop stock codes that are fees or bookkeeping entries, not products.
CREATE OR REPLACE VIEW s5_products_only AS
SELECT * FROM s4_valid_values
WHERE stock_code NOT IN (SELECT stock_code FROM non_product_codes);

-- Final clean table, with revenue per line.
CREATE OR REPLACE TABLE clean_transactions AS
SELECT *, quantity * price AS revenue
FROM s5_products_only;

-- Cancellations are kept in their own table, not thrown away.
-- Rule 3 drops them from the sales table, but the original orders they reverse
-- are still in it. Example: customer 16446 ordered 80,995 units (about 168k)
-- and cancelled 12 minutes later. Step 3 subtracts these to get net spend.
-- Quantities here are negative, so revenue is negative.
CREATE OR REPLACE TABLE cancellations AS
SELECT *, quantity * price AS revenue
FROM s2_has_customer
WHERE invoice LIKE 'C%'
  AND stock_code NOT IN (SELECT stock_code FROM non_product_codes);

-- Cleaning waterfall: rows left after each rule, and how many each rule removed.
WITH steps AS (
    SELECT 0 AS step, 'Raw data'                  AS rule, COUNT(*) AS rows_left FROM raw_transactions
    UNION ALL SELECT 1, 'Remove exact duplicates',  COUNT(*) FROM s1_dedup
    UNION ALL SELECT 2, 'Remove missing customer',  COUNT(*) FROM s2_has_customer
    UNION ALL SELECT 3, 'Keep sales invoices only', COUNT(*) FROM s3_sales_only
    UNION ALL SELECT 4, 'Remove price/qty <= 0',    COUNT(*) FROM s4_valid_values
    UNION ALL SELECT 5, 'Remove non-product codes', COUNT(*) FROM s5_products_only
)
SELECT
    step,
    rule,
    rows_left,
    LAG(rows_left) OVER (ORDER BY step) - rows_left             AS rows_removed,
    ROUND(100.0 * rows_left / FIRST_VALUE(rows_left) OVER (ORDER BY step), 1) AS pct_of_raw
FROM steps
ORDER BY step;

-- What the clean table holds
SELECT
    COUNT(*)                    AS n_rows,
    COUNT(DISTINCT invoice)     AS n_orders,
    COUNT(DISTINCT customer_id) AS n_customers,
    COUNT(DISTINCT stock_code)  AS n_products,
    ROUND(SUM(revenue))         AS total_revenue,
    MIN(invoice_date)           AS first_date,
    MAX(invoice_date)           AS last_date
FROM clean_transactions;

-- What the cancellations table holds
SELECT
    COUNT(*)                    AS n_rows,
    COUNT(DISTINCT invoice)     AS n_cancel_invoices,
    COUNT(DISTINCT customer_id) AS n_customers,
    ROUND(SUM(revenue))         AS total_cancelled
FROM cancellations;

-- What this showed (run on 18 Nov 2026):
-- * 1,067,371 raw rows -> 776,596 clean rows (72.8% kept).
-- * Biggest cut is missing customer ID (235,151 rows after de-duplication).
--   These rows are real sales, so total company revenue is higher than our clean
--   total. Our analysis is about known customers only.
-- * Clean table: 36,594 orders from 5,852 customers, 4,621 products,
--   about 17.07m in revenue (prices are in pounds sterling), Dec 2009 to Dec 2011.
-- * Cancellations table: 17,587 lines on 7,283 cancellation invoices from 2,445
--   customers, about -710k in total (around 4% of clean revenue).
