from __future__ import annotations

import json
import shutil
import sys
import unittest
import uuid
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import duckdb
from netCDF4 import Dataset, date2num


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_fire_grid_duckdb as fire_builder  # noqa: E402
import build_wind_direction_grid_duckdb as wind_builder  # noqa: E402


@contextmanager
def temporary_workspace():
    """Create a test directory without tempfile's restrictive Windows ACL."""
    work = DATA_GENERATION / f".fire_wind_test_{uuid.uuid4().hex}"
    work.mkdir()
    try:
        yield work
    finally:
        shutil.rmtree(work)


def write_grid(path: Path) -> None:
    def polygon(min_x: float, max_x: float) -> list[list[list[float]]]:
        return [[
            [min_x, -0.5],
            [max_x, -0.5],
            [max_x, 0.5],
            [min_x, 0.5],
            [min_x, -0.5],
        ]]

    collection = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {"id": 101, "split_d": 1, "split": 1, "unq_s__": 1},
                "geometry": {"type": "Polygon", "coordinates": polygon(-0.5, 0.5)},
            },
            {
                "type": "Feature",
                "properties": {"id": 102, "split_d": 1, "split": 2, "unq_s__": 2},
                "geometry": {"type": "Polygon", "coordinates": polygon(1.5, 2.5)},
            },
        ],
    }
    path.write_text(json.dumps(collection), encoding="utf-8")


def write_wind_netcdf(
    path: Path,
    indexed_years: list[tuple[int, int]],
) -> None:
    dates: list[datetime] = []
    u_rows: list[list[float]] = []
    for year, year_index in indexed_years:
        for day, addition in ((1, 0.0), (2, 2.0)):
            dates.append(datetime(year, 1, day))
            u_rows.append([year_index + addition, 100.0 + year_index + addition])

    with Dataset(path, mode="w") as dataset:
        dataset.createDimension("time", len(dates))
        dataset.createDimension("latitude", 1)
        dataset.createDimension("longitude", 2)
        time = dataset.createVariable("time", "f8", ("time",))
        latitude = dataset.createVariable("latitude", "f8", ("latitude",))
        longitude = dataset.createVariable("longitude", "f8", ("longitude",))
        u10 = dataset.createVariable(
            "u10", "f8", ("time", "latitude", "longitude")
        )
        v10 = dataset.createVariable(
            "v10", "f8", ("time", "latitude", "longitude")
        )
        time.units = "hours since 1900-01-01 00:00:00"
        time.calendar = "standard"
        time[:] = date2num(dates, units=time.units, calendar=time.calendar)
        latitude[:] = [0.0]
        longitude[:] = [0.0, 2.0]
        u10[:, 0, :] = np.asarray(u_rows)
        v10[:, 0, :] = 0.0


class FireWindDuckDBTests(unittest.TestCase):
    def test_fire_point_in_polygon_aggregation(self) -> None:
        with temporary_workspace() as work:
            grid_path = work / "grids.geojson"
            fires_path = work / "fires.csv"
            output_path = work / "_3_fire_grid.csv"
            write_grid(grid_path)
            pd.DataFrame(
                {
                    "longitude": [0.0, 0.1, 2.0, 20.0],
                    "latitude": [0.0, 0.1, 0.0, 20.0],
                    "acq_date": [
                        "2020-01-03",
                        "2020-01-20",
                        "2020-02-01",
                        "not-a-date",
                    ],
                    "brightness": [300.0, 320.0, 400.0, 999.0],
                }
            ).to_csv(fires_path, index=False)

            fire_builder.main(
                [
                    "--fires",
                    str(fires_path),
                    "--grid-shapefile",
                    str(grid_path),
                    "--output",
                    str(output_path),
                    "--threads",
                    "2",
                    "--memory-limit",
                    "1GB",
                    "--overwrite",
                ]
            )
            result = pd.read_csv(output_path).sort_values(
                ["unique_small_grid_id", "year", "month"]
            )
            self.assertEqual(len(result), 2)
            first = result.iloc[0]
            self.assertEqual(int(first["unique_small_grid_id"]), 1)
            self.assertEqual(int(first["count"]), 2)
            self.assertAlmostEqual(float(first["mean_brightness"]), 310.0)
            second = result.iloc[1]
            self.assertEqual(int(second["unique_small_grid_id"]), 2)
            self.assertEqual(int(second["count"]), 1)
            self.assertAlmostEqual(float(second["mean_brightness"]), 400.0)

    def test_monthly_wind_and_exact_ten_observation_roll(self) -> None:
        with temporary_workspace() as work:
            grid_path = work / "grids.geojson"
            historical_path = work / "historical.nc"
            year_2022_path = work / "year_2022.nc"
            recent_path = work / "recent.csv"
            output_path = work / "_2_wind_direction_grid.parquet"
            write_grid(grid_path)
            write_wind_netcdf(
                historical_path,
                [(year, index) for index, year in enumerate(range(2000, 2008), 1)],
            )
            write_wind_netcdf(year_2022_path, [(2008, 9)])

            recent_rows: list[dict[str, float | int]] = []
            for longitude in (0.0, 2.0):
                offset = 0.0 if longitude == 0.0 else 100.0
                for addition in (0.0, 2.0):
                    recent_rows.append(
                        {
                            "latitude": 0.0,
                            "longitude": longitude,
                            "year": 2009,
                            "month": 1,
                            "u10": offset + 10.0 + addition,
                            "v10": 0.0,
                        }
                    )
            pd.DataFrame(recent_rows).to_csv(recent_path, index=False)

            wind_builder.main(
                [
                    "--historical-netcdf",
                    str(historical_path),
                    "--year-2022-netcdf",
                    str(year_2022_path),
                    "--years-2023-2024-csv",
                    str(recent_path),
                    "--grid-shapefile",
                    str(grid_path),
                    "--output",
                    str(output_path),
                    "--netcdf-chunk-rows",
                    "5",
                    "--threads",
                    "2",
                    "--memory-limit",
                    "1GB",
                    "--overwrite",
                ]
            )
            result = pd.read_parquet(output_path)
            self.assertTrue(output_path.with_suffix(".duckdb").is_file())
            self.assertFalse(output_path.with_suffix(".csv").exists())
            self.assertEqual(len(result), 20)
            self.assertEqual(
                result.groupby("unique_small_grid_id").size().to_dict(),
                {1: 10, 2: 10},
            )
            first_grid = result[result["unique_small_grid_id"] == 1].sort_values("year")
            self.assertTrue(
                first_grid.iloc[:9]["rollav_wind_speed_cellid_month"].isna().all()
            )
            last = first_grid.iloc[-1]
            self.assertAlmostEqual(float(last["wind_speed_av_cellid_month"]), 11.0)
            self.assertAlmostEqual(
                float(last["rollav_wind_speed_cellid_month"]), 6.5
            )
            self.assertAlmostEqual(
                float(last["rollav_wind_direction_cellid_month"]), 0.0
            )

    def test_direction_uses_east_axis_and_vector_rolling_mean(self) -> None:
        connection = duckdb.connect()
        try:
            wind_builder.initialize_monthly_accumulator(connection)
            angles = np.asarray([179.0, -179.0] * 5)
            radians = np.radians(angles)
            wind_builder.append_chunk(
                connection,
                pd.DataFrame(
                    {
                        "latitude": np.zeros(10),
                        "longitude": np.zeros(10),
                        "year": np.arange(2000, 2010),
                        "month": np.ones(10),
                        "u10": np.cos(radians),
                        "v10": np.sin(radians),
                        "wind_speed": np.ones(10),
                    }
                ),
            )
            wind_builder.build_monthly_wind(connection)
            rows = connection.execute(
                """
                SELECT
                    year,
                    wind_direction_av_cellid_month,
                    rollav_wind_direction_cellid_month
                FROM wind_monthly_rolling
                ORDER BY year
                """
            ).fetchall()
        finally:
            connection.close()

        self.assertAlmostEqual(float(rows[0][1]), 179.0, places=8)
        self.assertAlmostEqual(float(rows[1][1]), -179.0, places=8)
        self.assertTrue(all(row[2] is None for row in rows[:9]))
        # The circular/vector mean is 180 degrees (West), not 0 degrees (East).
        self.assertAlmostEqual(abs(float(rows[-1][2])), 180.0, places=8)


if __name__ == "__main__":
    unittest.main()
