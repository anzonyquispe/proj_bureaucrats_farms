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

import build_ac_month_panel as panel  # noqa: E402


# Three electoral terms, with the first one left-truncated exactly as in the
# real master: the panel opens in 2012-09 but the 2012-04 assembly took office
# five months earlier, so its predecessor is not in the data and term_seq 1 can
# never have a knowable switch.
TERMS = (
    (2012, 4, 2012),
    (2017, 4, 2017),
    (2022, 4, 2022),
)
PANEL_START = 2012 * 12 + 9        # 2012-09, where the real master opens
PANEL_END = 2023 * 12 + 3          # past the window, so the cut is observable
WINDOW_END = 2022 * 12 + 8         # 2022-08
EXPECTED_MONTHS = WINDOW_END - PANEL_START + 1   # 120

# profession by term (2012, 2017, 2022); None means the profession text was
# blank, which the master folds to 0.
ACS = {
    "ac_switch_2017": (0, 1, 1),
    "ac_switch_2022": (0, 0, 1),
    "ac_never": (0, 0, 0),
    "ac_always": (1, 1, 1),
    "ac_revert": (0, 1, 0),
    "ac_missing_prev": (0, None, 1),
    "ac_late_protest": (0, 0, 0),
}
AC_IDS = {name: 100 + index for index, name in enumerate(ACS, start=1)}

# switch by term_seq (1, 2, 3); None means it must come back empty.
EXPECTED_SWITCH = {
    "ac_switch_2017": (None, 1, 0),
    "ac_switch_2022": (None, 0, 1),
    "ac_never": (None, 0, 0),
    "ac_always": (None, 0, 0),
    "ac_revert": (None, 1, 0),
    "ac_missing_prev": (None, 0, 1),   # spurious: the 2017 text was blank
    "ac_late_protest": (None, 0, 0),
}

# Grids per AC, and the month each grid's protest starts. ac_switch_2017 has
# two grids and only one of them protests, which is what distinguishes the
# "any grid in the AC" rule from an all-grids rule.
GRIDS = {
    "ac_switch_2017": {"g1a": 2021 * 12 + 1, "g1b": None},
    "ac_switch_2022": {"g2": 2022 * 12 + 7},
    "ac_never": {"g3": None},
    "ac_always": {"g4": None},
    "ac_revert": {"g5": None},
    "ac_missing_prev": {"g6": None},
    "ac_late_protest": {"g7": 2022 * 12 + 10},   # after the window closes
}


def term_index_for(monthyear: int) -> int:
    index = 0
    for position, (year, month, _) in enumerate(TERMS):
        if monthyear >= year * 12 + month:
            index = position
    return index


def make_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for ac_name, professions in ACS.items():
        for grid_id, protest_start in GRIDS[ac_name].items():
            for monthyear in range(PANEL_START, PANEL_END + 1):
                term_index = term_index_for(monthyear)
                year_take, month_take, election_year = TERMS[term_index]
                term_start = year_take * 12 + month_take
                year, month = divmod(monthyear - 1, 12)
                profession = professions[term_index]
                rows.append(
                    {
                        "unique_small_grid_id": grid_id,
                        "province": "Punjab",
                        "distr_id": 11,
                        "ac_uq_id": AC_IDS[ac_name],
                        "month": month + 1,
                        "year": year,
                        "monthyear": monthyear,
                        "election_year": election_year,
                        "year_take": year_take,
                        "month_take": month_take,
                        "ym_take": term_start,
                        "yeargov": (monthyear - term_start) // 12 + 1,
                        "self_profession": "" if profession is None else profession,
                        "self_profession_nomiss": 0 if profession is None else profession,
                        "protest5km": (
                            1 if protest_start is not None and monthyear >= protest_start
                            else 0
                        ),
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


def run_builder(work: Path, master: Path, *extra: str) -> list[dict[str, str]]:
    status = panel.main(
        [
            "--intermediate", str(work),
            "--input", str(master),
            "--threads", "1",
            "--memory-limit", "1GB",
            "--end-year", "2022",
            "--end-month", "8",
            "--expected-acs", str(len(ACS)),
            "--expected-months", str(EXPECTED_MONTHS),
            "--overwrite",
            *extra,
        ]
    )
    assert status == 0
    return read_csv(work / f"{panel.OUTPUT_STEM}.csv")


class ACMonthPanelTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.work = DATA_GENERATION / f".acpanel_test_{uuid.uuid4().hex}"
        cls.work.mkdir()
        try:
            cls.master = cls.work / "0_master_dataset.csv"
            write_csv(cls.master, make_rows())
            cls.rows = run_builder(cls.work, cls.master)
        except BaseException:
            shutil.rmtree(cls.work, ignore_errors=True)
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.work, ignore_errors=True)

    def rows_for(self, ac_name: str) -> list[dict[str, str]]:
        wanted = str(AC_IDS[ac_name])
        return sorted(
            (row for row in self.rows if row["ac_uq_id"] == wanted),
            key=lambda row: int(row["monthyear"]),
        )

    def test_panel_is_balanced(self) -> None:
        self.assertEqual(len(self.rows), len(ACS) * EXPECTED_MONTHS)
        keys = {(row["ac_uq_id"], row["year"], row["month"]) for row in self.rows}
        self.assertEqual(len(keys), len(self.rows))
        months = {row["monthyear"] for row in self.rows}
        self.assertEqual(len(months), EXPECTED_MONTHS)
        for ac_name in ACS:
            self.assertEqual(len(self.rows_for(ac_name)), EXPECTED_MONTHS)

    def test_window_closes_at_august_2022(self) -> None:
        months = [int(row["monthyear"]) for row in self.rows]
        self.assertEqual(min(months), PANEL_START)
        self.assertEqual(max(months), WINDOW_END)

    def test_agricola_matches_the_term_profession(self) -> None:
        for ac_name, professions in ACS.items():
            for row in self.rows_for(ac_name):
                index = term_index_for(int(row["monthyear"]))
                expected = professions[index]
                expected = 0 if expected is None else expected
                self.assertEqual(
                    int(row["agricola"]), expected, f"{ac_name} at {row['monthyear']}"
                )

    def test_agricola_and_switch_are_constant_within_a_term(self) -> None:
        for ac_name in ACS:
            by_term: dict[str, set[tuple[str, str]]] = {}
            for row in self.rows_for(ac_name):
                by_term.setdefault(row["term_start"], set()).add(
                    (row["agricola"], row["switch"])
                )
            for term_start, values in by_term.items():
                self.assertEqual(len(values), 1, f"{ac_name} term {term_start}")

    def test_switch_is_empty_not_zero_in_the_first_term(self) -> None:
        """The three-valued-logic trap: NULL AND FALSE would come back as 0."""

        for ac_name in ACS:
            first = [row for row in self.rows_for(ac_name) if row["term_seq"] == "1"]
            self.assertTrue(first, ac_name)
            for row in first:
                self.assertEqual(row["switch"], "", f"{ac_name} at {row['monthyear']}")
                self.assertEqual(row["switch_observable"], "0")

    def test_switch_matches_the_hand_coded_table(self) -> None:
        for ac_name, expected_by_term in EXPECTED_SWITCH.items():
            for row in self.rows_for(ac_name):
                expected = expected_by_term[int(row["term_seq"]) - 1]
                observed = None if row["switch"] == "" else int(row["switch"])
                self.assertEqual(
                    observed, expected, f"{ac_name} term_seq {row['term_seq']}"
                )

    def test_switch_is_term_scoped_while_post_switch_absorbs(self) -> None:
        rows = self.rows_for("ac_revert")
        by_term = {row["term_seq"]: row for row in rows}
        self.assertEqual(by_term["2"]["switch"], "1")
        self.assertEqual(by_term["3"]["switch"], "0")
        self.assertEqual(by_term["1"]["post_switch"], "0")
        self.assertEqual(by_term["2"]["post_switch"], "1")
        self.assertEqual(by_term["3"]["post_switch"], "1")
        self.assertTrue(all(row["ever_switch"] == "1" for row in rows))

    def test_ac_that_never_switches_is_flagged(self) -> None:
        for ac_name in ("ac_never", "ac_always"):
            self.assertTrue(
                all(row["ever_switch"] == "0" for row in self.rows_for(ac_name)),
                ac_name,
            )

    def test_post_protest_takes_any_grid_in_the_ac(self) -> None:
        onset = GRIDS["ac_switch_2017"]["g1a"]
        for row in self.rows_for("ac_switch_2017"):
            expected = 1 if int(row["monthyear"]) >= onset else 0
            self.assertEqual(int(row["post_protest"]), expected, row["monthyear"])
            # One of two grids protests, so the share is exactly a half.
            self.assertAlmostEqual(
                float(row["share_grids_protest"]), 0.5 if expected else 0.0
            )

    def test_post_protest_is_absorbing(self) -> None:
        for ac_name in ACS:
            previous = 0
            for row in self.rows_for(ac_name):
                value = int(row["post_protest"])
                self.assertFalse(previous == 1 and value == 0, ac_name)
                previous = value

    def test_protest_after_the_window_leaves_the_panel_clean(self) -> None:
        """The window is applied last, so a later protest sets no row to 1."""

        rows = self.rows_for("ac_late_protest")
        self.assertTrue(all(row["post_protest"] == "0" for row in rows))
        self.assertEqual(
            int(rows[0]["first_protest_monthyear"]), GRIDS["ac_late_protest"]["g7"]
        )

    def test_ac_without_protests_has_no_onset(self) -> None:
        rows = self.rows_for("ac_never")
        self.assertTrue(all(row["post_protest"] == "0" for row in rows))
        self.assertTrue(all(row["first_protest_monthyear"] == "" for row in rows))

    def test_blank_previous_profession_is_flagged(self) -> None:
        rows = [
            row for row in self.rows_for("ac_missing_prev") if row["term_seq"] == "3"
        ]
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row["switch"], "1")
            self.assertEqual(row["prev_term_profession_missing"], "1")

    def test_summary_has_one_row_per_term(self) -> None:
        summary = read_csv(self.work / f"{panel.SUMMARY_TABLE}.csv")
        self.assertEqual(len(summary), len(ACS) * len(TERMS))
        months = {row["term_seq"]: int(row["months_in_window"]) for row in summary}
        self.assertEqual(months["1"], 2017 * 12 + 4 - PANEL_START)   # 55
        self.assertEqual(months["2"], 60)
        self.assertEqual(months["3"], WINDOW_END - (2022 * 12 + 4) + 1)   # 5

    def test_stata_file_keeps_switch_missing(self) -> None:
        import pandas as pd

        frame = pd.read_stata(self.work / f"{panel.OUTPUT_STEM}.dta")
        self.assertEqual(len(frame), len(ACS) * EXPECTED_MONTHS)
        missing = frame["switch"].isna()
        self.assertTrue((missing == (frame["term_seq"] == 1)).all())

    def test_stata_column_names_survive_intact(self) -> None:
        """Stata truncates past 32 characters and pandas only warns."""

        import pandas as pd

        frame = pd.read_stata(self.work / f"{panel.OUTPUT_STEM}.dta")
        self.assertEqual(list(frame.columns), list(panel.OUTPUT_COLUMNS))
        self.assertEqual(list(self.rows[0]), list(panel.OUTPUT_COLUMNS))


class ACMonthPanelPolicyTests(unittest.TestCase):
    """A second build, so the policy switch is exercised end to end."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.work = DATA_GENERATION / f".acpanel_policy_{uuid.uuid4().hex}"
        cls.work.mkdir()
        try:
            cls.master = cls.work / "0_master_dataset.csv"
            write_csv(cls.master, make_rows())
            cls.rows = run_builder(
                cls.work, cls.master, "--prior-term-missing-policy", "drop"
            )
        except BaseException:
            shutil.rmtree(cls.work, ignore_errors=True)
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.work, ignore_errors=True)

    def test_drop_policy_nulls_the_spurious_switch(self) -> None:
        wanted = str(AC_IDS["ac_missing_prev"])
        rows = [
            row for row in self.rows
            if row["ac_uq_id"] == wanted and row["term_seq"] == "3"
        ]
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row["switch"], "")
            self.assertEqual(row["switch_observable"], "0")

    def test_genuine_switches_survive_the_drop_policy(self) -> None:
        wanted = str(AC_IDS["ac_switch_2017"])
        rows = [
            row for row in self.rows
            if row["ac_uq_id"] == wanted and row["term_seq"] == "2"
        ]
        self.assertTrue(rows)
        self.assertTrue(all(row["switch"] == "1" for row in rows))


class ACMonthPanelGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.work = DATA_GENERATION / f".acpanel_guard_{uuid.uuid4().hex}"
        self.work.mkdir()
        self.master = self.work / "0_master_dataset.csv"

    def tearDown(self) -> None:
        shutil.rmtree(self.work, ignore_errors=True)

    def test_wrong_ac_count_raises(self) -> None:
        write_csv(self.master, make_rows())
        with self.assertRaises(ValueError):
            panel.main(
                [
                    "--intermediate", str(self.work),
                    "--input", str(self.master),
                    "--threads", "1",
                    "--memory-limit", "1GB",
                    "--expected-acs", "1",
                    "--expected-months", str(EXPECTED_MONTHS),
                    "--overwrite",
                ]
            )

    def test_protest_reversal_raises(self) -> None:
        rows = make_rows()
        for row in rows:
            if row["unique_small_grid_id"] == "g1a" and row["monthyear"] == 2021 * 12 + 6:
                row["protest5km"] = 0
        write_csv(self.master, rows)
        with self.assertRaises(ValueError):
            run_builder(self.work, self.master)

    def test_by_election_inside_an_election_year_raises(self) -> None:
        """A second term_start inside one election year is not an election."""

        rows = make_rows()
        for row in rows:
            if (
                row["ac_uq_id"] == AC_IDS["ac_never"]
                and row["election_year"] == 2017
                and row["monthyear"] >= 2019 * 12 + 6
            ):
                row["month_take"] = 6
                row["year_take"] = 2019
                row["ym_take"] = 2019 * 12 + 6
        write_csv(self.master, rows)
        with self.assertRaises(ValueError):
            run_builder(self.work, self.master)


if __name__ == "__main__":
    unittest.main()
