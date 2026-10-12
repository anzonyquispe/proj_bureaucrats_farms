from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import duckdb
import pandas as pd


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_downup_ac_pop_rice as rice_builder  # noqa: E402


# One AC with a focal grid and four cardinal neighbours. Populations encode the
# position: centre=1, East=2, North=4, West=8, South=16 (total 31).
CARDINAL_GRIDS = (
    (1, 0.0, 0.0, 1.0),
    (2, 1.0, 0.0, 2.0),
    (3, 0.0, 1.0, 4.0),
    (4, -1.0, 0.0, 8.0),
    (5, 0.0, -1.0, 16.0),
)


def measure(
    grids: list[tuple[int, int, float, float, float, float, float]],
    rice_percentile: float = 0.5,
    sample_percentile: float = 0.5,
) -> dict[int, dict[str, object]]:
    """Run the AC-month stage on (grid, AC, x, y, population, rice, wind) rows."""

    connection = duckdb.connect()
    try:
        connection.execute(
            """
            CREATE TABLE panel_wind (
                unique_small_grid_id BIGINT,
                ac_uq_id BIGINT,
                year SMALLINT,
                month TINYINT,
                wind_direction_av_cellid_month DOUBLE
            );
            CREATE TABLE grid_population (
                unique_small_grid_id BIGINT,
                population_2010 DOUBLE,
                centroid_x DOUBLE,
                centroid_y DOUBLE
            );
            CREATE TABLE grid_rice (
                unique_small_grid_id BIGINT,
                rice_prod DOUBLE
            );
            """
        )
        for grid, ac, x, y, population, rice, wind in grids:
            connection.execute(
                "INSERT INTO panel_wind VALUES (?, ?, 2022, 10, ?)",
                [grid, ac, wind],
            )
            connection.execute(
                "INSERT INTO grid_population VALUES (?, ?, ?, ?)",
                [grid, population, x, y],
            )
            connection.execute(
                "INSERT INTO grid_rice VALUES (?, ?)", [grid, rice]
            )
        rice_builder.build_grid_ac(connection, rice_percentile, sample_percentile)
        rice_builder.build_ac_month_measures(connection)
        columns = ", ".join(rice_builder.OUTPUT_COLUMNS)
        cursor = connection.execute(
            f"SELECT {columns} FROM ac_month_pop_rice ORDER BY ac_uq_id"
        )
        names = [description[0] for description in cursor.description]
        return {
            int(row[0]): dict(zip(names, row)) for row in cursor.fetchall()
        }
    finally:
        connection.close()


def cardinal_ac(
    rice_by_grid: dict[int, float], wind: float, ac: int = 10, offset: int = 0
) -> list[tuple[int, int, float, float, float, float, float]]:
    return [
        (
            grid + offset,
            ac,
            x,
            y,
            population,
            rice_by_grid.get(grid, 0.0),
            wind,
        )
        for grid, x, y, population in CARDINAL_GRIDS
    ]


class DownupPopRiceTests(unittest.TestCase):
    def test_upwind_rice_zone_makes_whole_ac_downwind(self) -> None:
        # Wind blows East from the western rice zone: every grid lies beyond it.
        result = measure(cardinal_ac({4: 100.0}, wind=0.0))[10]
        self.assertEqual(result["n_rice_grids_ac"], 1)
        self.assertAlmostEqual(result["downwind_pop_rice_ac"], 31.0)
        self.assertAlmostEqual(result["upwind_pop_rice_ac"], 0.0)
        self.assertAlmostEqual(result["down_percent_pop_rice_ac"], 100.0)
        self.assertEqual(result["downup_ac_pop_rice"], 1)

    def test_downwind_rice_zone_only_counts_itself(self) -> None:
        # Wind blows East from the eastern rice zone: nothing lies beyond it.
        result = measure(cardinal_ac({2: 100.0}, wind=0.0))[10]
        self.assertAlmostEqual(result["downwind_pop_rice_ac"], 2.0)
        self.assertAlmostEqual(result["upwind_pop_rice_ac"], 29.0)
        self.assertEqual(result["downup_ac_pop_rice"], 0)

    def test_directions_are_counterclockwise_from_east(self) -> None:
        # North wind from the southern zone covers the rest of the AC; the
        # grids on the zone's own row (y = -1) are the zone itself only.
        south = measure(cardinal_ac({5: 100.0}, wind=90.0))[10]
        self.assertAlmostEqual(south["downwind_pop_rice_ac"], 31.0)
        # A wind blowing South (-90 degrees) from the northern zone.
        north = measure(cardinal_ac({3: 100.0}, wind=-90.0))[10]
        self.assertAlmostEqual(north["downwind_pop_rice_ac"], 31.0)
        # A wind blowing West from the western zone covers only that zone.
        west = measure(cardinal_ac({4: 100.0}, wind=180.0))[10]
        self.assertAlmostEqual(west["downwind_pop_rice_ac"], 8.0)

    def test_grids_on_the_dividing_line_are_not_downwind(self) -> None:
        # East wind from the northern zone: the centre and southern grids share
        # its x coordinate, so only the zone and the eastern grid count.
        result = measure(cardinal_ac({3: 100.0}, wind=0.0))[10]
        self.assertAlmostEqual(result["downwind_pop_rice_ac"], 4.0 + 2.0)

    def test_rice_below_the_within_ac_percentile_is_not_a_source(self) -> None:
        # Production 10..50: the p50 cutoff is 30, so the western grid (10) and
        # the centre (20) are not rice zones even though they produce rice.
        rice = {1: 20.0, 2: 50.0, 3: 40.0, 4: 10.0, 5: 30.0}
        result = measure(cardinal_ac(rice, wind=0.0))[10]
        self.assertEqual(result["n_rice_grids_ac"], 3)
        self.assertAlmostEqual(result["rice_cutoff_ac"], 30.0)
        # Zones: North (4), East (2), South (16); the most-upwind zone is at
        # x = 0, so the centre on that line stays upwind.
        self.assertAlmostEqual(result["downwind_pop_rice_ac"], 22.0)
        self.assertEqual(result["downup_ac_pop_rice"], 1)

        with_west = measure(cardinal_ac(rice, wind=0.0), rice_percentile=0.0)[10]
        self.assertEqual(with_west["n_rice_grids_ac"], 5)
        self.assertAlmostEqual(with_west["downwind_pop_rice_ac"], 31.0)

    def test_ac_without_rice_is_zero(self) -> None:
        result = measure(cardinal_ac({}, wind=0.0))[10]
        for suffix in ("", "_sample"):
            self.assertEqual(result[f"n_rice_grids_ac{suffix}"], 0)
            self.assertAlmostEqual(result[f"downwind_pop_rice_ac{suffix}"], 0.0)
            self.assertAlmostEqual(result[f"upwind_pop_rice_ac{suffix}"], 31.0)
            self.assertAlmostEqual(
                result[f"down_percent_pop_rice_ac{suffix}"], 0.0
            )
            self.assertEqual(result[f"downup_ac_pop_rice{suffix}"], 0)

    def test_sample_cutoff_uses_all_grids_not_the_ac(self) -> None:
        # AC 10 produces little rice (only its western grid, 1 t); AC 20
        # produces 100 t in every grid. Across the ten grids the p50 cutoff is
        # 50.5 t, so AC 10 has a within-AC rice zone but no sample rice zone.
        grids = cardinal_ac({4: 1.0}, wind=0.0, ac=10) + cardinal_ac(
            {grid: 100.0 for grid in range(1, 6)}, wind=0.0, ac=20, offset=10
        )
        result = measure(grids)
        low, high = result[10], result[20]

        self.assertAlmostEqual(low["rice_cutoff_sample"], 50.5)
        self.assertAlmostEqual(high["rice_cutoff_sample"], 50.5)
        self.assertEqual(low["n_rice_grids_ac"], 1)
        self.assertEqual(low["downup_ac_pop_rice"], 1)
        self.assertEqual(low["n_rice_grids_ac_sample"], 0)
        self.assertAlmostEqual(low["downwind_pop_rice_ac_sample"], 0.0)
        self.assertEqual(low["downup_ac_pop_rice_sample"], 0)

        self.assertEqual(high["n_rice_grids_ac_sample"], 5)
        self.assertAlmostEqual(high["downwind_pop_rice_ac_sample"], 31.0)
        self.assertEqual(high["downup_ac_pop_rice_sample"], 1)

    def test_sample_rice_zone_below_the_ac_median_is_a_source(self) -> None:
        # AC 10 is a rich AC whose western grid (60 t) sits below its own
        # median but above the sample cutoff, so only the sample rule uses it.
        rich = {1: 200.0, 2: 300.0, 3: 250.0, 4: 60.0, 5: 220.0}
        poor = {grid: 0.0 for grid in range(1, 6)}
        grids = cardinal_ac(rich, wind=0.0, ac=10) + cardinal_ac(
            poor, wind=0.0, ac=20, offset=10
        )
        result = measure(grids)[10]
        # Sample p50 across ten grids (five zeros): (0 + 60) / 2 = 30 t.
        self.assertAlmostEqual(result["rice_cutoff_sample"], 30.0)
        self.assertEqual(result["n_rice_grids_ac"], 3)
        self.assertEqual(result["n_rice_grids_ac_sample"], 5)
        # Within-AC zones (N, E, S) leave the centre on the line: 22 of 31.
        self.assertAlmostEqual(result["downwind_pop_rice_ac"], 22.0)
        # The western zone moves the line to x = -1: all 31 are downwind.
        self.assertAlmostEqual(result["downwind_pop_rice_ac_sample"], 31.0)

    def test_exactly_half_downwind_is_not_downup(self) -> None:
        grids = [
            (1, 10, 0.0, 0.0, 5.0, 1.0, 0.0),
            (2, 10, -1.0, 0.0, 5.0, 0.0, 0.0),
        ]
        result = measure(grids)[10]
        self.assertAlmostEqual(result["down_percent_pop_rice_ac"], 50.0)
        self.assertEqual(result["downup_ac_pop_rice"], 0)

    def test_ac_wind_is_the_unit_vector_mean(self) -> None:
        quadrant = measure(
            [
                (1, 10, 0.0, 0.0, 1.0, 1.0, 0.0),
                (2, 10, 5.0, 0.0, 1.0, 0.0, 90.0),
            ]
        )[10]
        self.assertAlmostEqual(quadrant["wind_direction_ac"], 45.0)

        across_zero = measure(
            [
                (1, 10, 0.0, 0.0, 1.0, 1.0, 350.0),
                (2, 10, 5.0, 0.0, 1.0, 0.0, 10.0),
            ]
        )[10]
        direction = float(across_zero["wind_direction_ac"])
        self.assertAlmostEqual(min(direction, 360.0 - direction), 0.0)
        # The AC wind blows East, so the eastern grid is downwind of the zone.
        self.assertAlmostEqual(across_zero["downwind_pop_rice_ac"], 2.0)

    def test_opposing_winds_have_no_direction(self) -> None:
        result = measure(
            [
                (1, 10, 0.0, 0.0, 1.0, 1.0, 0.0),
                (2, 10, 5.0, 0.0, 1.0, 0.0, 180.0),
            ]
        )[10]
        self.assertIsNone(result["wind_direction_ac"])
        self.assertIsNone(result["downwind_pop_rice_ac"])
        self.assertEqual(result["downup_ac_pop_rice"], 0)

    def test_main_excludes_grids_with_missing_wind(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            panel = root / "panel.parquet"
            population = root / "population.parquet"
            rice = root / "rice.parquet"
            output = root / "output.parquet"
            connection = duckdb.connect()
            try:
                # Grid 3 misses its wind in month 11 and must disappear from
                # both months, including from the AC population total.
                connection.execute(
                    f"""
                    COPY (
                        SELECT * FROM (VALUES
                            (1, 10, 2022, 10, 0.0, 0.0),
                            (2, 10, 2022, 10, 0.0, 0.0),
                            (3, 10, 2022, 10, 0.0, 0.0),
                            (1, 10, 2022, 11, 0.0, 0.0),
                            (2, 10, 2022, 11, 0.0, 0.0),
                            (3, 10, 2022, 11, NULL, 0.0),
                            (4, 20, 2022, 10, 0.0, 0.0),
                            (4, 20, 2022, 11, 0.0, 0.0)
                        ) AS t(
                            unique_small_grid_id, ac_uq_id, year, month,
                            wind_direction_av_cellid_month,
                            calculation_wind_direction
                        )
                    ) TO '{panel.as_posix()}' (FORMAT PARQUET)
                    """
                )
                connection.execute(
                    f"""
                    COPY (
                        SELECT * FROM (VALUES
                            (1, 3.0, 0.0, 0.0),
                            (2, 5.0, 1.0, 0.0),
                            (3, 100.0, 2.0, 0.0),
                            (4, 7.0, 0.0, 0.0)
                        ) AS t(
                            unique_small_grid_id, population_2010,
                            centroid_x, centroid_y
                        )
                    ) TO '{population.as_posix()}' (FORMAT PARQUET)
                    """
                )
                connection.execute(
                    f"""
                    COPY (
                        SELECT * FROM (VALUES
                            (1, 10.0), (2, 0.0), (3, 0.0), (4, 0.0)
                        ) AS t(unique_small_grid_id, rice_prod_2010)
                    ) TO '{rice.as_posix()}' (FORMAT PARQUET)
                    """
                )
                rice_builder.main(
                    [
                        "--panel", str(panel),
                        "--grid-population", str(population),
                        "--grid-rice", str(rice),
                        "--output", str(output),
                        "--threads", "1",
                        "--memory-limit", "1GB",
                    ]
                )
                rows = connection.execute(
                    f"""
                    SELECT
                        ac_uq_id, month, total_pop_ac, downwind_pop_rice_ac,
                        downup_ac_pop_rice
                    FROM read_parquet('{output.as_posix()}')
                    ORDER BY ac_uq_id, month
                    """
                ).fetchall()
                columns = [
                    row[0]
                    for row in connection.execute(
                        f"DESCRIBE SELECT * FROM read_parquet('{output.as_posix()}')"
                    ).fetchall()
                ]
            finally:
                connection.close()
            stata = pd.read_stata(output.with_suffix(".dta"))

        self.assertEqual(tuple(columns), rice_builder.OUTPUT_COLUMNS)
        self.assertEqual(tuple(stata.columns), rice_builder.OUTPUT_COLUMNS)
        self.assertEqual(
            stata[["ac_uq_id", "month", "downup_ac_pop_rice"]]
            .astype("int64")
            .values.tolist(),
            [[10, 10, 1], [10, 11, 1], [20, 10, 0], [20, 11, 0]],
        )
        self.assertEqual(
            stata["downup_ac_pop_rice_sample"].astype("int64").tolist(),
            [1, 1, 0, 0],
        )
        self.assertAlmostEqual(float(stata["total_pop_ac"].iloc[0]), 8.0)
        self.assertEqual(
            [tuple(row) for row in rows],
            [
                (10, 10, 8.0, 8.0, 1),
                (10, 11, 8.0, 8.0, 1),
                (20, 10, 7.0, 0.0, 0),
                (20, 11, 7.0, 0.0, 0),
            ],
        )


if __name__ == "__main__":
    unittest.main()
