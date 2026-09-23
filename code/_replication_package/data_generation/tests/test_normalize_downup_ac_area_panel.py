from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import duckdb


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import normalize_downup_ac_area_panel as normalizer  # noqa: E402


class NormalizeAreaPanelTests(unittest.TestCase):
    def test_legacy_population_copies_are_removed_without_changing_areas(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            directory_path = Path(directory)
            population = directory_path / "population.parquet"
            area = directory_path / "area.parquet"
            connection = duckdb.connect()
            try:
                connection.execute(
                    """
                    COPY (
                        SELECT * FROM (VALUES
                            (1::BIGINT, 10::BIGINT, 2022::SMALLINT, 8::TINYINT,
                             45.0::DOUBLE, 100.0::DOUBLE, 40.0::DOUBLE)
                        ) AS t(unique_small_grid_id, ac_uq_id, year, month,
                               rollav_wind_direction_cellid_month,
                               downwind_pop, upwind_pop)
                    ) TO ? (FORMAT PARQUET)
                    """,
                    [str(population)],
                )
                connection.execute(
                    """
                    COPY (
                        SELECT * FROM (VALUES
                            (1::BIGINT, 2022::SMALLINT, 8::TINYINT,
                             45.0::DOUBLE, 999.0::DOUBLE, 1::TINYINT,
                             6.0::DOUBLE, 2.0::DOUBLE)
                        ) AS t(unique_small_grid_id, year, month,
                               rollav_wind_direction_cellid_month,
                               downwind_pop, downup_ac_area,
                               downwind_area, upwind_area)
                    ) TO ? (FORMAT PARQUET)
                    """,
                    [str(area)],
                )
            finally:
                connection.close()

            arguments = [
                "normalize_downup_ac_area_panel.py",
                "--population",
                str(population),
                "--area",
                str(area),
                "--threads",
                "1",
                "--memory-limit",
                "1GB",
                "--overwrite",
            ]
            with patch.object(sys, "argv", arguments):
                self.assertEqual(normalizer.main(), 0)

            connection = duckdb.connect()
            try:
                result_columns = tuple(
                    row[0]
                    for row in connection.execute(
                        "DESCRIBE SELECT * FROM read_parquet(?)", [str(area)]
                    ).fetchall()
                )
                row = connection.execute(
                    "SELECT * FROM read_parquet(?)", [str(area)]
                ).fetchone()
            finally:
                connection.close()

            self.assertEqual(result_columns, normalizer.CANONICAL_COLUMNS)
            self.assertEqual(row, (1, 10, 2022, 8, 1, 6.0, 2.0))
            self.assertNotIn("downwind_pop", result_columns)


if __name__ == "__main__":
    unittest.main()
