# Customer Segmentation of an Online Retailer in SQL

A small SQL project on two years of real transactions from a UK online gift retailer.
It cleans the raw data, builds one row per customer, and splits customers into RFM
segments (recency, frequency, monetary value) to show which groups bring in the revenue
and which ones a marketing team should try to win back. K-means clustering is then used
to check that the segments hold up when the groups are found from the data alone.

Tools: SQL (DuckDB) for the data work, Python (pandas, scikit-learn) for K-means clustering.

## Data

[Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii), UCI Machine
Learning Repository. 1,067,371 invoice lines, 1 Dec 2009 to 9 Dec 2011. Prices are in
pounds sterling. The data file is not included in this repo; download it from the link.

## Steps

| File | What it does |
|---|---|
| `sql/01_load_and_profile.sql` | Loads the data, counts rows, customers and products, finds missing values, cancellations and duplicates |
| `sql/02_clean.sql` | Removes bad rows one rule at a time and records how many rows each rule drops. Keeps cancellations in their own table |
| `sql/03_customers.sql` | Builds an orders table, then one row per customer: orders, spend net of cancellations, days since last order |
| `sql/04_rfm.sql` | Scores customers 1 to 5 on recency, frequency and spend, and groups them into 7 segments |
| `sql/05_segment_products.sql` | Ranks products within each segment by net revenue and by share of the segment that bought them |
| `analysis/06_kmeans.py` | K-means on log recency, orders and spend; picks k with the elbow and silhouette score; compares clusters with the RFM segments |

## Main findings

- **Data issues.** 1–9 Dec 2010 appears in both sheets of the source file, so 22,523 rows
  would be counted twice without removing duplicates. 22.8% of rows have no customer ID.
- **Cancellations change the picture.** Some customers placed one huge order and cancelled
  it minutes later. One customer's spend is 168,473 gross but 2.90 net. Spend is measured
  net of about 710k of cancellations.
- **Cleaning result.** 1,067,371 raw rows to 776,596 sales lines from 5,852 customers.
- **Revenue is concentrated.** Champions (recent, frequent buyers) are 23.8% of customers
  and bring in 69.5% of net revenue.
- **Win-back target.** 714 "At risk" customers used to order regularly (median 4 orders)
  but have not bought for about a year. Together they spent about 1.37m.
- **One-time buyers** are 27.6% of customers but 3.3% of revenue.
- **What to show At risk customers.** 35% of them bought the white hanging heart T-light
  holder and 24% the 3-tier cakestand, so these are the products to lead a win-back email with.
- **K-means agrees with the rules.** With 4 clusters, 93% of Lost customers fall in the
  inactive one-timer cluster, 89% of At risk in the lapsing regulars cluster, and 78% of
  Champions in the best customer cluster, which holds 21% of customers and 74% of revenue.

| Segment | Customers | % of customers | % of revenue |
|---|---|---|---|
| Champions | 1,387 | 23.8 | 69.5 |
| Loyal | 464 | 8.0 | 9.7 |
| Potential loyalists | 711 | 12.2 | 4.2 |
| New customers | 234 | 4.0 | 0.5 |
| Need attention | 702 | 12.0 | 3.6 |
| At risk | 714 | 12.2 | 8.4 |
| Lost | 1,620 | 27.8 | 4.1 |

## One design choice worth noting

Frequency is scored with fixed bands (1, 2, 3–4, 5–9, 10+ orders), not `NTILE(5)`.
1,599 customers have exactly one order, more than a fifth of the base, so `NTILE` would
give some of them a score of 1 and others a score of 2 for no reason. `04_rfm.sql` shows this.

## K-means clusters (k = 4)

k = 2 has the highest silhouette score but only separates active from inactive customers.
Among k = 3 to 8, k = 4 scores best (0.364) and sits near the elbow (`analysis/choosing_k.png`).

| Cluster | Customers | Median days since last order | Median orders | Median spend | % of revenue |
|---|---|---|---|---|---|
| Best customers | 1,207 | 17 | 13 | 4,732 | 73.9 |
| Lapsing regulars | 1,500 | 186 | 4 | 1,365 | 16.4 |
| Recent, few orders | 1,165 | 24 | 3 | 720 | 5.9 |
| Inactive one-timers | 1,960 | 398 | 1 | 259 | 3.7 |

## How to run

```
pip install duckdb pandas openpyxl
python scripts/convert.py online_retail_II.xlsx data/online_retail_raw.csv
pip install scikit-learn
python scripts/run_sql.py sql/*.sql
python analysis/06_kmeans.py
```
