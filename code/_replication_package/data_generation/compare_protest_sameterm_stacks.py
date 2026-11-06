#!/usr/bin/env python3
"""Compare a rebuilt same-term protest stack with the RA's reference file.

Rows are matched on (cohort, cohort_election_year, unique_small_grid_id,
monthyear). The output directory receives:

  report.txt               verdict and headline numbers (also printed)
  columns.csv              columns present in each file
  overall.csv              rows, cohorts, grids and arms in each file
  cohorts.csv              per-cohort composition in each file
  unmatched_by_cohort.csv  rows present in only one file, by cohort and arm
  unmatched_samples.csv    first rows present in only one file
  value_mismatches.csv     disagreements on matched rows, by column

The structure is identical when no row is unmatched and the design columns
(treat, post, event time, cohort constants) agree on every matched row. Other
columns are reported separately, since they can move with master updates.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
from pathlib import Path
from typing import Sequence

import duckdb
import pandas as pd

from build_all_stacked_datasets_duckdb import default_intermediate


REFERENCE_NAME = "stacked_data_protest5km_election_sameterm.csv"
REFERENCE_SUBDIRECTORIES = ("", "cohortes_protest_term", "cohorts_protest_term")
KEYS = ("cohort", "cohort_election_year", "unique_small_grid_id", "monthyear")
DESIGN_COLUMNS = (
    "treat",
    "post",
    "relative_monthyear",
    "relative_year",
    "cohort_id",
    "cohort_term_start",
    "cohort_analysis_max",
)
NUMERIC_TOLERANCE = 1e-6


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def qstr(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def num(expression: str) -> str:
    return f"TRY_CAST(TRY_CAST({expression} AS DOUBLE) AS BIGINT)"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--intermediate", type=Path, default=default_intermediate())
    parser.add_argument("--reference", type=Path, default=None)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--treatment-col", default="protest5km")
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=Path(__file__).resolve().parent
        / "logs"
        / "data_generation"
        / "protest_sameterm_comparison",
    )
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--reload-reference", action="store_true")
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="60GB")
    return parser.parse_args(argv)


def find_reference(intermediate: Path) -> Path:
    candidates = [intermediate / sub / REFERENCE_NAME for sub in REFERENCE_SUBDIRECTORIES]
    for path in candidates:
        if path.is_file():
            return path
    raise FileNotFoundError(
        "RA reference not found in: " + ", ".join(str(p) for p in candidates)
    )


def load_tables(con: duckdb.DuckDBPyConnection, args: argparse.Namespace) -> None:
    exists = con.execute(
        "SELECT count(*) FROM information_schema.tables WHERE table_name = 'ref'"
    ).fetchone()[0]
    if args.reload_reference or not exists:
        logging.info("Loading reference CSV: %s", args.reference)
        con.execute("DROP TABLE IF EXISTS ref")
        con.execute(
            f"""
            CREATE TABLE ref AS
            SELECT * FROM read_csv_auto({qstr(args.reference)}, header=true,
                                        sample_size=100000, all_varchar=true)
            """
        )
    else:
        logging.info("Reusing the reference table stored in %s", args.database)
    con.execute(
        f"CREATE OR REPLACE VIEW cand AS SELECT * FROM read_parquet({qstr(args.candidate)})"
    )


def columns_of(con: duckdb.DuckDBPyConnection, table: str) -> dict[str, str]:
    return {
        row[0]: row[1]
        for row in con.execute(f"DESCRIBE SELECT * FROM {table}").fetchall()
    }


def keyed_view(con: duckdb.DuckDBPyConnection, name: str, table: str) -> None:
    keys = ",\n            ".join(f"{num(qid(k))} AS k_{k}" for k in KEYS)
    con.execute(
        f"""
        CREATE OR REPLACE VIEW {name} AS
        SELECT *, {keys}, {num('treat')} AS k_treat
        FROM {table}
        """
    )


def summary(con: duckdb.DuckDBPyConnection, view: str) -> dict[str, int]:
    row = con.execute(
        f"""
        SELECT
            count(*),
            count(DISTINCT (k_cohort, k_cohort_election_year)),
            count(DISTINCT k_unique_small_grid_id),
            count(DISTINCT (k_cohort, k_cohort_election_year, k_unique_small_grid_id)),
            count_if(k_treat = 1),
            count_if(k_treat = 0),
            count(*) - count(DISTINCT (k_cohort, k_cohort_election_year,
                                       k_unique_small_grid_id, k_monthyear))
        FROM {view}
        """
    ).fetchone()
    labels = (
        "rows",
        "cohorts",
        "grids",
        "grid_cohorts",
        "treated_rows",
        "control_rows",
        "duplicated_keys",
    )
    return dict(zip(labels, (int(v) for v in row)))


def cohort_table(con: duckdb.DuckDBPyConnection, view: str) -> pd.DataFrame:
    return con.execute(
        f"""
        SELECT
            k_cohort AS cohort,
            k_cohort_election_year AS cohort_election_year,
            min({num('cohort_id')}) AS cohort_id,
            min({num('cohort_term_start')}) AS term_start,
            min({num('cohort_analysis_max')}) AS analysis_max,
            count(DISTINCT k_unique_small_grid_id) FILTER (WHERE k_treat = 1)
                AS treated_grids,
            count(DISTINCT k_unique_small_grid_id) FILTER (WHERE k_treat = 0)
                AS control_grids,
            count(*) AS rows
        FROM {view}
        GROUP BY 1, 2
        """
    ).fetchdf()


def unmatched(con: duckdb.DuckDBPyConnection) -> tuple[pd.DataFrame, pd.DataFrame]:
    join_keys = " AND ".join(f"a.k_{k} = b.k_{k}" for k in KEYS)
    pieces = []
    samples = []
    for label, left, right in (("only_reference", "r", "c"), ("only_candidate", "c", "r")):
        anti = f"""
            SELECT a.* FROM {left} a
            WHERE NOT EXISTS (SELECT 1 FROM {right} b WHERE {join_keys})
        """
        pieces.append(
            con.execute(
                f"""
                SELECT '{label}' AS side, k_cohort AS cohort,
                       k_cohort_election_year AS cohort_election_year,
                       k_treat AS treat, count(*) AS rows,
                       count(DISTINCT k_unique_small_grid_id) AS grids
                FROM ({anti})
                GROUP BY ALL ORDER BY cohort, cohort_election_year, treat
                """
            ).fetchdf()
        )
        samples.append(
            con.execute(
                f"""
                SELECT '{label}' AS side, k_cohort AS cohort,
                       k_cohort_election_year AS cohort_election_year,
                       k_unique_small_grid_id AS unique_small_grid_id,
                       k_monthyear AS monthyear, k_treat AS treat
                FROM ({anti})
                ORDER BY cohort, cohort_election_year, unique_small_grid_id, monthyear
                LIMIT 50
                """
            ).fetchdf()
        )
    return pd.concat(pieces, ignore_index=True), pd.concat(samples, ignore_index=True)


def value_mismatches(
    con: duckdb.DuckDBPyConnection, common: list[str], candidate_types: dict[str, str]
) -> pd.DataFrame:
    numeric_types = ("INT", "DOUBLE", "FLOAT", "DECIMAL", "BIGINT", "HUGEINT")
    expressions = []
    for column in common:
        left, right = f"r.{qid(column)}", f"c.{qid(column)}"
        if any(t in candidate_types[column].upper() for t in numeric_types):
            lv, rv = f"TRY_CAST({left} AS DOUBLE)", f"TRY_CAST({right} AS DOUBLE)"
            differs = (
                f"(({lv} IS NULL) <> ({rv} IS NULL) OR abs({lv} - {rv}) > "
                f"{NUMERIC_TOLERANCE} * greatest(1, abs({rv})))"
            )
        else:
            differs = (
                f"NULLIF(trim(CAST({left} AS VARCHAR)), '') IS DISTINCT FROM "
                f"NULLIF(trim(CAST({right} AS VARCHAR)), '')"
            )
        expressions.append(f"count_if({differs}) AS {qid(column)}")
    join_keys = " AND ".join(f"r.k_{k} = c.k_{k}" for k in KEYS)
    row = con.execute(
        f"""
        SELECT count(*) AS matched_rows, {', '.join(expressions)}
        FROM r JOIN c ON {join_keys}
        """
    ).fetchdf()
    matched = int(row.loc[0, "matched_rows"])
    return pd.DataFrame(
        {
            "column": common,
            "design_column": [c in DESIGN_COLUMNS for c in common],
            "matched_rows": matched,
            "mismatches": [int(row.loc[0, c]) for c in common],
        }
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(message)s")
    args.intermediate = args.intermediate.resolve()
    args.reference = (args.reference or find_reference(args.intermediate)).resolve()
    args.candidate = args.candidate.resolve()
    args.database = (
        args.database or args.intermediate / "protest_sameterm_comparison.db"
    ).resolve()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(str(args.database))
    temp_directory = args.database.with_suffix(".tmp")
    temp_directory.mkdir(exist_ok=True)
    con.execute(f"SET threads={int(args.threads)}")
    con.execute(f"SET memory_limit={qstr(args.memory_limit)}")
    con.execute(f"SET temp_directory={qstr(temp_directory)}")
    try:
        load_tables(con, args)
        ref_columns = columns_of(con, "ref")
        cand_columns = columns_of(con, "cand")
        missing_keys = [
            k for k in (*KEYS, "treat") if k not in ref_columns or k not in cand_columns
        ]
        if missing_keys:
            raise ValueError("Key columns missing in one file: " + ", ".join(missing_keys))
        keyed_view(con, "r", "ref")
        keyed_view(con, "c", "cand")

        columns = pd.DataFrame(
            {"column": sorted(set(ref_columns) | set(cand_columns))}
        ).assign(
            in_reference=lambda d: d["column"].isin(ref_columns),
            in_candidate=lambda d: d["column"].isin(cand_columns),
        )
        columns.to_csv(args.output_directory / "columns.csv", index=False)

        logging.info("Summarising both files")
        ref_summary, cand_summary = summary(con, "r"), summary(con, "c")
        overall = pd.DataFrame(
            {
                "metric": list(ref_summary),
                "reference": list(ref_summary.values()),
                "candidate": [cand_summary[k] for k in ref_summary],
            }
        ).assign(difference=lambda d: d["candidate"] - d["reference"])
        overall.to_csv(args.output_directory / "overall.csv", index=False)

        cohorts = cohort_table(con, "r").merge(
            cohort_table(con, "c"),
            on=["cohort", "cohort_election_year"],
            how="outer",
            suffixes=("_reference", "_candidate"),
            indicator=True,
        )
        same = pd.concat(
            [
                cohorts[f"{m}_reference"].eq(cohorts[f"{m}_candidate"])
                for m in ("cohort_id", "term_start", "analysis_max",
                          "treated_grids", "control_grids", "rows")
            ],
            axis=1,
        ).all(axis=1)
        cohorts["identical"] = cohorts["_merge"].eq("both") & same
        cohorts = cohorts.sort_values(["cohort", "cohort_election_year"])
        cohorts.to_csv(args.output_directory / "cohorts.csv", index=False)

        logging.info("Matching rows")
        by_cohort, samples = unmatched(con)
        by_cohort.to_csv(args.output_directory / "unmatched_by_cohort.csv", index=False)
        samples.to_csv(args.output_directory / "unmatched_samples.csv", index=False)

        logging.info("Comparing values on matched rows")
        common = [
            c for c in cand_columns if c in ref_columns and c not in KEYS
        ]
        mismatches = value_mismatches(con, common, cand_columns)
        mismatches.to_csv(args.output_directory / "value_mismatches.csv", index=False)

        treatment = args.treatment_col
        censoring = (
            con.execute(
                f"SELECT count_if(k_treat = 0 AND {num(qid(treatment))} = 1) FROM r"
            ).fetchone()[0]
            if treatment in ref_columns
            else None
        )
    finally:
        con.close()
        shutil.rmtree(temp_directory, ignore_errors=True)

    only_ref = int(by_cohort.loc[by_cohort["side"] == "only_reference", "rows"].sum())
    only_cand = int(by_cohort.loc[by_cohort["side"] == "only_candidate", "rows"].sum())
    design = mismatches[mismatches["design_column"]]
    other = mismatches[~mismatches["design_column"] & (mismatches["mismatches"] > 0)]
    identical = (
        only_ref == 0
        and only_cand == 0
        and ref_summary["duplicated_keys"] == 0
        and cand_summary["duplicated_keys"] == 0
        and int(design["mismatches"].sum()) == 0
        and len(design) == len(DESIGN_COLUMNS)
    )

    lines = [
        f"Reference: {args.reference}",
        f"Candidate: {args.candidate}",
        "",
        "VERDICT: " + ("STRUCTURE IDENTICAL" if identical else "DIFFERENT"),
        "",
        overall.to_string(index=False),
        "",
        f"Cohorts identical: {int(cohorts['identical'].sum())} of {len(cohorts)}",
        f"Rows only in reference: {only_ref:,}",
        f"Rows only in candidate: {only_cand:,}",
        "",
        "Design columns (mismatches on matched rows):",
        design[["column", "mismatches"]].to_string(index=False),
        "",
        "Other columns with mismatches:",
        other[["column", "mismatches"]].to_string(index=False) if len(other) else "  none",
        "",
        "Columns only in reference: "
        + (", ".join(columns.loc[~columns["in_candidate"], "column"]) or "none"),
        "Columns only in candidate: "
        + (", ".join(columns.loc[~columns["in_reference"], "column"]) or "none"),
        "",
        f"Reference control rows with {treatment} = 1 (uncensored controls): "
        + ("column absent" if censoring is None else f"{censoring:,}"),
    ]
    report = "\n".join(lines)
    (args.output_directory / "report.txt").write_text(report + "\n", encoding="utf-8")
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
