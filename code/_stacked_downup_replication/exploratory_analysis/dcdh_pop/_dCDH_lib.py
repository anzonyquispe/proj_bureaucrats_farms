"""
_dCDH_lib.py

Shared helpers for the dCDH analysis pipeline.

Loads the current Parquet master panel, applies the same balanced-panel + reset transformation
as the Stata block embedded inside the did_multiplegt_dyn package, fits a
DidMultiplegtDyn model for both no-trend and ac-trend variants, and writes
outputs to every directory in OUT_DIRS.

Memory-efficient by design:
  * Lazy scan of 0_master_dataset.parquet; rural / time / dpl_ac filters pushed into the scan
  * Native polars Stata reader (no pandas roundtrip)
  * IDs cast to compact integer types after the joins
  * Only the columns needed by the model are passed to DidMultiplegtDyn
  * Headless matplotlib backend (`Agg`)
  * After every fit: `plt.close('all')`, `del model`, `gc.collect()`
  * `ZeroDivisionError` inside the package is caught and logged; the run keeps going

Env vars:
  ROOT             Override the data root. If unset, auto-detects:
                     1) cluster path  (/groups/sgulzar/sa_fires/proj_bureaucrats_farms)
                     2) Mac Dropbox path
  SAMPLE           "" | "_sample" suffix on the master Parquet file
  DCDH_LOCAL_OUT   Override the second output dir (default cluster home tree)
"""

from __future__ import annotations

import gc
import os
import sys
import traceback
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import polars as pl
import pyreadstat


def _read_dta(path: str | os.PathLike) -> pl.DataFrame:
    """Read a Stata .dta into a polars DataFrame via pyreadstat."""
    pdf, _meta = pyreadstat.read_dta(str(path))
    return pl.from_pandas(pdf)


# ---- Configuration ---------------------------------------------------------

CLUSTER_ROOT = "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
DBOX_ROOT    = ("/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/"
                "sa_fires/proj_bureaucrats_farms")


def _detect_root() -> str:
    """Pick ROOT from env, else first existing of cluster -> Mac Dropbox."""
    env_root = os.environ.get("ROOT", "").strip()
    if env_root:
        return env_root
    for candidate in (CLUSTER_ROOT, DBOX_ROOT):
        if Path(candidate).exists():
            return candidate
    raise RuntimeError(
        "Could not auto-detect ROOT. Set the ROOT env var or make sure one "
        f"of these paths exists:\n  {CLUSTER_ROOT}\n  {DBOX_ROOT}"
    )


ROOT   = _detect_root()
SAMPLE = os.environ.get("SAMPLE", "")
print(f"[lib] ROOT   = {ROOT}")
print(f"[lib] SAMPLE = {SAMPLE!r}")

INTERMEDIATE_DIR = Path(ROOT) / "data_output" / "intermediate"
MASTER_PARQUET = INTERMEDIATE_DIR / f"0_master_dataset{SAMPLE}.parquet"
GHS_DTA    = INTERMEDIATE_DIR / "ghs_grid_classification_2000.dta"
GRIDS_DTA  = INTERMEDIATE_DIR / "grids_with_more_1_ac.dta"

OUT_DIRS = [
    INTERMEDIATE_DIR / "dCDH",
    Path(os.environ.get(
        "DCDH_LOCAL_OUT",
        "/users/aquisper/proj_bureaucrats_farms/code/"
        "_stacked_downup_replication/exploratory_analysis/dcdh_pop/results",
    )),
]


def _import_didmlt():
    """Lazy import so the heavy package isn't loaded for utility runs."""
    from did_multiplegt_dyn import DidMultiplegtDyn
    return DidMultiplegtDyn


# ---- Data loading ----------------------------------------------------------

def load_panel(treatment: str) -> pl.DataFrame:
    """
    Load the analysis sample for the given treatment column.

    Mirrors the Stata dofile chain:
      * inner-merge with rural classifier; keep is_rural == 1
      * left-merge with grids_with_more_1_ac; drop dpl_ac == 1
      * keep year < 2022 or (year == 2022 and month <= 8)
      * gen countk = count * 1000

    The two .dta lookups are read first to get the rural / excluded grid lists;
    those are then pushed into the Parquet scan as `is_in` filters so the
    master panel never lands in memory at full size.
    """
    if not MASTER_PARQUET.exists():
        raise FileNotFoundError(
            "Current master Parquet is missing: "
            f"{MASTER_PARQUET}. Run build_0_master_dataset.py first."
        )
    print(f"[load] master Parquet: {MASTER_PARQUET}")
    print(f"[load] treatment column: {treatment}")

    panel_scan = pl.scan_parquet(str(MASTER_PARQUET))
    grid_dtype = panel_scan.collect_schema()["unique_small_grid_id"]

    # Small lookups -- align IDs to the Parquet key type before is_in.
    ghs = _read_dta(GHS_DTA).select(
        ["unique_small_grid_id", "is_rural"]
    )
    rural_grids = (
        ghs.filter(pl.col("is_rural") == 1)["unique_small_grid_id"]
        .cast(grid_dtype)
    )

    grids = _read_dta(GRIDS_DTA)
    excluded_grids = (
        grids.filter(pl.col("dpl_ac") == 1)["unique_small_grid_id"]
        .cast(grid_dtype)
    )

    keep_cols = [
        "count", "unique_small_grid_id", "monthyear",
        "year", "month", treatment, "ac_uq_id",
        "av_wind_speed", "wind_direction", "province",
    ]

    df = (
        panel_scan
          .select(keep_cols)
          .filter(pl.col("unique_small_grid_id").is_in(rural_grids))
          .filter(~pl.col("unique_small_grid_id").is_in(excluded_grids))
          .filter(
              (pl.col("year") < 2022)
              | ((pl.col("year") == 2022) & (pl.col("month") <= 8))
          )
          .with_columns([(pl.col("count") * 1000).alias("countk")])
          .collect()
    )

    print(f"[load] rows after filters: {df.height:,}")
    print(f"[load] unique grids:       {df['unique_small_grid_id'].n_unique():,}")
    print(f"[load] unique ac_uq_id:    {df['ac_uq_id'].n_unique():,}")

    # Drop lookups before returning
    del ghs, grids, rural_grids, excluded_grids
    gc.collect()
    return df


# ---- Reset transformations -------------------------------------------------

def apply_reset(
    df: pl.DataFrame,
    reset: int,
    group_col: str,
    treatment_col: str,
    time_col: str,
    cluster: str | None = None,
) -> tuple[pl.DataFrame, str]:
    """
    Polars port of the `reset` block from did_multiplegt_dyn's internal Stata
    code.

    Steps (matching the Stata snippet verbatim):
      1. Balance: drop groups whose count of non-missing treatment is below
         the GLOBAL max (Stata `sum` -> `r(max)`).
      2. changed_XX = (treatment != treatment[_n-1]), 0 on first obs per group.
      3. spell_XX   = cum_sum(changed_XX) per group ordered by time.
      4. periods_since_change_XX = _n - 1 within (group, spell); 0 when spell == 0.
      5. reset_dummy_XX = (periods_since_change_XX == reset).
      6. reset_count_XX = cum_sum(reset_dummy_XX) per group.
      7. new_group_XX  = dense_rank over (group, reset_count).
      8. If cluster is None, save old_group_XX = group_col BEFORE the rename
         and use it as the default cluster.
      9. Replace group_col with new_group_XX.
    """
    if reset == 0:
        if cluster is None:
            cluster = group_col
        return df, cluster

    # 1. Balance panel
    df = df.with_columns(
        pl.col(treatment_col).is_not_null().cast(pl.Int32)
          .sum().over(group_col).alias("_count_d_non_miss")
    )
    global_max = df["_count_d_non_miss"].max()
    n_before = df.height
    df = df.filter(pl.col("_count_d_non_miss") == global_max).drop("_count_d_non_miss")
    print(f"[reset={reset}] balanced panel: kept {df.height:,} / {n_before:,} rows")

    # Sort within group by time so cum_sum/shift respect chronological order.
    df = df.sort([group_col, time_col])

    # 2-6. Spell/reset bookkeeping
    df = df.with_columns(
        pl.when(pl.col(time_col) == pl.col(time_col).min().over(group_col))
        .then(pl.lit(0, dtype=pl.Int8))
        .when(pl.col(treatment_col) != pl.col(treatment_col).shift(1).over(group_col))
        .then(pl.lit(1, dtype=pl.Int8))
        .otherwise(pl.lit(0, dtype=pl.Int8))
        .alias("_changed")
    ).with_columns(
        pl.col("_changed").cum_sum().over(group_col).alias("_spell")
    ).with_columns(
        pl.when(pl.col("_spell") == 0)
        .then(pl.lit(0, dtype=pl.Int32))
        .otherwise(pl.int_range(pl.len()).over([group_col, "_spell"]))
        .alias("_psc")
    ).with_columns(
        (pl.col("_psc") == reset).cast(pl.Int8)
          .cum_sum().over(group_col).alias("_rc")
    )

    # 8. Save old group BEFORE the rename (this is the bug we fix vs the
    #    original notebook port).
    if cluster is None:
        df = df.with_columns(pl.col(group_col).alias("old_group_XX"))
        cluster = "old_group_XX"

    # 7 + 9. Replace group_col with the dense rank over (group, reset_count).
    df = df.with_columns(
        pl.struct([group_col, "_rc"]).rank("dense").alias(group_col)
    ).drop(["_changed", "_spell", "_psc", "_rc"])

    print(f"[reset={reset}] new groups: {df[group_col].n_unique():,}")
    return df, cluster


def generate_12month_subgroups(
    df: pl.DataFrame,
    time_col: str,
    group_col: str,
    cluster: str | None = None,
) -> tuple[pl.DataFrame, str]:
    """
    Splits each group into fixed 12-month buckets relative to that group's
    earliest observation. New group_col = dense_rank over (old group, bucket).

    Does NOT balance the panel first (per user instruction).
    """
    if cluster is None:
        df = df.with_columns(pl.col(group_col).alias("old_group_XX"))
        cluster = "old_group_XX"

    df = df.with_columns(
        ((pl.col(time_col) - pl.col(time_col).min().over(group_col)) // 12)
        .cast(pl.Int32).alias("_bucket")
    ).with_columns(
        pl.struct([group_col, "_bucket"]).rank("dense").alias(group_col)
    ).drop("_bucket")

    print(f"[12month] new groups: {df[group_col].n_unique():,}")
    return df, cluster


# ---- Model fit -------------------------------------------------------------

def _ensure_dirs(dirs):
    """mkdir each output dir; warn-and-skip any we cannot write to."""
    usable = []
    for d in dirs:
        try:
            Path(d).mkdir(parents=True, exist_ok=True)
            usable.append(Path(d))
        except OSError as e:
            print(f"[out] WARNING: cannot create {d}: {e}", file=sys.stderr)
    return usable


def fit_and_save(
    df: pl.DataFrame,
    treatment: str,
    with_actrend: bool,
    effects: int,
    placebo: int,
    cluster: str,
    out_basename: str,
    out_dirs,
    switchers: str | None = None,
) -> None:
    """
    Fit one DidMultiplegtDyn model and write summary CSV + event-study PNG to
    every directory in `out_dirs`. On ZeroDivisionError inside the package,
    log a warning and return -- the calling script keeps running.
    """
    DidMultiplegtDyn = _import_didmlt()

    kwargs = dict(
        df=df,
        outcome="countk",
        group="unique_small_grid_id",
        time="monthyear",
        treatment=treatment,
        effects=effects,
        placebo=placebo,
        controls=["av_wind_speed", "wind_direction"],
        cluster=cluster,
    )
    if with_actrend:
        kwargs["trends_nonparam"] = ["ac_uq_id"]
    if switchers:
        kwargs["switchers"] = switchers

    print(
        f"[fit] {out_basename}  rows={df.height:,}  "
        f"groups={df['unique_small_grid_id'].n_unique():,}  "
        f"effects={effects}  placebo={placebo}  with_actrend={with_actrend}"
        f"  switchers={switchers!r}"
    )

    model = DidMultiplegtDyn(**kwargs)
    try:
        model.fit()
    except ZeroDivisionError as e:
        print(
            f"[fit] WARNING: ZeroDivisionError in {out_basename}: {e}",
            file=sys.stderr,
        )
        traceback.print_exc()
        del model
        plt.close("all")
        gc.collect()
        return

    summary = model.summary()
    model.plot()

    usable_dirs = _ensure_dirs(out_dirs)
    for d in usable_dirs:
        csv_path = d / f"{out_basename}.csv"
        png_path = d / f"{out_basename}.png"
        summary.to_csv(str(csv_path), index=False)
        plt.savefig(str(png_path), dpi=300, bbox_inches="tight")
        print(f"[out] wrote {csv_path}")
        print(f"[out] wrote {png_path}")

    plt.close("all")
    del model, summary
    gc.collect()


# ---- Column pruning helper -------------------------------------------------

def prune_for_fit(df: pl.DataFrame, treatment: str, cluster: str) -> pl.DataFrame:
    """
    Keep only the columns DidMultiplegtDyn needs. Drops everything else so the
    model's internal copies are as small as possible.
    """
    keep = [
        "countk", "unique_small_grid_id", "monthyear",
        treatment, "ac_uq_id", "av_wind_speed", "wind_direction",
    ]
    if cluster not in keep:
        keep.append(cluster)
    # dedup, preserve order
    keep = list(dict.fromkeys(keep))
    return df.select(keep)
