from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import duckdb


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import build_stacked_protest_province_election_switch as builder


class ProvinceElectionSwitchStackTest(unittest.TestCase):
    def test_cohorts_and_control_censoring(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "master.parquet"
            con = duckdb.connect()
            try:
                con.execute(
                    """
                    CREATE TABLE source AS
                    WITH units(grid, province, switch_month) AS (
                        VALUES
                            (1, 'A', 4), (2, 'A', 4),
                            (3, 'A', NULL), (4, 'A', 6), (7, 'A', NULL),
                            (5, 'B', 4), (6, 'B', NULL)
                    ), months AS (SELECT range AS month FROM range(1, 9))
                    SELECT
                        grid::BIGINT AS unique_small_grid_id,
                        grid::BIGINT AS ac_uq_id,
                        province,
                        1::SMALLINT AS distr_id,
                        'D'::VARCHAR AS district,
                        month::TINYINT AS month,
                        2020::SMALLINT AS year,
                        (2020 * 12 + month)::INTEGER AS monthyear,
                        1::BIGINT AS count,
                        300.0::DOUBLE AS mean_brightness,
                        2.0::DOUBLE AS av_wind_speed,
                        45.0::DOUBLE AS wind_direction,
                        0::TINYINT AS downup_ac,
                        0::TINYINT AS downup_ac_pop,
                        0::TINYINT AS rice_area_aclvl_ahigh,
                        0::TINYINT AS rice_harvarea_aclvl_ahigh,
                        0::TINYINT AS rice_prod_aclvl_ahigh,
                        CASE
                            WHEN switch_month IS NOT NULL AND month >= switch_month
                            THEN 1 ELSE 0
                        END::TINYINT AS protest5km,
                        NULL::BIGINT AS protest_id,
                        0::BIGINT AS protest_place,
                        2019.0::DOUBLE AS election_year,
                        month::DOUBLE AS yeargov,
                        2020.0::DOUBLE AS year_take,
                        1.0::DOUBLE AS month_take,
                        2020.0::DOUBLE AS year_end,
                        9.0::DOUBLE AS month_end,
                        (2020 * 12 + 1)::DOUBLE AS ym_take
                    FROM units CROSS JOIN months
                    WHERE NOT (grid = 7 AND month = 3)
                    """
                )
                con.execute(
                    f"COPY source TO '{source.as_posix()}' (FORMAT PARQUET)"
                )
            finally:
                con.close()

            status = builder.main(
                [
                    "--intermediate",
                    str(root),
                    "--input",
                    str(source),
                    "--threads",
                    "2",
                    "--memory-limit",
                    "1GB",
                    "--overwrite",
                ]
            )
            self.assertEqual(status, 0)

            db = duckdb.connect(str(root / f"{builder.OUTPUT_STEM}.db"))
            try:
                cohorts = db.execute(
                    """
                    SELECT cohort_province, cohort, count(DISTINCT cohort_id)
                    FROM final_stack GROUP BY 1, 2 ORDER BY 1, 2
                    """
                ).fetchall()
                self.assertEqual(
                    cohorts,
                    [("A", 2020 * 12 + 4, 1), ("A", 2020 * 12 + 6, 1),
                     ("B", 2020 * 12 + 4, 1)],
                )

                cohort_a4 = db.execute(
                    """
                    SELECT unique_small_grid_id, treat, control_type,
                           min(month), max(month)
                    FROM final_stack
                    WHERE cohort_province = 'A' AND cohort = 2020 * 12 + 4
                    GROUP BY 1, 2, 3 ORDER BY 1
                    """
                ).fetchall()
                self.assertEqual(
                    cohort_a4,
                    [(1, 1, 0, 1, 8), (2, 1, 0, 1, 8),
                     (3, 0, 1, 1, 8), (4, 0, 2, 1, 5)],
                )
                self.assertEqual(
                    db.execute(
                        "SELECT count(*) FROM final_stack "
                        "WHERE unique_small_grid_id = 7"
                    ).fetchone()[0],
                    0,
                )
            finally:
                db.close()


if __name__ == "__main__":
    unittest.main()
