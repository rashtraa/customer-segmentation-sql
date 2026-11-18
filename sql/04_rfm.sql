-- 04_rfm.sql
-- RFM segmentation: score every customer 1-5 on
--   R = recency   (how recently they bought; 5 = most recent)
--   F = frequency (how many orders;        5 = most orders)
--   M = monetary  (net spend;              5 = highest spend)
-- then group the scores into named segments a marketing team can act on.
-- Run with: python scripts/run_sql.py sql/*.sql   (needs the tables from steps 1-3)

-- Why frequency is not scored with NTILE:
-- NTILE cuts the list into 5 equal-sized groups, even if that means splitting
-- customers with the same value. 1,599 customers have exactly 1 order, which is
-- more than a fifth of the base, so NTILE gives some of them F=1 and others F=2
-- for no real reason. This query shows the problem.
WITH t AS (
    SELECT n_orders, NTILE(5) OVER (ORDER BY n_orders, customer_id) AS f_ntile
    FROM customers
    WHERE net_revenue > 0
)
SELECT n_orders, LIST(DISTINCT f_ntile ORDER BY f_ntile) AS ntile_scores_given, COUNT(*) AS n_customers
FROM t
WHERE n_orders <= 9
GROUP BY n_orders
ORDER BY n_orders;

-- RFM scores.
-- R and M take many different values, so NTILE works well for them.
-- customer_id is added to ORDER BY so ties are broken the same way every run.
-- F uses fixed bands instead, so customers with the same order count get the same score.
-- Customers whose cancellations wipe out all their spend (net <= 0) are left out.
CREATE OR REPLACE TABLE rfm AS
WITH scored AS (
    SELECT
        customer_id,
        recency_days,
        n_orders,
        net_revenue,
        NTILE(5) OVER (ORDER BY recency_days DESC, customer_id) AS r_score,  -- fewest days = 5
        CASE
            WHEN n_orders = 1  THEN 1
            WHEN n_orders = 2  THEN 2
            WHEN n_orders <= 4 THEN 3
            WHEN n_orders <= 9 THEN 4
            ELSE 5
        END                                                    AS f_score,
        NTILE(5) OVER (ORDER BY net_revenue, customer_id)      AS m_score    -- highest spend = 5
    FROM customers
    WHERE net_revenue > 0
)
SELECT
    *,
    CAST(r_score AS VARCHAR) || CAST(f_score AS VARCHAR) || CAST(m_score AS VARCHAR) AS rfm_code,
    -- Segments are set on R and F. M moves closely with F here
    -- (correlation of log orders and log spend is 0.85), so it is used as a check below.
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN '1 Champions'          -- recent and frequent
        WHEN r_score  = 3 AND f_score >= 4 THEN '2 Loyal'              -- frequent, a bit less recent
        WHEN r_score >= 4 AND f_score IN (2, 3) THEN '3 Potential loyalists' -- recent, a few orders
        WHEN r_score >= 4 AND f_score  = 1 THEN '4 New customers'      -- recent first order
        WHEN r_score  = 3 AND f_score <= 3 THEN '5 Need attention'     -- middling on both
        WHEN r_score <= 2 AND f_score >= 3 THEN '6 At risk'            -- used to buy often, gone quiet
        ELSE                                    '7 Lost'               -- long gone, few orders
    END AS segment
FROM scored;

-- What each recency score means in days
SELECT r_score, MIN(recency_days) AS from_days, MAX(recency_days) AS to_days, COUNT(*) AS n_customers
FROM rfm
GROUP BY r_score
ORDER BY r_score;

-- What each monetary score means in net spend
SELECT m_score, ROUND(MIN(net_revenue)) AS from_spend, ROUND(MAX(net_revenue)) AS to_spend, COUNT(*) AS n_customers
FROM rfm
GROUP BY m_score
ORDER BY m_score;

-- Segment summary: size, revenue share and typical behaviour
SELECT
    segment,
    COUNT(*)                                                          AS n_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct_customers,
    ROUND(SUM(net_revenue))                                           AS net_revenue,
    ROUND(100.0 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS pct_revenue,
    ROUND(MEDIAN(recency_days))                                       AS median_recency_days,
    MEDIAN(n_orders)                                                  AS median_orders,
    ROUND(MEDIAN(net_revenue))                                        AS median_spend,
    ROUND(AVG(m_score), 1)                                            AS avg_m_score
FROM rfm
GROUP BY segment
ORDER BY segment;

-- What this showed (run on 18 Nov 2026), 5,832 customers with net spend > 0:
-- * Score bands. R: 1-20 days = 5, up to 409-739 days = 1. F: 1, 2, 3-4, 5-9, 10+ orders.
--   M: under ~278 = 1, over ~2,850 = 5.
--   NTILE still splits ties at the exact cut-off values of R and M (e.g. 409 days
--   appears in R1 and R2). That only affects customers sitting on a boundary.
-- * Champions: 23.8% of customers, 69.5% of net revenue (median 11 orders,
--   last order 17 days ago).
-- * At risk: 714 customers (12.2%) with 8.4% of revenue (about 1.37m). Median 4 orders
--   but no order for a year. The clearest win-back target.
-- * Lost: 27.8% of customers but only 4.1% of revenue. Mostly one-time buyers
--   from over a year ago.
-- * Average M score falls steadily from Champions (4.5) to Lost (1.7), so segments
--   built on R and F also sort customers by spend.
