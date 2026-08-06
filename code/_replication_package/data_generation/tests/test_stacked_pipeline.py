from __future__ import annotations

import csv
import shutil
import sys
import unittest
import uuid
from contextlib import contextmanager
from pathlib import Path


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import _stacked_duckdb_core as core  # noqa: E402
import build_all_stacked_datasets_duckdb as wrapper  # noqa: E402


TREATMENT_PATHS = {
    "treated": [0, 0, 0, 0, 1, 1, 1],
    "switching_control": [0, 1, 0, 0, 0, 0, 1],
    "never_treated": [0, 0, 0, 0, 0, 0, 0],
}


def panel_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for grid_id, treatment_path in TREATMENT_PATHS.items():
        for month, treatment in enumerate(treatment_path, start=1):
            rows.append(
                {
                    "unique_small_grid_id": grid_id,
                    "province": "Punjab",
                    "distr_id": 22,
                    "ac_uq_id": 101,
                    "count": month,
                    "mean_brightness": 300.0 + month,
                    "month": month,
                    "year": 2023,
                    "monthyear": 2023 * 12 + month,
                    "downup_ac": treatment,
                    "downup_ac_pop": treatment,
                    "downup_13kmpl": treatment,
                    "protest5km": treatment,
                    "self_profession_nomiss": treatment,
                    "av_wind_speed": 2.5,
                    "wind_direction": 90.0,
                    "rice_prod_aclvl_ahigh": 1,
                    "election_year": 2022,
                    "yeargov": 1,
                }
            )
    return rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


@contextmanager
def temporary_workspace():
    """Create a test directory without tempfile's restrictive Windows ACL."""

    work = DATA_GENERATION / f".stacked_pipeline_test_{uuid.uuid4().hex}"
    work.mkdir()
    try:
        yield work
    finally:
        shutil.rmtree(work)


class StackedEngineTests(unittest.TestCase):
    def test_standard_output_names(self) -> None:
        self.assertEqual(
            {
                spec.treatment_col: spec.output_csv
                for spec in wrapper.STACK_SPECIFICATIONS
            },
            {
                "downup_ac": "combined_dt.csv",
                "downup_ac_pop": "combined_dt_pop.csv",
                "self_profession_nomiss": "politicians_characteristics.csv",
                "protest5km": "stacked_data_protest5km.csv",
                "downup_13kmpl": "stacked_downup_13kmpl.csv",
            },
        )

    def test_clean_spells_and_generated_indicators(self) -> None:
        with temporary_workspace() as work:
            source = work / "panel.csv"
            output = work / "stack.csv"
            database = work / "stack.db"
            write_csv(source, panel_rows())

            result = core.main(
                [
                    "--input",
                    str(source),
                    "--output",
                    str(output),
                    "--database",
                    str(database),
                    "--temp-directory",
                    str(work / "tmp"),
                    "--treatment-col",
                    "downup_ac",
                    "--keep-cols",
                    "unique_small_grid_id",
                    "year",
                    "month",
                    "monthyear",
                    "downup_ac",
                    "--threads",
                    "1",
                    "--memory-limit",
                    "1GB",
                    "--checkpoint-every",
                    "1",
                    "--write-manifest",
                    "--year-level-controls",
                    "--overwrite",
                ]
            )
            self.assertEqual(result, 0)

            rows = read_csv(output)
            cohort = 2023 * 12 + 5
            cohort_rows = [row for row in rows if int(row["cohort"]) == cohort]
            by_grid: dict[str, list[dict[str, str]]] = {}
            for row in cohort_rows:
                by_grid.setdefault(row["unique_small_grid_id"], []).append(row)

            treated = sorted(by_grid["treated"], key=lambda row: int(row["month"]))
            self.assertEqual([int(row["month"]) for row in treated], list(range(1, 8)))
            self.assertEqual({int(row["treat"]) for row in treated}, {1})
            self.assertEqual(
                [int(row["post"]) for row in treated],
                [0, 0, 0, 0, 1, 1, 1],
            )

            switching_control = sorted(
                by_grid["switching_control"],
                key=lambda row: int(row["month"]),
            )
            self.assertEqual(
                [int(row["month"]) for row in switching_control],
                [3, 4, 5, 6],
            )
            self.assertEqual(
                [int(row["relative_monthyear"]) for row in switching_control],
                [-2, -1, 0, 1],
            )
            self.assertEqual(
                [int(row["relative_year"]) for row in switching_control],
                [-1, -1, 0, 0],
            )
            self.assertEqual({int(row["downup_ac"]) for row in switching_control}, {0})
            self.assertEqual({int(row["treat"]) for row in switching_control}, {0})
            self.assertEqual(
                [int(row["post"]) for row in switching_control],
                [0, 0, 1, 1],
            )
            self.assertEqual(
                {int(row["control_type"]) for row in switching_control},
                {2},
            )

            never_treated = by_grid["never_treated"]
            self.assertEqual(len(never_treated), 7)
            self.assertEqual(
                {int(row["control_type"]) for row in never_treated},
                {1},
            )
            self.assertEqual(
                {int(row["control_type"]) for row in treated},
                {0},
            )
            self.assertTrue((work / "stack_manifest.csv").is_file())

    def test_wrapper_uses_full_time_span_and_required_schema(self) -> None:
        with temporary_workspace() as work:
            source = work / "0_master_dataset.csv"
            write_csv(source, panel_rows())

            result = wrapper.main(
                [
                    "--intermediate",
                    str(work),
                    "--input",
                    str(source),
                    "--threads",
                    "1",
                    "--memory-limit",
                    "1GB",
                    "--checkpoint-every",
                    "1",
                    "--overwrite",
                ]
            )
            self.assertEqual(result, 0)

            output = work / "combined_dt.csv"
            rows = read_csv(output)
            self.assertTrue(rows)
            self.assertEqual({int(row["year"]) for row in rows}, {2023})
            self.assertEqual(
                list(rows[0]),
                [*wrapper.COMMON_KEEP_COLUMNS, *wrapper.GENERATED_COLUMNS],
            )
            self.assertIn("mean_brightness", rows[0])
            self.assertEqual({int(row["distr_id"]) for row in rows}, {22})
            self.assertTrue(all(row["mean_brightness"] for row in rows))
            for spec in wrapper.STACK_SPECIFICATIONS:
                spec_output = work / spec.output_csv
                self.assertTrue(spec_output.is_file(), spec.output_csv)
                spec_rows = read_csv(spec_output)
                self.assertTrue(spec_rows, spec.output_csv)
                self.assertEqual(
                    list(spec_rows[0]),
                    [
                        *wrapper.columns_for(spec),
                        *wrapper.generated_columns_for(spec),
                    ],
                )
                if spec.treatment_col in {
                    "self_profession_nomiss",
                    "protest5km",
                }:
                    self.assertIn("relative_year", spec_rows[0])
                    self.assertIn("control_type", spec_rows[0])
                else:
                    self.assertNotIn("relative_year", spec_rows[0])
                    self.assertNotIn("control_type", spec_rows[0])

    def test_wrapper_requires_yeargov_from_master(self) -> None:
        with temporary_workspace() as work:
            source = work / "0_master_dataset.csv"
            rows = panel_rows()
            for row in rows:
                del row["yeargov"]
            write_csv(source, rows)

            with self.assertRaisesRegex(ValueError, "yeargov"):
                wrapper.main(
                    [
                        "--spec",
                        "downup_ac",
                        "--intermediate",
                        str(work),
                        "--input",
                        str(source),
                        "--dry-run",
                    ]
                )

    def test_wrapper_rejects_nonbinary_treatment_before_writing(self) -> None:
        with temporary_workspace() as work:
            source = work / "0_master_dataset.csv"
            rows = panel_rows()
            rows[0]["protest5km"] = 2
            write_csv(source, rows)

            with self.assertRaisesRegex(ValueError, "protest5km=1"):
                wrapper.main(
                    [
                        "--intermediate",
                        str(work),
                        "--input",
                        str(source),
                        "--dry-run",
                    ]
                )
            self.assertFalse((work / "combined_dt.csv").exists())

    def test_new_spec_automatically_keeps_its_treatment(self) -> None:
        spec = wrapper.StackSpecification(
            treatment_col="future_treatment",
            output_csv="future.csv",
            database="future.db",
            temp_directory="future_tmp",
            description="test treatment",
        )
        columns = wrapper.columns_for(spec)
        self.assertIn("future_treatment", columns)
        self.assertEqual(columns.count("future_treatment"), 1)


if __name__ == "__main__":
    unittest.main()
