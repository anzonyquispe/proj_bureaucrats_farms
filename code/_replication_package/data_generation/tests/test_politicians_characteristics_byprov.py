from __future__ import annotations

import csv
import shutil
import sys
import unittest
import uuid
from pathlib import Path


DATA_GENERATION = Path(__file__).resolve().parents[1]
if str(DATA_GENERATION) not in sys.path:
    sys.path.insert(0, str(DATA_GENERATION))

import build_politicians_characteristics_byprov as byprov  # noqa: E402


def make_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    units = {
        "Punjab_treated": ("Punjab", 11, [0, 0, 1, 1]),
        "Punjab_control": ("Punjab", 11, [0, 0, 0, 0]),
        "Haryana_treated": ("Haryana", 22, [0, 0, 1, 1]),
        "Haryana_control": ("Haryana", 22, [0, 0, 0, 0]),
    }
    for grid_id, (province, district, treatment_path) in units.items():
        for month, treatment in enumerate(treatment_path, start=1):
            rows.append(
                {
                    "unique_small_grid_id": grid_id,
                    "province": province,
                    "distr_id": district,
                    "ac_uq_id": district * 10,
                    "count": month,
                    "mean_brightness": 300.0 + month,
                    "month": month,
                    "year": 2022,
                    "monthyear": 2022 * 12 + month,
                    "downup_ac": 0,
                    "downup_ac_pop": 0,
                    "av_wind_speed": 2.5,
                    "wind_direction": 90.0,
                    "rice_prod_aclvl_ahigh": 1,
                    "election_year": 2022,
                    "year_take": 2022,
                    "month_take": 3,
                    "yeargov": 1,
                    "self_profession_nomiss": treatment,
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


class PoliticianCharacteristicsByProvinceTests(unittest.TestCase):
    def test_shared_cluster_pipelines_include_byprovince_stack(self) -> None:
        expected_command = "build_politicians_characteristics_byprov.py"
        for filename in (
            "build_stacked_datasets.sbatch",
            "build_master_and_stacked_datasets.sh",
        ):
            contents = (DATA_GENERATION / filename).read_text(encoding="utf-8")
            self.assertIn(expected_command, contents, filename)

    def test_controls_are_restricted_to_province_election_cohort(self) -> None:
        work = DATA_GENERATION / f".byprov_test_{uuid.uuid4().hex}"
        work.mkdir()
        try:
            source = work / "0_master_dataset.csv"
            write_csv(source, make_rows())

            result = byprov.main(
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
                    "--last-cohort-year",
                    "2022",
                    "--last-cohort-month",
                    "12",
                    "--expected-cohorts",
                    "2",
                    "--overwrite",
                ]
            )
            self.assertEqual(result, 0)

            rows = read_csv(work / byprov.OUTPUT_NAME)
            self.assertTrue(rows)
            self.assertEqual({int(row["cohort_id"]) for row in rows}, {1, 2})
            self.assertIn("cohort_province", rows[0])
            self.assertIn("cohort_year", rows[0])
            self.assertIn("cohort_month", rows[0])
            self.assertIn("relative_year", rows[0])
            self.assertIn("control_type", rows[0])

            for cohort_id in {1, 2}:
                cohort_rows = [
                    row for row in rows if int(row["cohort_id"]) == cohort_id
                ]
                self.assertEqual(
                    len({row["province"] for row in cohort_rows}),
                    1,
                )
                self.assertEqual(
                    {int(row["treat"]) for row in cohort_rows},
                    {0, 1},
                )

            manifest = read_csv(work / byprov.MANIFEST_NAME)
            self.assertEqual(len(manifest), 2)
            self.assertEqual(
                {row["province"] for row in manifest},
                {"Punjab", "Haryana"},
            )
        finally:
            shutil.rmtree(work)


if __name__ == "__main__":
    unittest.main()
