-- 05_segment_products.sql
-- Which products does each RFM segment buy? Useful for deciding what to put in
-- front of each group, e.g. which products to feature in a win-back email.
-- Run with: python scripts/run_sql.py sql/*.sql   (needs the tables from steps 1-4)

-- Revenue and buyers for every segment-product pair, ranked within each segment.
-- PARTITION BY segment restarts the ranking for each segment, so every segment
-- gets its own 1, 2, 3 ...
CREATE OR REPLACE TABLE segment_products AS
WITH segment_size AS (
    SELECT segment, COUNT(*) AS n_customers
    FROM rfm
    GROUP BY segment
),
all_lines AS (
    -- Sales and cancellations stacked together, so product revenue is net.
    -- Without this, an 80,995-unit order cancelled 12 minutes later shows up
    -- as a segment's top product.
    SELECT customer_id, stock_code, description, revenue, TRUE  AS is_sale FROM clean_transactions
    UNION ALL
    SELECT customer_id, stock_code, description, revenue, FALSE AS is_sale FROM cancellations
),
segment_sales AS (
    SELECT
        r.segment,
        l.stock_code,
        MODE(l.description) FILTER (WHERE l.is_sale)           AS description,  -- a few codes have slightly different names
        SUM(l.revenue)                                         AS revenue,      -- net of cancellations
        COUNT(DISTINCT l.customer_id) FILTER (WHERE l.is_sale) AS n_buyers
    FROM all_lines l
    JOIN rfm r USING (customer_id)
    GROUP BY r.segment, l.stock_code
    HAVING COUNT(*) FILTER (WHERE l.is_sale) > 0                -- products the segment actually bought
)
SELECT
    s.segment,
    ROW_NUMBER() OVER (PARTITION BY s.segment ORDER BY s.revenue DESC) AS rank_in_segment,
    s.stock_code,
    s.description,
    ROUND(s.revenue)                                                   AS revenue,
    s.n_buyers,
    ROUND(100.0 * s.n_buyers / z.n_customers, 1)                       AS pct_of_segment_bought
FROM segment_sales s
JOIN segment_size z USING (segment);

-- Top 5 products in each segment
SELECT segment, rank_in_segment AS rnk, description, revenue, n_buyers, pct_of_segment_bought
FROM segment_products
WHERE rank_in_segment <= 5
ORDER BY segment, rank_in_segment;

-- Products At risk customers used to buy most widely.
-- Ranked by how many of them bought it, not revenue: a product most of the
-- segment knows is a better hook for a win-back email than one big order.
SELECT description, n_buyers, pct_of_segment_bought, revenue
FROM segment_products
WHERE segment = '6 At risk'
ORDER BY n_buyers DESC
LIMIT 5;

-- What this showed (run on 18 Nov 2026):
-- * The same few bestsellers top almost every segment: the Regency 3-tier cakestand
--   and the white hanging heart T-light holder.
-- * Products At risk customers knew best: the T-light holder (35% of the segment
--   bought it) and the cakestand (24%). These are the obvious products to feature in
--   a win-back email.
-- * Ranking by revenue alone can mislead: Need attention's top product is a picnic
--   basket worth about 40k, bought by only 13 customers. Share of segment that bought
--   a product is the better guide for a campaign.
-- * Product revenue adds up to 16,363,247, against 16,361,548 net revenue in rfm.
--   The 1,699 gap is cancellations of products a customer never bought in this
--   data (bought before Dec 2009), dropped by the HAVING clause.
