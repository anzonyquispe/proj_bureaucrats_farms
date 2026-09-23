#!/usr/bin/env python3
"""Build reproducible unit-level samples while retaining complete panels."""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_sample(
    con: duckdb.DuckDBPyConnection,
    *,
    input_csv: Path,
    output_csv: Path,
    rate: float,
    seed: int,
    cohorts: list[str] | None,
    choose_two_random_cohorts: bool,
) -> list[str]:
    con.execute("DROP VIEW IF EXISTS source_panel")
    con.execute("DROP TABLE IF EXISTS source_units")
    con.execute("DROP TABLE IF EXISTS sampled_units")
    con.execute(
        f"CREATE TEMP VIEW source_panel AS "
        f"SELECT * FROM read_csv_auto({quote(str(input_csv))}, header=true)"
    )
    columns = {row[0] for row in con.execute("DESCRIBE source_panel").fetchall()}
    required = {"unique_small_grid_id", "ac_uq_id", "cohort", "treat"}
    missing = sorted(required - columns)
    if missing:
        raise ValueError(f"{input_csv.name} is missing columns: {missing}")

    con.execute(
        """
        CREATE TEMP TABLE source_units AS
        SELECT unique_small_grid_id, ac_uq_id, cohort,
               CAST(MIN(CAST(treat AS INTEGER)) AS INTEGER) AS treat
        FROM source_panel
        GROUP BY unique_small_grid_id, ac_uq_id, cohort
        HAVING COUNT(DISTINCT treat) = 1
        """
    )
    inconsistent = con.execute(
        """
        SELECT COUNT(*) FROM (
          SELECT 1 FROM source_panel
          GROUP BY unique_small_grid_id, ac_uq_id, cohort
          HAVING COUNT(DISTINCT treat) <> 1
        )
        """
    ).fetchone()[0]
    if inconsistent:
        raise ValueError(f"Treatment changes within {inconsistent} stacked units.")

    if choose_two_random_cohorts and not cohorts:
        cohorts = [
            str(row[0])
            for row in con.execute(
                """
                SELECT cohort
                FROM source_units
                GROUP BY cohort
                HAVING COUNT(*) FILTER (WHERE treat = 1) > 0
                   AND COUNT(*) FILTER (WHERE treat = 0) > 0
                ORDER BY hash(?, cohort), cohort
                LIMIT 2
                """,
                [seed],
            ).fetchall()
        ]
        if len(cohorts) != 2:
            raise ValueError("Fewer than two cohorts contain treated and control units.")

    cohort_filter = "TRUE"
    if cohorts:
        cohort_values = ", ".join(quote(value) for value in cohorts)
        cohort_filter = f"CAST(cohort AS VARCHAR) IN ({cohort_values})"

    con.execute(
        f"""
        CREATE TEMP TABLE sampled_units AS
        WITH eligible AS (
          SELECT *,
            ROW_NUMBER() OVER (
              PARTITION BY cohort, treat
              ORDER BY hash(
                {seed}, unique_small_grid_id, ac_uq_id, cohort, treat
              )
            ) AS sample_rank,
            COUNT(*) OVER (PARTITION BY cohort, treat) AS stratum_units
          FROM source_units
          WHERE {cohort_filter}
        )
        SELECT unique_small_grid_id, ac_uq_id, cohort, treat,
               sample_rank, stratum_units
        FROM eligible
        WHERE sample_rank <= GREATEST(1, CEIL(stratum_units * {rate}))
        """
    )
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    con.execute(
        f"""
        COPY (
          SELECT p.*
          FROM source_panel p
          SEMI JOIN sampled_units u
            ON p.unique_small_grid_id = u.unique_small_grid_id
           AND p.ac_uq_id = u.ac_uq_id
           AND p.cohort = u.cohort
           AND CAST(p.treat AS INTEGER) = u.treat
        ) TO {quote(str(output_csv))}
        (HEADER, DELIMITER ',')
        """
    )
    return cohorts or []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--intermediate", type=Path, required=True)
    parser.add_argument("--politician-cohorts", default="")
    parser.add_argument("--seed", type=int, default=20260811)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--memory-limit", default="24GB")
    args = parser.parse_args()

    cohorts = [x.strip() for x in args.politician_cohorts.split(",") if x.strip()]
    if cohorts and len(cohorts) != 2:
        raise ValueError("--politician-cohorts must contain exactly two values.")

    con = duckdb.connect()
    con.execute(f"SET threads={args.threads}")
    con.execute(f"SET memory_limit={quote(args.memory_limit)}")
    selected = build_sample(
        con,
        input_csv=args.intermediate / "politicians_characteristics.csv",
        output_csv=args.intermediate / "politicians_characteristics_sample.csv",
        rate=0.02,
        seed=args.seed,
        cohorts=cohorts or None,
        choose_two_random_cohorts=True,
    )
    print("Politician cohorts:", ", ".join(selected))
    build_sample(
        con,
        input_csv=args.intermediate / "stacked_data_protest5km.csv",
        output_csv=args.intermediate / "stacked_data_protest5km_sample.csv",
        rate=0.01,
        seed=args.seed,
        cohorts=None,
        choose_two_random_cohorts=False,
    )
    for filename in (
        "politicians_characteristics_sample.csv",
        "stacked_data_protest5km_sample.csv",
    ):
        path = args.intermediate / filename
        rows, units = con.execute(
            f"""
            SELECT COUNT(*), COUNT(DISTINCT (unique_small_grid_id, ac_uq_id, cohort))
            FROM read_csv_auto({quote(str(path))}, header=true)
            """
        ).fetchone()
        print(f"{path}: rows={rows:,}, stacked_units={units:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
