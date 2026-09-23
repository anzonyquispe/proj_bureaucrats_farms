from __future__ import annotations

import sys
import unittest
from pathlib import Path

import duckdb
import pandas as pd
from shapely.geometry import box


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_downup_ac_area_cluster as area_builder  # noqa: E402
import build_downup_ac_pop_cluster as population_builder  # noqa: E402


class DownupDirectionConventionTests(unittest.TestCase):
    def test_area_worker_returns_only_keys_and_area_outputs(self) -> None:
        polygon = box(-1.0, -1.0, 3.0, 1.0)
        area_builder.initialize_worker({10: polygon.wkb})
        frame = pd.DataFrame(
            {
                "unique_small_grid_id": [1],
                "ac_uq_id": [10],
                "year": [2022],
                "month": [8],
                "calculation_wind_direction": [0.0],
                "centroid_x": [0.0],
                "centroid_y": [0.0],
            }
        )

        result = area_builder.calculate_area_chunk(frame)

        self.assertEqual(
            list(result.columns),
            [
                "unique_small_grid_id",
                "ac_uq_id",
                "year",
                "month",
                "downwind_area",
                "upwind_area",
                "downup_ac_area",
            ],
        )
        self.assertNotIn("downwind_pop", result.columns)
        self.assertNotIn("rollav_wind_direction_cellid_month", result.columns)

    def test_area_halfplanes_use_counterclockwise_degrees_from_east(self) -> None:
        # The focal point is at the origin. The AC has 6 square units East of
        # the dividing line and 2 square units West of it.
        polygon = box(-1.0, -1.0, 3.0, 1.0)
        total_area = float(polygon.area)
        expected = {
            0.0: (6.0, 2.0),   # East
            90.0: (4.0, 4.0),  # North
            180.0: (2.0, 6.0), # West
            270.0: (4.0, 4.0), # South
        }
        for direction, (expected_down, expected_up) in expected.items():
            down, up = area_builder.scalar_halfplane_area(
                polygon,
                tuple(map(float, polygon.bounds)),
                total_area,
                0.0,
                0.0,
                direction,
            )
            # scalar_halfplane_area returns km2, while this synthetic geometry
            # uses square metres.
            self.assertAlmostEqual(down * 1_000_000.0, expected_down, places=8)
            self.assertAlmostEqual(up * 1_000_000.0, expected_up, places=8)

    def test_population_lookup_matches_east_north_west_south(self) -> None:
        connection = duckdb.connect()
        try:
            connection.execute(
                """
                CREATE TABLE panel (
                    unique_small_grid_id BIGINT,
                    ac_uq_id BIGINT
                );
                INSERT INTO panel VALUES
                    (1, 10), (2, 10), (3, 10), (4, 10), (5, 10);

                CREATE TABLE grid_population (
                    unique_small_grid_id BIGINT,
                    population_2010 DOUBLE,
                    centroid_x DOUBLE,
                    centroid_y DOUBLE
                );
                INSERT INTO grid_population VALUES
                    (1, 0.0,  0.0,  0.0),
                    (2, 1.0,  1.0,  0.0),
                    (3, 2.0,  0.0,  1.0),
                    (4, 4.0, -1.0,  0.0),
                    (5, 8.0,  0.0, -1.0);
                """
            )
            population_builder.build_lookup(connection)
            result = connection.execute(
                """
                SELECT query.direction, event.downwind_pop
                FROM (
                    SELECT * FROM (VALUES
                        (10::BIGINT, 1::BIGINT, 0.0::DOUBLE),
                        (10::BIGINT, 1::BIGINT, 90.0::DOUBLE),
                        (10::BIGINT, 1::BIGINT, 180.0::DOUBLE),
                        (10::BIGINT, 1::BIGINT, 270.0::DOUBLE)
                    ) AS values_table(ac_uq_id, focal_grid_id, direction)
                ) AS query
                ASOF LEFT JOIN angle_events AS event
                  ON query.ac_uq_id = event.ac_uq_id
                 AND query.focal_grid_id = event.focal_grid_id
                 AND query.direction >= event.event_angle
                ORDER BY query.direction
                """
            ).fetchall()
        finally:
            connection.close()

        # Populations deliberately encode the cardinal direction: E=1, N=2,
        # W=4, S=8. Points on the perpendicular boundary are excluded.
        self.assertEqual(
            [(int(direction), float(population)) for direction, population in result],
            [(0, 1.0), (90, 2.0), (180, 4.0), (270, 8.0)],
        )


if __name__ == "__main__":
    unittest.main()
