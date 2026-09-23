#!/usr/bin/env python3
"""Build every standard stacked dataset from ``0_master_dataset.parquet``.

This is the public wrapper for the project's stacked-data generation process.
Each specification changes only the binary source treatment and output/work
filenames. Add a ``StackSpecification`` entry to ``STACK_SPECIFICATIONS`` to
generate another treatment definition with the same clean-spell algorithm.

By default all registered specifications run. Use ``--spec`` to run one or a
subset. Standard runs use the full input time span; ``--cutoff-year`` remains
available only as an explicit diagnostic or replication override.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import duckdb

from _stacked_duckdb_core import (
    discover_columns,
    main as run_stack_engine,
    qid,
    source_expression,
)


CLUSTER_INTERMEDIATE = Path(
    "/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/intermediate"
)
LOCAL_INTERMEDIATE = Path(
    r"C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"
    r"\data_output\intermediate"
)


# These source columns are required in every standard stacked output. Generated
# Base generated columns (treat, post, cohort, relative_monthyear) are appended
# by the engine. Year-level specifications additionally receive relative_year
# and control_type.
COMMON_KEEP_COLUMNS = (
    "unique_small_grid_id",
    "province",
    "distr_id",
    "ac_uq_id",
    "count",
    "mean_brightness",
    "month",
    "year",
    "monthyear",
    "downup_ac",
    "downup_ac_pop",
    "av_wind_speed",
    "wind_direction",
    "rice_prod_aclvl_ahigh",
    "election_year",
    "yeargov",
)

GENERATED_COLUMNS = (
    "treat",
    "post",
    "cohort",
    "relative_monthyear",
)

YEAR_CONTROL_COLUMNS = (
    "relative_year",
    "control_type",
)


@dataclass(frozen=True)
class StackSpecification:
    """One treatment/output mapping for the common stack-building engine."""

    treatment_col: str
    output_csv: str
    database: str
    temp_directory: str
    description: str
    extra_columns: tuple[str, ...] = ()
    year_level_controls: bool = False


# Extending the pipeline normally requires only one additional entry here. The
# active treatment column is retained automatically, even when it is not part
# of COMMON_KEEP_COLUMNS.
STACK_SPECIFICATIONS = (
    StackSpecification(
        treatment_col="downup_ac",
        output_csv="combined_dt.csv",
        database="combined_dt.db",
        temp_directory="combined_dt_duckdb_tmp",
        description="AC downwind/upwind area treatment",
    ),
    StackSpecification(
        treatment_col="downup_ac_pop",
        output_csv="combined_dt_pop.csv",
        database="combined_dt_pop.db",
        temp_directory="combined_dt_pop_duckdb_tmp",
        description="AC downwind/upwind population treatment",
    ),
    StackSpecification(
        treatment_col="self_profession_nomiss",
        output_csv="politicians_characteristics.csv",
        database="politicians_characteristics.db",
        temp_directory="politicians_characteristics_duckdb_tmp",
        description="politician self-profession treatment without missing values",
        year_level_controls=True,
    ),
    StackSpecification(
        treatment_col="protest5km",
        output_csv="stacked_data_protest5km.csv",
        database="stacked_data_protest5km.db",
        temp_directory="stacked_data_protest5km_duckdb_tmp",
        description="grid within 5 km of a protest treatment",
        year_level_controls=True,
    ),
    StackSpecification(
        treatment_col="downup_13kmpl",
        output_csv="stacked_downup_13kmpl.csv",
        database="stacked_downup_13kmpl.db",
        temp_directory="stacked_downup_13kmpl_duckdb_tmp",
        description="13 km placebo downwind/upwind population treatment",
    ),
)

SPEC_BY_NAME = {spec.treatment_col: spec for spec in STACK_SPECIFICATIONS}


def default_intermediate() -> Path:
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def unique_ordered(values: Sequence[str]) -> list[str]:
    return list(dict.fromkeys(values))


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--spec",
        action="append",
        default=None,
        metavar="NAME",
        help=(
            "Treatment specification to run. Repeat the option or provide a "
            "comma-separated list. Omit it (or use 'all') to run every spec."
        ),
    )
    parser.add_argument(
        "--list-specs",
        action="store_true",
        help="List configured treatments and outputs, then exit.",
    )
    parser.add_argument(
        "--intermediate",
        type=Path,
        default=default_intermediate(),
        help="Directory containing the master input and receiving all outputs.",
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Master CSV/Parquet. Defaults to INTERMEDIATE/0_master_dataset.parquet.",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--checkpoint-every", type=int, default=25)
    parser.add_argument("--csv-sample-size", type=int, default=100_000)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--delete-database-after", action="store_true")
    parser.add_argument("--sort-final", action="store_true")
    parser.add_argument(
        "--compression",
        choices=["none", "gzip", "zstd"],
        default="none",
    )
    parser.add_argument(
        "--no-write-manifest",
        action="store_false",
        dest="write_manifest",
        help="Do not write the cohort-level manifest CSV.",
    )
    parser.set_defaults(write_manifest=True)
    parser.add_argument("--pre-periods", type=int, default=None)
    parser.add_argument("--post-periods", type=int, default=None)
    parser.add_argument(
        "--post-definition",
        choices=["include_event", "after_event"],
        default="include_event",
    )
    parser.add_argument("--min-pre", type=int, default=0)
    parser.add_argument("--min-post", type=int, default=0)
    parser.add_argument("--require-full-window", action="store_true")
    parser.add_argument("--cohort-min", type=int, default=None)
    parser.add_argument("--cohort-max", type=int, default=None)
    parser.add_argument(
        "--cutoff-year",
        type=int,
        default=None,
        help="Optional explicit cutoff. Standard runs leave this unset.",
    )
    parser.add_argument("--cutoff-month", type=int, default=12)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING"],
        default="INFO",
    )
    return parser.parse_args(argv)


def selected_specifications(raw_specs: Sequence[str] | None) -> list[StackSpecification]:
    if not raw_specs:
        return list(STACK_SPECIFICATIONS)

    requested: list[str] = []
    for raw in raw_specs:
        requested.extend(part.strip() for part in raw.split(",") if part.strip())
    if not requested or "all" in requested:
        if len(set(requested) - {"all"}) > 0:
            raise ValueError("Use --spec all by itself, or list individual specs.")
        return list(STACK_SPECIFICATIONS)

    unknown = sorted(set(requested) - set(SPEC_BY_NAME))
    if unknown:
        choices = ", ".join(SPEC_BY_NAME)
        raise ValueError(
            f"Unknown stack specification(s): {', '.join(unknown)}. "
            f"Available: {choices}."
        )
    requested_set = set(requested)
    return [
        spec for spec in STACK_SPECIFICATIONS if spec.treatment_col in requested_set
    ]


def columns_for(spec: StackSpecification) -> list[str]:
    return unique_ordered(
        [*COMMON_KEEP_COLUMNS, *spec.extra_columns, spec.treatment_col]
    )


def generated_columns_for(spec: StackSpecification) -> list[str]:
    columns = list(GENERATED_COLUMNS)
    if spec.year_level_controls:
        columns.extend(YEAR_CONTROL_COLUMNS)
    return columns


def preflight_input(
    input_path: Path,
    specifications: Sequence[StackSpecification],
    csv_sample_size: int,
) -> list[str]:
    if not input_path.is_file():
        raise FileNotFoundError(input_path)
    connection = duckdb.connect()
    try:
        source_sql = source_expression(input_path, csv_sample_size)
        source_columns = discover_columns(connection, source_sql)
        required = unique_ordered(
            [
                *COMMON_KEEP_COLUMNS,
                *(
                    column
                    for spec in specifications
                    for column in (*spec.extra_columns, spec.treatment_col)
                ),
            ]
        )
        missing = [column for column in required if column not in source_columns]
        if missing:
            raise ValueError(
                "Master input is missing required stacking columns: "
                + ", ".join(missing)
            )

        invalid_expressions = []
        for spec in specifications:
            treatment = qid(spec.treatment_col)
            invalid_expressions.append(
                "count_if("
                f"{treatment} IS NOT NULL AND ("
                f"try_cast({treatment} AS DOUBLE) IS NULL OR "
                f"try_cast({treatment} AS DOUBLE) NOT IN (0.0, 1.0)))"
            )
        invalid_counts = connection.execute(
            "SELECT " + ", ".join(invalid_expressions) + " FROM source_raw"
        ).fetchone()
        invalid = {
            spec.treatment_col: int(count)
            for spec, count in zip(specifications, invalid_counts)
            if int(count)
        }
        if invalid:
            details = ", ".join(
                f"{column}={count:,}" for column, count in invalid.items()
            )
            raise ValueError(
                "Treatment columns contain nonmissing values outside 0/1: "
                + details
            )
    finally:
        connection.close()
    return source_columns


def append_option(argv: list[str], option: str, value: object | None) -> None:
    if value is not None:
        argv.extend([option, str(value)])


def engine_arguments(
    args: argparse.Namespace,
    spec: StackSpecification,
    input_path: Path,
    intermediate: Path,
) -> list[str]:
    argv = [
        "--input",
        str(input_path),
        "--output",
        str(intermediate / spec.output_csv),
        "--database",
        str(intermediate / spec.database),
        "--temp-directory",
        str(intermediate / spec.temp_directory),
        "--treatment-col",
        spec.treatment_col,
        "--keep-cols",
        *columns_for(spec),
        "--threads",
        str(args.threads),
        "--memory-limit",
        args.memory_limit,
        "--checkpoint-every",
        str(args.checkpoint_every),
        "--csv-sample-size",
        str(args.csv_sample_size),
        "--compression",
        args.compression,
        "--post-definition",
        args.post_definition,
        "--min-pre",
        str(args.min_pre),
        "--min-post",
        str(args.min_post),
        "--cutoff-month",
        str(args.cutoff_month),
        "--log-level",
        args.log_level,
    ]
    append_option(argv, "--pre-periods", args.pre_periods)
    append_option(argv, "--post-periods", args.post_periods)
    append_option(argv, "--cohort-min", args.cohort_min)
    append_option(argv, "--cohort-max", args.cohort_max)
    append_option(argv, "--cutoff-year", args.cutoff_year)
    if args.require_full_window:
        argv.append("--require-full-window")
    if args.overwrite:
        argv.append("--overwrite")
    if args.delete_database_after:
        argv.append("--delete-database-after")
    if args.sort_final:
        argv.append("--sort-final")
    if args.write_manifest:
        argv.append("--write-manifest")
    if spec.year_level_controls:
        argv.append("--year-level-controls")
    return argv


def print_specifications() -> None:
    for spec in STACK_SPECIFICATIONS:
        print(
            f"{spec.treatment_col}: {spec.output_csv} "
            f"({spec.description})"
        )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.list_specs:
        print_specifications()
        return 0

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    specifications = selected_specifications(args.spec)
    intermediate = args.intermediate.resolve()
    input_path = (
        args.input.resolve()
        if args.input
        else intermediate / "0_master_dataset.parquet"
    )
    source_columns = preflight_input(
        input_path,
        specifications,
        args.csv_sample_size,
    )
    intermediate.mkdir(parents=True, exist_ok=True)

    logging.info("Master input: %s", input_path)
    logging.info("Master columns: %s", f"{len(source_columns):,}")
    logging.info(
        "Specifications: %s",
        ", ".join(spec.treatment_col for spec in specifications),
    )
    if args.cutoff_year is None:
        logging.info("Time coverage: full master dataset (no cutoff)")
    else:
        logging.warning(
            "Explicit cutoff enabled: %s-%02d",
            args.cutoff_year,
            args.cutoff_month,
        )

    for index, spec in enumerate(specifications, start=1):
        stack_argv = engine_arguments(args, spec, input_path, intermediate)
        logging.info(
            "Stack %s/%s: treatment=%s output=%s",
            index,
            len(specifications),
            spec.treatment_col,
            intermediate / spec.output_csv,
        )
        if args.dry_run:
            logging.info("Dry run: %s", " ".join(stack_argv))
            continue
        result = run_stack_engine(stack_argv)
        if result:
            return int(result)

    if args.dry_run:
        logging.info("Dry run completed; no outputs were written.")
    else:
        logging.info("Completed %s stacked dataset(s).", len(specifications))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        logging.error("Interrupted. Re-run the same command to resume completed cohorts.")
        raise SystemExit(130)
    except Exception as exc:
        logging.exception("Stacked-data pipeline failed: %s", exc)
        raise SystemExit(1)
