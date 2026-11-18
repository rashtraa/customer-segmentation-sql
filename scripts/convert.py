import os, sys, pandas as pd
src, out = sys.argv[1], sys.argv[2]
sheets = pd.read_excel(src, sheet_name=None, dtype={"Invoice": str, "StockCode": str})
for name, df in sheets.items():
    print(name, df.shape, list(df.columns))
df = pd.concat(sheets.values(), ignore_index=True)
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)  # create the output folder if missing
df.to_csv(out, index=False)
print("total", df.shape)
