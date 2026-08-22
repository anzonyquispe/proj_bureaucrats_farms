#!/usr/bin/env python3
"""Audit treatment spells and cohort composition in a protest stack."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import duckdb


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--threads", type=int, default=8)
    parser.add_argument("--memory-limit", default="20GB")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(str(args.database))
    con.execute(f"SET threads = {args.threads}")
    con.execute(f"SET memory_limit = '{args.memory_limit}'")
    exists = con.execute(
        "SELECT count(*) FROM information_schema.tables WHERE table_name='audit'"
    ).fetchone()[0]
    if args.rebuild or not exists:
        con.execute("DROP TABLE IF EXISTS audit")
        con.execute(
            """
            CREATE TABLE audit AS
            SELECT
                CAST(unique_small_grid_id AS BIGINT) AS unique_small_grid_id,
                province,
                CAST(ac_uq_id AS BIGINT) AS ac_uq_id,
                CAST(election_year AS INTEGER) AS election_year,
                CAST(protest5km AS TINYINT) AS protest5km,
                CAST(treat AS TINYINT) AS treat,
                CAST(post AS TINYINT) AS post,
                CAST(cohort AS BIGINT) AS cohort,
                CAST(relative_monthyear AS BIGINT) AS relative_monthyear,
                CAST(relative_year AS BIGINT) AS relative_year,
                CAST(cohort_election_year AS INTEGER) AS cohort_election_year,
                CAST(cohort_id AS BIGINT) AS cohort_id,
                CAST(cohort_term_start AS BIGINT) AS cohort_term_start,
                CAST(cohort_analysis_max AS BIGINT) AS cohort_analysis_max
            FROM read_csv_auto(?, header=true, sample_size=100000, all_varchar=true)
            """,
            [str(args.input)],
        )
        con.execute("ANALYZE audit")

    con.execute(
        """
        CREATE OR REPLACE TEMP VIEW treated_provinces AS
        SELECT DISTINCT cohort_id, province
        FROM audit
        WHERE treat = 1
        """
    )

    overall = con.execute(
        """
        SELECT
            count(*) AS rows,
            count(DISTINCT cohort_id) AS cohorts,
            count(DISTINCT unique_small_grid_id) AS grids,
            count(DISTINCT (cohort_id, unique_small_grid_id)) AS grid_cohorts,
            count_if(treat=1) AS treated_rows,
            count_if(treat=0) AS control_rows
        FROM audit
        """
    ).fetchdf()

    violations = con.execute(
        """
        SELECT
            count_if(treat=1 AND relative_monthyear>=0
                     AND protest5km IS DISTINCT FROM 1) AS treated_post_zero_rows,
            count(DISTINCT CASE WHEN treat=1 AND relative_monthyear>=0
                                      AND protest5km IS DISTINCT FROM 1
                                THEN (cohort_id, unique_small_grid_id) END)
                AS treated_post_zero_units,
            count_if(treat=1 AND relative_monthyear<0
                     AND protest5km IS DISTINCT FROM 0) AS treated_pre_one_rows,
            count_if(treat=1 AND relative_monthyear=0
                     AND protest5km IS DISTINCT FROM 1) AS invalid_switch_rows,
            count_if(election_year IS DISTINCT FROM cohort_election_year)
                AS rows_outside_cohort_election_year,
            count_if(treat=1 AND election_year IS DISTINCT FROM cohort_election_year)
                AS treated_rows_outside_cohort_election_year,
            count_if(treat=0 AND election_year IS DISTINCT FROM cohort_election_year)
                AS control_rows_outside_cohort_election_year
        FROM audit
        """
    ).fetchdf()

    cohort_summary = con.execute(
        """
        SELECT
            cohort_id,
            min(cohort) AS cohort,
            min(cohort_election_year) AS cohort_election_year,
            min(cohort_term_start) AS cohort_term_start,
            min(cohort_analysis_max) AS cohort_analysis_max,
            count(DISTINCT province) AS provinces_all,
            count(DISTINCT province) FILTER (WHERE treat=1) AS provinces_treated,
            count(DISTINCT province) FILTER (WHERE treat=0) AS provinces_control,
            count(DISTINCT election_year) AS row_election_years,
            count(DISTINCT unique_small_grid_id) FILTER (WHERE treat=1)
                AS treated_grids,
            count(DISTINCT unique_small_grid_id) FILTER (WHERE treat=0)
                AS control_grids,
            count_if(treat=1 AND relative_monthyear>=0
                     AND protest5km IS DISTINCT FROM 1) AS treated_post_zero_rows,
            count_if(election_year IS DISTINCT FROM cohort_election_year)
                AS wrong_term_rows
        FROM audit
        GROUP BY cohort_id
        ORDER BY cohort_id
        """
    ).fetchdf()

    control_province = con.execute(
        """
        SELECT
            count(*) AS control_rows_not_in_a_treated_province,
            count(DISTINCT (a.cohort_id, a.unique_small_grid_id))
                AS control_units_not_in_a_treated_province,
            count(DISTINCT a.cohort_id) AS affected_cohorts
        FROM audit a
        WHERE a.treat=0
          AND NOT EXISTS (
              SELECT 1 FROM treated_provinces t
              WHERE t.cohort_id=a.cohort_id AND t.province=a.province
          )
        """
    ).fetchdf()

    switch_units = con.execute(
        """
        SELECT
            cohort_id,
            unique_small_grid_id,
            min(relative_monthyear) FILTER (WHERE protest5km=1) AS first_one,
            count_if(relative_monthyear=0) AS rows_at_switch,
            count_if(relative_monthyear=0 AND protest5km=1) AS ones_at_switch,
            count_if(relative_monthyear>=0 AND protest5km=0) AS post_zero_rows
        FROM audit
        WHERE treat=1
        GROUP BY cohort_id, unique_small_grid_id
        HAVING first_one IS DISTINCT FROM 0
            OR rows_at_switch <> 1
            OR ones_at_switch <> 1
            OR post_zero_rows <> 0
        ORDER BY cohort_id, unique_small_grid_id
        """
    ).fetchdf()

    province_arm = con.execute(
        """
        SELECT
            cohort_id,
            min(cohort) AS cohort,
            min(cohort_election_year) AS cohort_election_year,
            province,
            treat,
            count(DISTINCT unique_small_grid_id) AS grids,
            count(*) AS rows
        FROM audit
        GROUP BY cohort_id, province, treat
        ORDER BY cohort_id, treat DESC, province
        """
    ).fetchdf()

    problematic = cohort_summary[
        (cohort_summary["provinces_all"] != 1)
        | (cohort_summary["provinces_treated"] != 1)
        | (cohort_summary["row_election_years"] != 1)
        | (cohort_summary["treated_post_zero_rows"] != 0)
        | (cohort_summary["wrong_term_rows"] != 0)
    ]

    overall.to_csv(args.output_directory / "overall.csv", index=False)
    violations.to_csv(args.output_directory / "violations.csv", index=False)
    cohort_summary.to_csv(args.output_directory / "cohort_summary.csv", index=False)
    problematic.to_csv(args.output_directory / "problematic_cohorts.csv", index=False)
    control_province.to_csv(
        args.output_directory / "control_province_mismatches.csv", index=False
    )
    switch_units.to_csv(args.output_directory / "invalid_treated_switches.csv", index=False)
    province_arm.to_csv(args.output_directory / "province_by_cohort_arm.csv", index=False)

    result = {
        "overall": overall.iloc[0].to_dict(),
        "violations": violations.iloc[0].to_dict(),
        "cohort_composition": {
            "cohorts_with_multiple_provinces": int(
                (cohort_summary["provinces_all"] > 1).sum()
            ),
            "cohorts_with_multiple_treated_provinces": int(
                (cohort_summary["provinces_treated"] > 1).sum()
            ),
            "cohorts_with_multiple_row_election_years": int(
                (cohort_summary["row_election_years"] > 1).sum()
            ),
        },
        "control_province": control_province.iloc[0].to_dict(),
        "invalid_treated_grid_cohorts": int(len(switch_units)),
    }
    print(json.dumps(result, indent=2, default=int))
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
