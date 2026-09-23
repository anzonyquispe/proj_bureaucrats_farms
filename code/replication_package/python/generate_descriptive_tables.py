#!/usr/bin/env python3
"""Generate the three descriptive tables actively input by main.tex.

This is a clean, non-notebook translation of the original descriptive R files.
The numerical definitions and row ordering are preserved.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


HEADERS = ["", "Mean", "SD", "Min", "Max", "Observations", "Unique Obs."]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--sample", default="")
    parser.add_argument("--rural-var", default="is_rural_area")
    return parser.parse_args()


def require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required input does not exist: {path}")
    return path


def fmt_number(value: float, digits: int = 3) -> str:
    if pd.isna(value) or not np.isfinite(value):
        return ""
    text = f"{value:,.{digits}f}"
    return text.rstrip("0").rstrip(".")


def fmt_integer(value: float) -> str:
    return "" if pd.isna(value) else f"{int(value):,}"


def latex_table(rows: list[list[str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    align = "l" + "r" * (len(HEADERS) - 1)
    lines = [
        f"\\begin{{tabular}}{{{align}}}",
        "\\toprule",
        " & ".join(HEADERS) + r" \\",
        "\\midrule",
    ]
    lines.extend(" & ".join(row) + r" \\" for row in rows)
    lines.extend(["\\bottomrule", "\\end{tabular}"])
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated: {output}")


def load_rural(data: pd.DataFrame, intermediate: Path, rural_var: str) -> pd.DataFrame:
    ghs = pd.read_stata(require(intermediate / "ghs_grid_classification_2000.dta"))
    if rural_var not in ghs.columns:
        # Older mirrors used `is_rural`; retain compatibility while making the
        # requested classifier explicit in the merged frame.
        if rural_var == "is_rural_area" and "is_rural" in ghs.columns:
            ghs = ghs.rename(columns={"is_rural": rural_var})
        else:
            raise KeyError(f"{rural_var!r} is absent from the rural-classification file")
    cols = ["unique_small_grid_id", rural_var]
    merged = data.merge(ghs[cols], on="unique_small_grid_id", how="left")
    return merged.loc[merged[rural_var].eq(1)].copy()


def summary_rows(
    data: pd.DataFrame,
    variables: Iterable[str],
    labels: dict[str, str],
    continuous: set[str],
    unique_only: set[str] | None = None,
) -> list[list[str]]:
    rows: list[list[str]] = []
    unique_only = unique_only or set()
    for variable in variables:
        if variable not in data.columns:
            raise KeyError(f"Required descriptive variable is absent: {variable}")
        series = data[variable]
        valid = series.dropna()
        if variable in unique_only:
            rows.append([labels[variable], "", "", "", "", "", fmt_integer(valid.nunique())])
            continue
        if variable in continuous:
            numeric = pd.to_numeric(valid, errors="coerce").dropna()
            stats = [
                fmt_number(numeric.mean()),
                fmt_number(numeric.std(ddof=1)),
                fmt_number(numeric.min()),
                fmt_number(numeric.max()),
            ]
        else:
            stats = ["", "", "", ""]
        rows.append(
            [labels[variable], *stats, fmt_integer(valid.shape[0]), fmt_integer(valid.nunique())]
        )
    return rows


def add_group_ids(data: pd.DataFrame) -> pd.DataFrame:
    result = data.copy()
    result["prov"] = pd.factorize(result["province"], sort=False)[0] + 1
    keys = pd.MultiIndex.from_frame(result[["province", "election_year"]])
    result["legis.govyear"] = pd.factorize(keys, sort=False)[0] + 1
    return result


def merge_rice(data: pd.DataFrame, intermediate: Path) -> pd.DataFrame:
    rice = pd.read_stata(require(intermediate / "rice_moderators.dta"))
    return data.merge(rice, on=["unique_small_grid_id", "ac_uq_id"], how="left", suffixes=("", "_rice"))


def main_descriptives(intermediate: Path, tables: Path, sample: str, rural_var: str) -> None:
    data = pd.read_csv(require(intermediate / f"0_master_merge_data_gen{sample}.csv"), low_memory=False)
    data = data.loc[(data.year < 2022) | ((data.year == 2022) & (data.month <= 8))]
    data = load_rural(data, intermediate, rural_var)
    data["prov"] = pd.factorize(data["province"], sort=False)[0] + 1
    data = data.rename(columns={"count": "count_fires"})
    variables = [
        "unique_small_grid_id", "year", "month", "ac_uq_id", "prov", "count_fires",
        "downup_ac_pop", "av_wind_speed", "wind_direction", "rice_prod_aclvl_ahigh",
    ]
    labels = dict(zip(variables, [
        "Grid ID", "Year", "Month", "Assembly", "Province", "Number of Fires",
        r"Down $\times$ Up AC Pop", "Average Wind Speed", "Wind Direction", "Rice Production",
    ]))
    rows = summary_rows(
        data, variables, labels,
        continuous=set(variables) - {"unique_small_grid_id", "year", "month", "ac_uq_id", "prov"},
        unique_only={"unique_small_grid_id", "year", "month", "ac_uq_id", "prov"},
    )
    latex_table(rows, tables / "descriptives_main.tex")


def protest_descriptives(intermediate: Path, tables: Path, sample: str, rural_var: str) -> None:
    data = pd.read_csv(require(intermediate / f"stacked_data_protest{sample}.csv"), low_memory=False)
    data = merge_rice(add_group_ids(load_rural(data, intermediate, rural_var)), intermediate)
    data["post"] = data["relative_year_bin"].ge(0).astype(int)
    data["protest"] = data["post"] * data["treat"]
    variables = [
        "unique_small_grid_id", "year", "month", "ac_uq_id", "prov", "ac_area_tr",
        "cohort", "legis.govyear", "relative_year_bin", "protest", "count.k",
        "rice_prod_aclvl_ahigh",
    ]
    labels = dict(zip(variables, [
        "Grid ID", "Year", "Month", "Assembly Constituency (AC)", "Province",
        "Protest Area", "Cohort", "Legislature", "Relative year", "Protest",
        "Number of Fires", "High Rice production (AC level)",
    ]))
    rows = summary_rows(
        data, variables, labels,
        continuous={"count.k", "rice_prod_aclvl_ahigh", "protest", "relative_year_bin"},
    )
    latex_table(rows, tables / "_protest_stacked_descriptive.tex")


def politician_descriptives(intermediate: Path, tables: Path, sample: str, rural_var: str) -> None:
    data = pd.read_csv(require(intermediate / f"politicians_characteristics{sample}.csv"), low_memory=False)
    data = merge_rice(add_group_ids(load_rural(data, intermediate, rural_var)), intermediate)
    data["post"] = data["relative_year_bin"].ge(0).astype(int)
    data["agri_politician"] = data["post"] * data["treat"]
    data["countk"] = data["count"] * 1000
    variables = [
        "unique_small_grid_id", "year", "month", "ac_uq_id", "prov", "election_year",
        "cohort", "legis.govyear", "relative_year_bin", "agri_politician", "countk",
        "rice_prod_aclvl_ahigh",
    ]
    labels = dict(zip(variables, [
        "Grid ID", "Year", "Month", "Assembly Constituency (AC)", "Province",
        "Election Year", "Cohort", "Legislature", "Relative year",
        "Agricultural Politician", "Number of Fires", "High Rice production (AC level)",
    ]))
    rows = summary_rows(
        data, variables, labels,
        continuous={"countk", "rice_prod_aclvl_ahigh", "relative_year_bin"},
    )
    latex_table(rows, tables / "_politicians_stacked_descriptive.tex")


def main() -> None:
    args = parse_args()
    intermediate = args.root / "data_output" / "intermediate"
    tables = args.root / "tex" / "paper" / "tables"
    main_descriptives(intermediate, tables, args.sample, args.rural_var)
    protest_descriptives(intermediate, tables, args.sample, args.rural_var)
    politician_descriptives(intermediate, tables, args.sample, args.rural_var)


if __name__ == "__main__":
    main()
