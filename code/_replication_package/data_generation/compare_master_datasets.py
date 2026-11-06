#!/usr/bin/env python3
"""Check that two master datasets differ only in the expected columns.

Confirms that a master rebuilt with another protest grid file (e.g.
0_master_dataset_protest2.parquet) equals 0_master_dataset.parquet in every
grid-month and every column except the protest columns. Exits with status 1
otherwise, so a cluster job stops before building stacks from a wrong master.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Sequence

import duckdb


KEYS = ("unique_small_grid_id", "year", "month")
PROTEST_COLUMNS = (
    "protest_id",
    "protest_place",
    "yr_pr_5km",
    "mt_pr_5km",
    "protest5km",
    "ac_area_tr",
)


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def qstr(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--allowed", nargs="+", default=list(PROTEST_COLUMNS))
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="60GB")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    con = duckdb.connect()
    con.execute(f"SET threads={int(args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute(f"CREATE VIEW r AS SELECT * FROM read_parquet({qstr(args.reference)})")
    con.execute(f"CREATE VIEW c AS SELECT * FROM read_parquet({qstr(args.candidate)})")
    ref_cols = [row[0] for row in con.execute("DESCRIBE r").fetchall()]
    cand_cols = [row[0] for row in con.execute("DESCRIBE c").fetchall()]
    common = [col for col in ref_cols if col in cand_cols and col not in KEYS]

    join = " AND ".join(f"r.{qid(k)} = c.{qid(k)}" for k in KEYS)
    ref_rows, cand_rows, matched = con.execute(
        f"SELECT (SELECT count(*) FROM r), (SELECT count(*) FROM c), "
        f"(SELECT count(*) FROM r JOIN c ON {join})"
    ).fetchone()
    mismatch_sql = ", ".join(
        f"count_if(r.{qid(col)} IS DISTINCT FROM c.{qid(col)})" for col in common
    )
    counts = con.execute(f"SELECT {mismatch_sql} FROM r JOIN c ON {join}").fetchone()
    mismatches = dict(zip(common, (int(v) for v in counts)))
    changed_grids = con.execute(
        f"""
        SELECT count(DISTINCT r.unique_small_grid_id)
        FROM r JOIN c ON {join}
        WHERE r.protest5km IS DISTINCT FROM c.protest5km
        """
    ).fetchone()[0] if "protest5km" in common else None
    con.close()

    unexpected = {col: n for col, n in mismatches.items() if n and col not in args.allowed}
    missing = sorted(set(ref_cols) ^ set(cand_cols))
    ok = ref_rows == cand_rows == matched and not unexpected and not missing

    lines = [
        f"Reference: {args.reference}",
        f"Candidate: {args.candidate}",
        "",
        "VERDICT: " + ("ONLY PROTEST COLUMNS DIFFER" if ok else "UNEXPECTED DIFFERENCES"),
        "",
        f"Rows: reference {ref_rows:,} | candidate {cand_rows:,} | matched {matched:,}",
        "Columns in only one file: " + (", ".join(missing) or "none"),
        "Unexpected column differences: "
        + (", ".join(f"{col} ({n:,} rows)" for col, n in unexpected.items()) or "none"),
        "",
        "Protest columns (rows that differ):",
        *(f"  {col}: {mismatches[col]:,}" for col in args.allowed if col in mismatches),
    ]
    if changed_grids is not None:
        lines.append(f"Grids whose protest5km history changes: {changed_grids:,}")
    report = "\n".join(lines)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report + "\n", encoding="utf-8")
    print(report)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
