-- 03_customers.sql
-- Build one row per customer from clean_transactions.
-- Two levels of aggregation: product lines -> orders -> customers.
-- Run with: python scripts/run_sql.py sql/03_customers.sql

-- Level 1: one row per order (invoice).
-- We need order totals first, otherwise "average order value" would really be
-- the average line value. A few invoices have lines a minute apart, so we take
-- the earliest time as the order time.
CREATE OR REPLACE TABLE orders AS
SELECT
    invoice,
    customer_id,
    MIN(invoice_date)          AS order_date,
    COUNT(*)                   AS n_lines,
    SUM(quantity)              AS n_units,
    SUM(revenue)               AS order_value
FROM clean_transactions
GROUP BY invoice, customer_id;

-- Level 2: one row per customer.
-- Recency is measured from a snapshot date: the day after the last order in the data.
CREATE OR REPLACE TABLE customers AS
WITH snapshot AS (
    SELECT CAST(MAX(order_date) AS DATE) + 1 AS snapshot_date FROM orders
),
customer_orders AS (
    SELECT
        customer_id,
        CAST(MIN(order_date) AS DATE) AS first_purchase,
        CAST(MAX(order_date) AS DATE) AS last_purchase,
        COUNT(*)                      AS n_orders,
        SUM(n_units)                  AS n_units,
        SUM(order_value)              AS gross_revenue
    FROM orders
    GROUP BY customer_id
),
customer_cancellations AS (
    -- Value of everything the customer cancelled (a negative number)
    SELECT customer_id, SUM(revenue) AS cancelled_value
    FROM cancellations
    GROUP BY customer_id
),
customer_country AS (
    -- 12 customers appear under more than one country, so take their most common one
    SELECT customer_id, MODE(country) AS country, COUNT(DISTINCT stock_code) AS n_products
    FROM clean_transactions
    GROUP BY customer_id
)
SELECT
    o.customer_id,
    c.country,
    o.first_purchase,
    o.last_purchase,
    s.snapshot_date - o.last_purchase  AS recency_days,   -- days since last order
    o.last_purchase - o.first_purchase AS tenure_days,    -- days between first and last order
    o.n_orders,
    o.n_units,
    c.n_products,
    ROUND(o.gross_revenue, 2)                             AS gross_revenue,
    ROUND(COALESCE(x.cancelled_value, 0), 2)              AS cancelled_value,
    ROUND(o.gross_revenue + COALESCE(x.cancelled_value, 0), 2)              AS net_revenue,
    ROUND((o.gross_revenue + COALESCE(x.cancelled_value, 0)) / o.n_orders, 2) AS avg_order_value
FROM customer_orders o
JOIN customer_country c USING (customer_id)
LEFT JOIN customer_cancellations x USING (customer_id)   -- LEFT: most customers never cancel
CROSS JOIN snapshot s;

-- Check: the customer table must add back to the clean tables
SELECT
    (SELECT COUNT(DISTINCT customer_id) FROM clean_transactions) AS customers_in_clean,
    (SELECT COUNT(*) FROM customers)                             AS customers_in_table,
    (SELECT ROUND(SUM(revenue)) FROM clean_transactions)         AS gross_in_clean,
    (SELECT ROUND(SUM(gross_revenue)) FROM customers)            AS gross_in_table,
    (SELECT ROUND(SUM(cancelled_value)) FROM customers)          AS cancelled_in_table;

-- Cancellations from customers with no sales in the data are left out of the
-- customer table (their original orders were before Dec 2009). How much is that?
SELECT COUNT(DISTINCT customer_id) AS n_customers, ROUND(SUM(revenue)) AS cancelled_value
FROM cancellations
WHERE customer_id NOT IN (SELECT customer_id FROM customers);

-- Customers whose cancellations cancel out all their spend
SELECT COUNT(*) AS n_customers_net_zero_or_less
FROM customers
WHERE net_revenue <= 0;

-- What a typical customer looks like: 25th percentile, median, 75th percentile
SELECT 'orders' AS metric,
       QUANTILE_CONT(n_orders, 0.25) AS p25, MEDIAN(n_orders) AS median,
       QUANTILE_CONT(n_orders, 0.75) AS p75, ROUND(AVG(n_orders), 1) AS mean
FROM customers
UNION ALL
SELECT 'net revenue',
       ROUND(QUANTILE_CONT(net_revenue, 0.25)), ROUND(MEDIAN(net_revenue)),
       ROUND(QUANTILE_CONT(net_revenue, 0.75)), ROUND(AVG(net_revenue))
FROM customers
UNION ALL
SELECT 'avg order value',
       ROUND(QUANTILE_CONT(avg_order_value, 0.25)), ROUND(MEDIAN(avg_order_value)),
       ROUND(QUANTILE_CONT(avg_order_value, 0.75)), ROUND(AVG(avg_order_value))
FROM customers
UNION ALL
SELECT 'recency (days)',
       QUANTILE_CONT(recency_days, 0.25), MEDIAN(recency_days),
       QUANTILE_CONT(recency_days, 0.75), ROUND(AVG(recency_days))
FROM customers;

-- One-time buyers vs repeat buyers
SELECT
    CASE WHEN n_orders = 1 THEN 'One-time' ELSE 'Repeat' END AS buyer_type,
    COUNT(*)                                                 AS n_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct_customers,
    ROUND(SUM(net_revenue))                                  AS net_revenue,
    ROUND(100.0 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_revenue
FROM customers
GROUP BY buyer_type
ORDER BY buyer_type;

-- Ten biggest customers by net revenue
SELECT customer_id, country, n_orders, gross_revenue, cancelled_value,
       net_revenue, avg_order_value, recency_days
FROM customers
ORDER BY net_revenue DESC
LIMIT 10;

-- What this showed (run on 18 Nov 2026):
-- * 5,852 customers. Gross revenue reconciles to the clean table exactly.
--   Cancellations: -708,584 for customers in the table, plus -1,406 from 23 customers
--   with no sales in the data = -709,990, the full cancellations total.
-- * Net spend matters: customer 16446 is 168,473 gross but 2.90 net, and 12346 is
--   77,353 gross but 169 net. Both placed one huge order and cancelled it minutes later.
-- * 20 customers have net spend of zero or less. Step 4 leaves them out of RFM.
-- * Median customer: 3 orders, 840 net spend, 272 average order value, last bought
--   96 days before the snapshot. Means are far above medians, so spend is very skewed.
-- * One-time buyers are 27.6% of customers but only 3.3% of net revenue.
