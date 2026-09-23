#!/usr/bin/env python3
"""Province x switching-month exploratory stacks, with gap-aware full spells.

Each treated membership includes the entire zero spell immediately preceding
an observed consecutive 0->1 switch and the entire following one spell.
Each control membership includes the entire zero spell containing the cohort
month (including that month). Missing dates/values terminate spells. Prior
treated spells do not disqualify a control from a later untreated spell.
Window exports are pure row restrictions, not balanced-panel selections.
"""
import argparse
import logging
import os
from pathlib import Path

import duckdb


PREFIX = "combined_dt_pop_byprov"
WINDOWS = ((-6, 6), (-5, 5), (-5, 6))


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def build(con, source, end_year=2022, end_month=8):
    """Build compact spell/membership tables and lazy stacked views."""
    cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM {source}").fetchall()]
    required = {"unique_small_grid_id", "province", "year", "month", "downup_ac_pop"}
    if required - set(cols):
        raise ValueError(f"Missing source columns: {sorted(required - set(cols))}")
    reserved = {"cohort", "cohort_id", "treat", "post", "relative_monthyear",
                "relative_year", "spell_start", "spell_end", "_province", "_time"}
    if reserved & set(cols):
        raise ValueError(f"Expected unstacked master; reserved columns: {reserved & set(cols)}")
    # Validate state histories over the entire source, including later dates.
    bad = con.execute(f"""
        SELECT count(*) FROM (
          SELECT unique_small_grid_id FROM {source}
          GROUP BY 1 HAVING unique_small_grid_id IS NULL
             OR count(DISTINCT lower(trim(province))) <> 1
             OR count(*) FILTER (WHERE province IS NULL OR trim(province)='') > 0
        )""").fetchone()[0]
    if bad:
        raise ValueError(f"{bad} grids have missing or changing province")
    bad = con.execute(f"""SELECT count(*) FROM {source}
        WHERE year IS NULL OR month IS NULL OR month NOT BETWEEN 1 AND 12
          OR year <> floor(year) OR month <> floor(month)
          OR (downup_ac_pop IS NOT NULL AND downup_ac_pop NOT IN (0,1))""").fetchone()[0]
    if bad:
        raise ValueError(f"{bad} invalid dates/treatment values")
    if "monthyear" in cols:
        bad = con.execute(f"SELECT count(*) FROM {source} WHERE monthyear IS DISTINCT FROM year*12+month").fetchone()[0]
        if bad:
            raise ValueError("Master monthyear must equal year*12+month")
    add_time = "" if "monthyear" in cols else ", CAST(year*12+month AS BIGINT) AS monthyear"
    con.execute(f"""CREATE TABLE panel AS SELECT * {add_time},
        lower(trim(province)) AS _province, CAST(year*12+month AS BIGINT) AS _time
        FROM {source} WHERE year*12+month <= {end_year*12+end_month}""")
    duplicate = con.execute("""SELECT count(*) FROM (
        SELECT unique_small_grid_id,_time FROM panel GROUP BY 1,2 HAVING count(*)>1)
        """).fetchone()[0]
    if duplicate:
        raise ValueError(f"{duplicate} duplicate grid-month keys")
    # Remove missing treatment only before lagging: elapsed month then reveals gaps.
    con.execute("""CREATE TABLE spells AS
        WITH lagged AS (
          SELECT unique_small_grid_id,_province,_time,downup_ac_pop,
            lag(_time) OVER w AS prev_time, lag(downup_ac_pop) OVER w AS prev_d
          FROM panel WHERE downup_ac_pop IS NOT NULL
          WINDOW w AS (PARTITION BY unique_small_grid_id ORDER BY _time)
        ), numbered AS (
          SELECT *, sum(CASE WHEN prev_time=_time-1 AND prev_d=downup_ac_pop
                             THEN 0 ELSE 1 END) OVER
            (PARTITION BY unique_small_grid_id ORDER BY _time) AS spell
          FROM lagged
        ) SELECT unique_small_grid_id,_province,spell,downup_ac_pop,
            min(_time) AS spell_start,max(_time) AS spell_end,count(*) AS n_months
          FROM numbered GROUP BY 1,2,3,4""")
    con.execute("""CREATE TABLE events AS
        SELECT a.unique_small_grid_id,a._province,a.spell_start AS cohort,
               b.spell_start,a.spell_end
        FROM spells a JOIN spells b
          ON a.unique_small_grid_id=b.unique_small_grid_id AND a.spell=b.spell+1
        WHERE a.downup_ac_pop=1 AND b.downup_ac_pop=0
          AND a.spell_start=b.spell_end+1""")
    con.execute("""CREATE TABLE cohorts AS
        SELECT row_number() OVER (ORDER BY _province,cohort) AS cohort_id,
               _province,cohort FROM (SELECT DISTINCT _province,cohort FROM events)""")
    # Compact interval memberships: no enormous materialized expanded stack.
    con.execute("""CREATE TABLE memberships AS
        SELECT c.cohort_id,e.cohort,e._province,e.unique_small_grid_id,
               1::TINYINT AS treat,e.spell_start,e.spell_end
        FROM events e JOIN cohorts c USING (_province,cohort)
        UNION ALL
        SELECT c.cohort_id,c.cohort,c._province,z.unique_small_grid_id,
               0::TINYINT AS treat,z.spell_start,z.spell_end
        FROM cohorts c JOIN spells z ON c._province=z._province
          AND c.cohort BETWEEN z.spell_start AND z.spell_end
        WHERE z.downup_ac_pop=0""")
    con.execute("""CREATE VIEW final_stack AS
        SELECT p.* EXCLUDE (_province,_time),m.cohort_id,m.cohort,m.treat,
            (p._time>=m.cohort)::TINYINT AS post,
            p._time-m.cohort AS relative_monthyear,
            m.spell_start,m.spell_end
        FROM memberships m JOIN panel p
          ON m.unique_small_grid_id=p.unique_small_grid_id
          AND p._time BETWEEN m.spell_start AND m.spell_end""")
    bad = con.execute("""SELECT count(*) FROM (
        SELECT cohort_id,unique_small_grid_id FROM memberships
        GROUP BY 1,2 HAVING count(*)<>1)""").fetchone()[0]
    assert bad == 0, "Duplicate unit-cohort memberships"
    assert con.execute("SELECT count(*) FROM spells WHERE n_months<>spell_end-spell_start+1").fetchone()[0] == 0
    con.execute("""CREATE TABLE cohort_summary AS SELECT c.cohort_id,
        c._province AS province,c.cohort,
        (c.cohort-1)//12 AS switch_year, (c.cohort-1)%12+1 AS switch_month,
        count(*) FILTER (WHERE m.treat=1) AS treated_grids,
        count(*) FILTER (WHERE m.treat=0) AS control_grids,
        sum(m.spell_end-m.spell_start+1) AS full_rows,
        min(m.spell_start-m.cohort) AS relative_min,
        max(m.spell_end-m.cohort) AS relative_max
        FROM cohorts c JOIN memberships m USING (cohort_id)
        GROUP BY c.cohort_id,c._province,c.cohort""")
    for lo, hi in WINDOWS:
        name = f"window_m{-lo}_p{hi}"
        con.execute(f"CREATE VIEW {name} AS SELECT * FROM final_stack WHERE relative_monthyear BETWEEN {lo} AND {hi}")
        con.execute(f"""CREATE TABLE {name}_summary AS SELECT cohort_id,
            count(*) FILTER (WHERE treat=1) AS treated_grids,
            count(*) FILTER (WHERE treat=0) AS control_grids,
            sum(least(spell_end,cohort+{hi})-greatest(spell_start,cohort+{lo})+1) AS rows,
            count(*) FILTER (WHERE spell_start>=cohort) AS units_without_pre,
            count(*) FILTER (WHERE spell_end<=cohort) AS units_without_strict_post
            FROM memberships GROUP BY cohort_id""")
    counts = con.execute("SELECT count(*),sum(full_rows),sum(control_grids=0) FROM cohort_summary").fetchone()
    logging.info("Cohorts=%s; full rows=%s; cohorts without controls=%s", *counts)
    logging.info("Memberships are intentional spell expansion, not a master attachment merge")


def main():
    default = (Path(r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms\data_output\intermediate")
               if os.name == "nt" else Path("/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"))
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, default=default / "0_master_dataset.parquet")
    ap.add_argument("--output-dir", type=Path, default=default)
    ap.add_argument("--threads", type=int, default=10)
    ap.add_argument("--memory-limit", default="90GB")
    ap.add_argument("--end-year", type=int, default=2022)
    ap.add_argument("--end-month", type=int, default=8)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
    if not args.input.is_file():
        raise FileNotFoundError(args.input)
    if not 1 <= args.end_month <= 12:
        ap.error("--end-month must be between 1 and 12")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    db = args.output_dir / f"{PREFIX}.db"
    # Prevent silently replacing previous experiments or partially completed runs.
    targets = [db, args.output_dir/f"{PREFIX}_full.csv", args.output_dir/f"{PREFIX}_cohorts.csv"]
    for lo, hi in WINDOWS:
        targets.extend([args.output_dir/f"{PREFIX}_m{-lo}_p{hi}.csv",
                        args.output_dir/f"{PREFIX}_m{-lo}_p{hi}_cohorts.csv"])
    existing = [str(p) for p in targets if p.exists()]
    if existing:
        raise FileExistsError(f"Choose a fresh --output-dir; outputs already exist: {existing}")
    with duckdb.connect(str(db)) as con:
        con.execute(f"SET threads={args.threads}")
        con.execute(f"SET memory_limit={literal(args.memory_limit)}")
        con.execute(f"SET temp_directory={literal(args.output_dir/(PREFIX+'_tmp'))}")
        con.execute("SET preserve_insertion_order=false")
        build(con, f"read_parquet({literal(args.input.resolve())})", args.end_year, args.end_month)
        exports = [("final_stack", "full"), ("cohort_summary", "cohorts")]
        for lo, hi in WINDOWS:
            suffix = f"m{-lo}_p{hi}"
            exports.extend([(f"window_{suffix}",suffix),(f"window_{suffix}_summary",suffix+"_cohorts")])
        for table, suffix in exports:
            path = args.output_dir/f"{PREFIX}_{suffix}.csv"
            logging.info("Exporting %s", path)
            con.execute(f"COPY {table} TO {literal(path)} (FORMAT CSV, HEADER true)")
        con.execute("CHECKPOINT")
    logging.info("Completed; database with full stack and window views: %s", db)


if __name__ == "__main__":
    main()
