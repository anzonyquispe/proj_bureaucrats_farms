#!/usr/bin/env python3
"""Generate the three production descriptive-statistics LaTeX tables."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

import duckdb
import pandas as pd
import pyreadstat


LOG = logging.getLogger("descriptive_tables")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--sample", default="")
    parser.add_argument("--threads", type=int, default=10)
    parser.add_argument("--memory-limit", default="100GB")
    return parser.parse_args()


def sql_path(path: Path) -> str:
    return str(path.resolve()).replace("'", "''")


def find_first(paths: list[Path]) -> Path:
    for path in paths:
        if path.exists():
            return path
    raise FileNotFoundError("None of these inputs exists:\n" + "\n".join(map(str, paths)))


def load_dta_lookup(con: duckdb.DuckDBPyConnection, name: str, path: Path,
                    columns: list[str]) -> None:
    frame, _ = pyreadstat.read_dta(str(path), usecols=columns)
    con.register(f"_{name}_frame", frame)
    con.execute(f"CREATE OR REPLACE TABLE {name} AS SELECT * FROM _{name}_frame")
    con.unregister(f"_{name}_frame")
    LOG.info("Loaded %s rows into %s", len(frame), name)


def fmt_number(value: object, integer: bool = False) -> str:
    if value is None or pd.isna(value):
        return ""
    if integer:
        return f"{int(value):,}"
    text = f"{float(value):,.3f}".rstrip("0").rstrip(".")
    return text


def summarize(con: duckdb.DuckDBPyConnection, table: str,
              rows: list[tuple[str, str, bool]]) -> list[list[str]]:
    expressions = ["count(*) AS total_n"]
    for index, (_, variable, continuous) in enumerate(rows):
        q = f'"{variable}"'
        expressions.extend([
            f"count({q}) AS n_{index}",
            f"count(DISTINCT {q}) AS u_{index}",
        ])
        if continuous:
            expressions.extend([
                f"avg({q}) AS mean_{index}",
                f"stddev_samp({q}) AS sd_{index}",
                f"min({q}) AS min_{index}",
                f"max({q}) AS max_{index}",
            ])
    result = con.execute(
        f"SELECT {', '.join(expressions)} FROM {table}"
    ).fetchone()
    names = [item[0] for item in con.description]
    stats = dict(zip(names, result))

    output: list[list[str]] = []
    for index, (label, _, continuous) in enumerate(rows):
        output.append([
            label,
            fmt_number(stats.get(f"mean_{index}")) if continuous else "",
            fmt_number(stats.get(f"sd_{index}")) if continuous else "",
            fmt_number(stats.get(f"min_{index}")) if continuous else "",
            fmt_number(stats.get(f"max_{index}")) if continuous else "",
            fmt_number(stats[f"n_{index}"], integer=True),
            fmt_number(stats[f"u_{index}"], integer=True),
        ])
    LOG.info("%s: %s observations", table, fmt_number(stats["total_n"], True))
    return output


def write_latex(path: Path, rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        r"\begin{tabular}{lrrrrrr}",
        r"\toprule",
        r" & Mean & SD & Min & Max & Observations & Unique Obs.\\",
        r"\midrule",
    ]
    lines.extend(" & ".join(row) + r"\\" for row in rows)
    lines.extend([r"\bottomrule", r"\end{tabular}", ""])
    path.write_text("\n".join(lines), encoding="utf-8")
    LOG.info("Generated %s", path)


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    sample = "" if args.sample in ("", "none") else args.sample
    intermediate = args.root / "data_output" / "intermediate"
    tables = args.output_root / "tables"
    database = intermediate / f"descriptive_statistics{sample}.duckdb"

    con = duckdb.connect(str(database))
    con.execute(f"SET threads={args.threads}")
    con.execute(f"SET memory_limit='{args.memory_limit}'")
    con.execute(f"SET temp_directory='{sql_path(intermediate / '_duckdb_tmp_descriptives')}'")
    con.execute("SET preserve_insertion_order=false")

    rural_path = intermediate / "ghs_grid_classification_2000.dta"
    area_path = intermediate / "grid_month_ac_area_tr.dta"
    load_dta_lookup(con, "rural_lookup", rural_path,
                    ["unique_small_grid_id", "is_rural"])
    load_dta_lookup(con, "area_lookup", area_path,
                    ["unique_small_grid_id", "month", "year", "ac_area_tr"])
    con.execute("""
        CREATE OR REPLACE TABLE rural_lookup_clean AS
        SELECT CAST(unique_small_grid_id AS VARCHAR) AS grid_key,
               max(is_rural) AS is_rural
        FROM rural_lookup GROUP BY 1
    """)
    con.execute("""
        CREATE OR REPLACE TABLE area_lookup_clean AS
        SELECT CAST(unique_small_grid_id AS VARCHAR) AS grid_key,
               CAST(month AS INTEGER) AS month,
               CAST(year AS INTEGER) AS year,
               max(ac_area_tr) AS ac_area_tr
        FROM area_lookup GROUP BY 1,2,3
    """)

    main_csv = intermediate / f"combined_dt_pop{sample}.csv"
    politician_csv = intermediate / f"politicians_characteristics_byprov{sample}.csv"
    protest_csv = find_first([
        intermediate / f"stacked_data_protest5km_election_sameterm{sample}.csv",
        intermediate / "cohortes_protest_term" / f"stacked_data_protest5km_election_sameterm{sample}.csv",
        intermediate / "cohorts_protest_term" / f"stacked_data_protest5km_election_sameterm{sample}.csv",
    ])
    for path in (main_csv, politician_csv):
        if not path.exists():
            raise FileNotFoundError(path)

    csv_options = "header=true, auto_detect=true, sample_size=1000000, null_padding=true"
    LOG.info("Building main descriptive sample")
    con.execute(f"""
        CREATE OR REPLACE TABLE desc_main AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id, p.province,
               p."count" AS fires, p.downup_ac_pop, p.av_wind_speed,
               p.wind_direction, p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(main_csv)}', {csv_options}) p
        JOIN rural_lookup_clean r
          ON CAST(p.unique_small_grid_id AS VARCHAR)=r.grid_key AND r.is_rural=1
        WHERE p.relative_monthyear BETWEEN -5 AND 6
          AND (p.year < 2022 OR (p.year=2022 AND p.month<=8))
          AND p."count" IS NOT NULL AND p.downup_ac_pop IS NOT NULL
          AND p.av_wind_speed IS NOT NULL AND p.wind_direction IS NOT NULL
          AND p.rice_prod_aclvl_ahigh IS NOT NULL AND p.cohort IS NOT NULL
          AND p.monthyear IS NOT NULL AND p.ac_uq_id IS NOT NULL
          AND p.unique_small_grid_id IS NOT NULL
    """)

    LOG.info("Building protest descriptive sample")
    con.execute(f"""
        CREATE OR REPLACE TABLE desc_protest AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id, p.province,
               a.ac_area_tr, p.cohort,
               concat(CAST(p.province AS VARCHAR),'|',CAST(p.election_year AS VARCHAR)) AS legislature,
               p.relative_year_bin,
               CAST((p.relative_year_bin>=0) AND (p.treat=1) AS INTEGER) AS protest,
               p."count"*1000 AS fires,
               p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(protest_csv)}', {csv_options}) p
        JOIN rural_lookup_clean r
          ON CAST(p.unique_small_grid_id AS VARCHAR)=r.grid_key AND r.is_rural=1
        JOIN area_lookup_clean a
          ON CAST(p.unique_small_grid_id AS VARCHAR)=a.grid_key
         AND p.month=a.month AND p.year=a.year
        WHERE p.relative_year_bin BETWEEN -4 AND 4
          AND (p.year < 2022 OR (p.year=2022 AND p.month<=8))
          AND p."count" IS NOT NULL AND p.treat IS NOT NULL
          AND p.downup_ac_pop IS NOT NULL AND p.wind_direction IS NOT NULL
          AND p.av_wind_speed IS NOT NULL AND p.rice_prod_aclvl_ahigh IS NOT NULL
          AND p.cohort_id IS NOT NULL AND p.election_year IS NOT NULL
          AND p.monthyear IS NOT NULL AND p.ac_uq_id IS NOT NULL
    """)

    LOG.info("Building politician descriptive sample")
    con.execute(f"""
        CREATE OR REPLACE TABLE desc_politician AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id, p.province,
               p.election_year, p.cohort,
               concat(CAST(p.province AS VARCHAR),'|',CAST(p.election_year AS VARCHAR)) AS legislature,
               p.self_profession_nomiss AS agricultural_politician,
               p.relative_year_bin,
               CAST((p.relative_year_bin>=0) AND (p.treat=1) AS INTEGER) AS switching_agri,
               p."count"*1000 AS fires,
               p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(politician_csv)}', {csv_options}) p
        JOIN rural_lookup_clean r
          ON CAST(p.unique_small_grid_id AS VARCHAR)=r.grid_key AND r.is_rural=1
        WHERE p.relative_year_bin BETWEEN -5 AND 4
          AND (p.year < 2022 OR (p.year=2022 AND p.month<=8))
          AND p."count" IS NOT NULL AND p.treat IS NOT NULL
          AND p.downup_ac_pop IS NOT NULL AND p.wind_direction IS NOT NULL
          AND p.av_wind_speed IS NOT NULL AND p.rice_prod_aclvl_ahigh IS NOT NULL
          AND p.cohort_id IS NOT NULL AND p.election_year IS NOT NULL
          AND p.monthyear IS NOT NULL AND p.ac_uq_id IS NOT NULL
    """)

    main_rows = [
        ("Grid", "unique_small_grid_id", False), ("Year", "year", False),
        ("Month", "month", False), ("Assembly Constituency (AC)", "ac_uq_id", False),
        ("Province", "province", False), ("Number of Fires", "fires", True),
        (r"Down $>$ Up", "downup_ac_pop", True),
        ("Average Wind Speed", "av_wind_speed", True),
        ("Wind Direction", "wind_direction", True),
        ("Rice Production", "rice_prod_aclvl_ahigh", True),
    ]
    protest_rows = [
        ("Grid ID", "unique_small_grid_id", False), ("Year", "year", False),
        ("Month", "month", False), ("Assembly Constituency (AC)", "ac_uq_id", False),
        ("Province", "province", False), ("Protest Area", "ac_area_tr", False),
        ("Cohort", "cohort", False), ("Legislature", "legislature", False),
        ("Relative year", "relative_year_bin", True), ("Protest", "protest", True),
        ("Number of Fires", "fires", True),
        ("High Rice production (AC level)", "rice_prod_aclvl_ahigh", True),
    ]
    politician_rows = [
        ("Grid ID", "unique_small_grid_id", False), ("Year", "year", False),
        ("Month", "month", False), ("Assembly Constituency (AC)", "ac_uq_id", False),
        ("Province", "province", False), ("Election Year", "election_year", False),
        ("Cohort", "cohort", False), ("Legislature", "legislature", False),
        ("Agricultural Politician", "agricultural_politician", False),
        ("Relative year", "relative_year_bin", True),
        ("Switching to Agri Pol", "switching_agri", True),
        ("Number of Fires", "fires", True),
        ("High Rice production (AC level)", "rice_prod_aclvl_ahigh", True),
    ]

    write_latex(tables / f"descriptives_main{sample}.tex",
                summarize(con, "desc_main", main_rows))
    write_latex(tables / f"_protest_stacked_descriptive{sample}.tex",
                summarize(con, "desc_protest", protest_rows))
    write_latex(tables / f"_politicians_stacked_descriptive{sample}.tex",
                summarize(con, "desc_politician", politician_rows))
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
