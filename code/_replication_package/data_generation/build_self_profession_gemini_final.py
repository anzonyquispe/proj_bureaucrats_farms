#!/usr/bin/env python3
"""Build the pipeline-ready Gemini self-profession table and validation sample.

The final table preserves every row and column from the historical winners table,
replaces ``self_profession`` with the Gemini majority-rule result, and appends the
classification inputs and audit fields. Blank/unavailable profession descriptions
remain missing; they are never converted to zero.

The validation file follows the previous validation design: its target size is
10 percent of the full table (rounded up), blank professions are excluded, each
normalized profession appears once, and classes 0 and 1 are balanced as closely
as possible. Empty columns are included for manual review.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Sequence

import numpy as np
import pandas as pd


DEFAULT_BASE_TABLE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\data\input\my_neta\2008_onwards_winners_table.csv"
)
DEFAULT_GEMINI_DETAILS = Path(
    r"C:\Users\eunic\OneDrive\Documents\GitHub\ownpkg\myneta_llm\data"
    r"\gemini_self_prof_batch_historical\final\self_profession_majority_detailed.csv"
)
DEFAULT_OUTPUT_DIRECTORY = DEFAULT_GEMINI_DETAILS.parent
DEFAULT_SAMPLE_FRACTION = 0.10
DEFAULT_RANDOM_SEED = 20260821


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--base-table", type=Path, default=DEFAULT_BASE_TABLE)
    parser.add_argument("--gemini-details", type=Path, default=DEFAULT_GEMINI_DETAILS)
    parser.add_argument("--output-directory", type=Path, default=DEFAULT_OUTPUT_DIRECTORY)
    parser.add_argument("--sample-fraction", type=float, default=DEFAULT_SAMPLE_FRACTION)
    parser.add_argument("--random-seed", type=int, default=DEFAULT_RANDOM_SEED)
    return parser.parse_args(argv)


def read_inputs(base_path: Path, details_path: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    if not base_path.is_file():
        raise FileNotFoundError(f"Base table not found: {base_path}")
    if not details_path.is_file():
        raise FileNotFoundError(f"Gemini details not found: {details_path}")

    base = pd.read_csv(base_path)
    details = pd.read_csv(details_path)
    required_base = {"unique_id", "self_profession"}
    required_details = {
        "unique_id",
        "profession_text",
        "profession_normalized",
        "source_status",
        "source_file",
        "valid_votes",
        "votes_1",
        "votes_0",
        "majority_agri_profession",
        "majority_reasoning",
        "classification_source",
    }
    missing_base = sorted(required_base - set(base.columns))
    missing_details = sorted(required_details - set(details.columns))
    if missing_base:
        raise ValueError(f"Base table is missing columns: {missing_base}")
    if missing_details:
        raise ValueError(f"Gemini details are missing columns: {missing_details}")
    if base["unique_id"].duplicated().any():
        raise ValueError("Base table has duplicate unique_id values.")
    if details["unique_id"].duplicated().any():
        raise ValueError("Gemini details have duplicate unique_id values.")
    return base, details


def report_key_overlap(base: pd.DataFrame, details: pd.DataFrame) -> None:
    overlap = base[["unique_id"]].merge(
        details[["unique_id"]],
        on="unique_id",
        how="outer",
        indicator=True,
        validate="one_to_one",
    )
    counts = overlap["_merge"].value_counts().reindex(
        ["left_only", "right_only", "both"], fill_value=0
    )
    print("Full-outer unique_id overlap:")
    for category, count in counts.items():
        print(f"  {category}: {count:,}")
    if counts["left_only"] or counts["right_only"]:
        raise ValueError("The base table and Gemini details do not have identical unique_id keys.")


def build_final_table(base: pd.DataFrame, details: pd.DataFrame) -> pd.DataFrame:
    audit_columns = [
        "unique_id",
        "profession_text",
        "profession_normalized",
        "source_status",
        "source_file",
        "valid_votes",
        "votes_1",
        "votes_0",
        "majority_agri_profession",
        "majority_reasoning",
        "classification_source",
    ]
    original_columns = list(base.columns)
    self_profession_position = original_columns.index("self_profession")

    base = base.rename(columns={"self_profession": "self_profession_original"})
    final = base.merge(
        details[audit_columns],
        on="unique_id",
        how="left",
        validate="one_to_one",
    )
    final["self_profession"] = pd.to_numeric(
        final["majority_agri_profession"], errors="coerce"
    ).astype("Int64")
    final["self_profession_gemini"] = final["self_profession"]
    final["self_profession_missing"] = final["self_profession"].isna().astype("Int64")

    # Enforce the original >=7 majority rule for all nonmissing classifications.
    expected = pd.Series(pd.NA, index=final.index, dtype="Int64")
    has_votes = final["valid_votes"].eq(10)
    expected.loc[has_votes] = final.loc[has_votes, "votes_1"].ge(7).astype("Int64")
    mismatch = has_votes & final["self_profession"].ne(expected).fillna(True)
    if mismatch.any():
        examples = final.loc[mismatch, ["unique_id", "votes_1", "self_profession"]].head()
        raise ValueError(f"Gemini labels violate the >=7 rule:\n{examples.to_string(index=False)}")

    missing = final["self_profession"].isna()
    if not final.loc[missing, "source_status"].eq("blank_profession").all():
        raise ValueError("A missing classification exists for a nonblank profession.")
    if final.loc[~missing, "valid_votes"].ne(10).any():
        raise ValueError("A classified row does not have exactly 10 valid votes.")

    pipeline_columns = original_columns.copy()
    pipeline_columns[self_profession_position] = "self_profession"
    appended_columns = [
        "self_profession_original",
        "self_profession_gemini",
        "self_profession_missing",
        "profession_text",
        "profession_normalized",
        "source_status",
        "source_file",
        "valid_votes",
        "votes_1",
        "votes_0",
        "majority_reasoning",
        "classification_source",
    ]
    return final[pipeline_columns + appended_columns]


def build_validation_sample(
    final: pd.DataFrame,
    sample_fraction: float,
    random_seed: int,
) -> pd.DataFrame:
    if not 0 < sample_fraction <= 1:
        raise ValueError("--sample-fraction must be greater than 0 and at most 1.")
    sample_size = math.ceil(len(final) * sample_fraction)
    working = (
        final.dropna(subset=["self_profession", "profession_normalized"])
        .sort_values("unique_id")
        .drop_duplicates("profession_normalized")
        .copy()
    )
    class_targets = {1: math.ceil(sample_size / 2), 0: math.floor(sample_size / 2)}
    sampled_parts = []
    for class_value, count in class_targets.items():
        class_rows = working.loc[working["self_profession"].eq(class_value)]
        if len(class_rows) < count:
            raise ValueError(
                f"Class {class_value} has only {len(class_rows)} distinct profession texts; "
                f"{count} are required."
            )
        sampled_parts.append(class_rows.sample(n=count, random_state=random_seed))
    sample = pd.concat(sampled_parts, ignore_index=True)
    sample = sample.sample(frac=1, random_state=random_seed).reset_index(drop=True)
    sample.insert(0, "review_id", np.arange(1, len(sample) + 1))
    sample["manual_correct"] = pd.Series(pd.NA, index=sample.index, dtype="Int64")
    sample["manual_agri_profession"] = pd.Series(pd.NA, index=sample.index, dtype="Int64")
    sample["reviewer_notes"] = ""
    if len(sample) != sample_size:
        raise AssertionError(f"Expected {sample_size} validation rows; obtained {len(sample)}.")
    if sample["unique_id"].duplicated().any():
        raise AssertionError("Validation sample contains duplicate unique_id values.")
    if sample["profession_normalized"].duplicated().any():
        raise AssertionError("Validation sample contains duplicate normalized professions.")
    return sample


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    base, details = read_inputs(args.base_table, args.gemini_details)
    report_key_overlap(base, details)
    final = build_final_table(base, details)
    validation = build_validation_sample(final, args.sample_fraction, args.random_seed)

    args.output_directory.mkdir(parents=True, exist_ok=True)
    final_path = args.output_directory / "2008_onwards_winners_table_gemini.csv"
    validation_path = args.output_directory / "validation_sample_10pct.csv"
    final.to_csv(final_path, index=False)
    validation.to_csv(validation_path, index=False)

    label_counts = final["self_profession"].value_counts(dropna=False).sort_index()
    validation_counts = validation["self_profession"].value_counts(dropna=False).sort_index()
    print(f"Final rows: {len(final):,}")
    print(f"Final unique unique_id values: {final['unique_id'].nunique():,}")
    print(f"Final self_profession counts:\n{label_counts.to_string()}")
    print(f"Validation rows: {len(validation):,} ({len(validation) / len(final):.2%})")
    print(f"Validation class counts:\n{validation_counts.to_string()}")
    print(f"Pipeline-ready CSV: {final_path}")
    print(f"Validation CSV: {validation_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
