"""06_kmeans.py
K-means clustering on recency, frequency and spend, compared with the RFM segments.

RFM (step 4) uses rules we wrote ourselves. K-means finds groups from the data alone:
it puts customers who are close to each other on the three measures in the same group.
If both methods find similar groups, the segments are not just an artefact of our rules.

Run from the project folder, after the SQL steps:
    python analysis/06_kmeans.py
"""
import os
# Stops a harmless joblib warning on newer Windows versions, where the tool it uses
# to count CPU cores no longer exists. Has no effect on the results.
os.environ.setdefault("LOKY_MAX_CPU_COUNT", str(os.cpu_count()))

import duckdb
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # save charts to file without opening a window
import matplotlib.pyplot as plt
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

pd.set_option("display.width", 250)
pd.set_option("display.max_columns", None)

# 1. Load the customers we scored in step 4 (net spend > 0)
con = duckdb.connect("retail.duckdb")
df = con.execute("""
    SELECT customer_id, recency_days, n_orders, net_revenue, segment
    FROM rfm
""").df()
print(f"Customers: {len(df)}\n")

# 2. Prepare the three features
# Log: all three are very skewed (mean spend 2,796 vs median 840). Without the log,
#      a handful of huge customers would pull the clusters around.
# Scale: days, order counts and pounds are in different units. StandardScaler puts
#      each on mean 0, standard deviation 1, so no single measure dominates the distances.
X = np.log(df[["recency_days", "n_orders", "net_revenue"]])
X_scaled = StandardScaler().fit_transform(X)

# 3. Choose the number of clusters k
# Inertia: total distance of customers to their cluster centre. Always falls as k
#          grows, so we look for the "elbow" where it stops falling fast.
# Silhouette: from -1 to 1, how much closer customers are to their own cluster than
#          to the next one. Higher is better.
rows = []
for k in range(2, 9):
    km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X_scaled)
    rows.append({"k": k,
                 "inertia": round(km.inertia_),
                 "silhouette": round(silhouette_score(X_scaled, km.labels_), 3)})
k_table = pd.DataFrame(rows)
print("Choosing k:")
print(k_table.to_string(index=False), "\n")

fig, axes = plt.subplots(1, 2, figsize=(10, 4))
axes[0].plot(k_table["k"], k_table["inertia"], marker="o", color="black")
axes[0].set(title="Elbow: inertia by k", xlabel="k (number of clusters)", ylabel="inertia")
axes[1].plot(k_table["k"], k_table["silhouette"], marker="o", color="black")
axes[1].set(title="Silhouette score by k", xlabel="k (number of clusters)", ylabel="silhouette")
fig.tight_layout()
fig.savefig("analysis/choosing_k.png", dpi=150)
print("Saved chart: analysis/choosing_k.png\n")

# 4. Fit the chosen model
# k = 2 has the best silhouette, but it only splits active from inactive customers,
# which is too coarse to act on. Among k >= 3, k = 4 scores best (0.364 vs 0.344
# for k = 3 and 0.335 for k = 5), and it sits near the elbow of the inertia curve.
K = 4
km = KMeans(n_clusters=K, n_init=10, random_state=42).fit(X_scaled)

# K-means numbers its clusters 0-3 in no particular order, and the order can change
# between computers. So we name clusters by their median spend instead.
names = ["A Best customers", "B Lapsing regulars", "C Recent, few orders", "D Inactive one-timers"]
order = (pd.Series(df["net_revenue"].values).groupby(km.labels_).median()
           .sort_values(ascending=False).index)
df["cluster"] = pd.Series(km.labels_).map(dict(zip(order, names)))

# 5. Describe each cluster in plain numbers (medians, because the data is skewed)
profile = (df.groupby("cluster")
             .agg(n_customers=("customer_id", "count"),
                  median_recency_days=("recency_days", "median"),
                  median_orders=("n_orders", "median"),
                  median_spend=("net_revenue", "median"),
                  net_revenue=("net_revenue", "sum")))
profile["pct_customers"] = (100 * profile["n_customers"] / profile["n_customers"].sum()).round(1)
profile["pct_revenue"] = (100 * profile["net_revenue"] / profile["net_revenue"].sum()).round(1)
profile["net_revenue"] = profile["net_revenue"].round()
print("Cluster profiles:")
print(profile.to_string(), "\n")

# 6. Compare with the RFM segments: where does each segment land?
print("RFM segment (rows) vs K-means cluster (columns), % of each segment:")
crosstab = pd.crosstab(df["segment"], df["cluster"], normalize="index").mul(100).round(1)
print(crosstab.to_string(), "\n")

# 7. Save the cluster labels back to the database, so SQL can use them
con.execute("CREATE OR REPLACE TABLE kmeans_clusters AS SELECT customer_id, cluster FROM df")
print("Saved table: kmeans_clusters")
con.close()
