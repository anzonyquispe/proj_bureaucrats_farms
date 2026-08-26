#!/usr/bin/env python3
"""Generate production descriptives directly from Stata e(sample) exports."""

from __future__ import annotations

import argparse
import logging
import math
from pathlib import Path

import duckdb


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


def csv_columns(con: duckdb.DuckDBPyConnection, path: Path,
                options: str) -> set[str]:
    rows = con.execute(
        f"DESCRIBE SELECT * FROM read_csv_auto('{sql_path(path)}', {options})"
    ).fetchall()
    return {str(row[0]) for row in rows}


def relative_year_column(columns: set[str], path: Path) -> str:
    for candidate in ("relative_year_bin", "relative_year"):
        if candidate in columns:
            return candidate
    raise ValueError(
        f"{path} has neither relative_year_bin nor relative_year"
    )


def first_existing_column(columns: set[str], candidates: tuple[str, ...],
                          path: Path, label: str) -> str:
    """Return the first supported source-column name with a clear failure."""
    for candidate in candidates:
        if candidate in columns:
            return candidate
    raise ValueError(
        f"{path} has no supported {label} column; expected one of "
        f"{', '.join(candidates)}"
    )


def drop_relation(con: duckdb.DuckDBPyConnection, name: str) -> None:
    """Drop a retained DuckDB table or view so reruns are idempotent."""
    row = con.execute(
        """
        SELECT table_type
        FROM information_schema.tables
        WHERE table_schema = current_schema() AND table_name = ?
        """,
        [name],
    ).fetchone()
    if row is None:
        return
    object_type = "VIEW" if str(row[0]).upper() == "VIEW" else "TABLE"
    con.execute(f'DROP {object_type} "{name}"')
    LOG.info("Dropped existing %s %s before rebuilding", object_type, name)


def fmt_number(value: object, integer: bool = False) -> str:
    if value is None:
        return ""
    try:
        if math.isnan(float(value)):
            return ""
    except (TypeError, ValueError):
        pass
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
            fmt_number(
                stats[f"n_{index}"] if continuous else stats["total_n"],
                integer=True,
            ),
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

    main_csv = intermediate / f"main_downup_ac_pop_esample{sample}.csv"
    politician_csv = intermediate / f"politician_downup_ac_pop_esample{sample}.csv"
    protest_csv = intermediate / f"protest_downup_ac_pop_esample{sample}.csv"
    for path in (main_csv, politician_csv, protest_csv):
        if not path.exists():
            raise FileNotFoundError(path)

    csv_options = "header=true, auto_detect=true, sample_size=1000000, null_padding=true"
    main_columns = csv_columns(con, main_csv, csv_options)
    protest_columns = csv_columns(con, protest_csv, csv_options)
    politician_columns = csv_columns(con, politician_csv, csv_options)
    main_province = first_existing_column(
        main_columns, ("province", "prov"), main_csv, "province"
    )
    protest_relative = relative_year_column(protest_columns, protest_csv)
    politician_relative = relative_year_column(
        politician_columns, politician_csv
    )
    LOG.info("Main province column: %s", main_province)
    LOG.info("Protest relative-year column: %s", protest_relative)
    LOG.info("Politician relative-year column: %s", politician_relative)
    LOG.info("Building main descriptives from exact specification-4 e(sample)")
    drop_relation(con, "desc_main")
    con.execute(f"""
        CREATE OR REPLACE VIEW desc_main AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id,
               p."{main_province}" AS province,
               p."count" AS fires, p.downup_ac_pop, p.av_wind_speed,
               p.wind_direction, p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(main_csv)}', {csv_options}) p
    """)

    LOG.info("Building protest descriptives from exact richest-DiD e(sample)")
    drop_relation(con, "desc_protest")
    con.execute(f"""
        CREATE OR REPLACE VIEW desc_protest AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id, p.province,
               p.ac_area_tr, p.cohort,
               concat(CAST(p.province AS VARCHAR),'|',CAST(p.election_year AS VARCHAR)) AS legislature,
               p."{protest_relative}" AS relative_year_bin,
               CAST((p."{protest_relative}">=0) AND (p.treat=1) AS INTEGER) AS protest,
               p.countk AS fires,
               p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(protest_csv)}', {csv_options}) p
    """)

    LOG.info("Building politician descriptives from exact richest-DiD e(sample)")
    drop_relation(con, "desc_politician")
    con.execute(f"""
        CREATE OR REPLACE VIEW desc_politician AS
        SELECT p.unique_small_grid_id, p.year, p.month, p.ac_uq_id, p.province,
               p.election_year, p.cohort,
               concat(CAST(p.province AS VARCHAR),'|',CAST(p.election_year AS VARCHAR)) AS legislature,
               CASE WHEN p.self_profession_nomiss=1 THEN
                    concat(CAST(p.ac_uq_id AS VARCHAR),'|',
                           CAST(p.election_year AS VARCHAR))
               END AS agricultural_politician,
               p."{politician_relative}" AS relative_year_bin,
               CAST((p."{politician_relative}">=0) AND (p.treat=1) AS INTEGER) AS switching_agri,
               p.countk AS fires,
               p.rice_prod_aclvl_ahigh
        FROM read_csv_auto('{sql_path(politician_csv)}', {csv_options}) p
    """)

    for table, source in (
        ("desc_main", main_csv),
        ("desc_politician", politician_csv),
        ("desc_protest", protest_csv),
    ):
        source_n = con.execute(
            f"SELECT count(*) FROM read_csv_auto('{sql_path(source)}', {csv_options})"
        ).fetchone()[0]
        table_n = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        if source_n != table_n:
            raise RuntimeError(
                f"{table} changed the exported e(sample): source={source_n:,}, "
                f"descriptive={table_n:,}"
            )
        LOG.info(
            "Validated %s: %s rows exactly match %s",
            table,
            f"{table_n:,}",
            source,
        )

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
