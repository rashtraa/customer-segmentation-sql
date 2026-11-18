"""Run a .sql file against the project's DuckDB database and print each result.

Usage (from the project folder):
    python scripts/run_sql.py sql/01_load_and_profile.sql
    python scripts/run_sql.py sql/*.sql            (runs every step in order)
"""
import glob
import sys
import duckdb
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_columns", None)


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: python scripts/run_sql.py <file.sql> [more files]   or   sql/*.sql")
    # Expand wildcards ourselves, because the Windows shell doesn't
    paths = sorted(p for arg in sys.argv[1:] for p in (glob.glob(arg) or [arg]))
    con = duckdb.connect("retail.duckdb")
    for path in paths:
        print(f"\n===== {path} =====\n")
        run_file(con, path)
    con.close()


def run_file(con, path):
    with open(path, encoding="utf-8") as f:
        sql_text = f.read()

    # DuckDB's own parser splits the file into statements, so semicolons
    # inside comments or strings don't cause problems.
    for stmt in con.extract_statements(sql_text):
        result = con.execute(stmt.query)
        if "SELECT" in str(stmt.type):
            print(result.df().to_string(index=False), end="\n\n")
        else:
            # CREATE / DROP / INSERT: print one line instead of an empty table
            first_line = " ".join(l.strip() for l in stmt.query.splitlines()
                                  if l.strip() and not l.strip().startswith("--"))
            print("done:", first_line[:70] + "...")


if __name__ == "__main__":
    main()
