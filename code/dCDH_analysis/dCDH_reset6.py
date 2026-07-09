import pandas as pd
import polars as pl
from did_multiplegt_dyn import DidMultiplegtDyn
root = '/groups/sgulzar/sa_fires/proj_bureaucrats_farms'

df = pl.read_csv(
    f'{root}/data_output/intermediate/0_master_merge_data_gen.csv',
    columns=[
        "count",
        "unique_small_grid_id",
        "monthyear",
        "year", "month",
        "downup_ac",
        "ac_uq_id",
        "av_wind_speed",
        "wind_direction",
        'province'
    ],
    ignore_errors=True,
)


ghs = pl.from_pandas(
    pd.read_stata(f'{root}/data_output/intermediate/ghs_grid_classification_2000.dta')
).select(['unique_small_grid_id', 'is_rural'])   # keepusing(is_rural)

df = df.join(ghs, on='unique_small_grid_id', how='inner')   # _merge == 3, drop _merge

# --- keep if is_rural == 1
df = df.filter(pl.col('is_rural') == 1)

# --- merge m:1 unique_small_grid_id using grids_with_more_1_ac.dta
#     drop if dpl_ac == 1    (then drop _merge)
grids = pl.from_pandas(
    pd.read_stata(f'{root}/data_output/intermediate/grids_with_more_1_ac.dta')
)

df = df.join(grids, on='unique_small_grid_id', how='left')   # keeps all master rows
df = df.filter((pl.col('dpl_ac') != 1) | pl.col('dpl_ac').is_null())   # drop if dpl_ac == 1

# --- keep if year < 2022 | (year == 2022 & month <= 8)
df = df.filter(
    (pl.col('year') < 2022) | ((pl.col('year') == 2022) & (pl.col('month') <= 8))
)

def apply_reset(
    lf: pl.LazyFrame,
    reset: int,
    group_col: str,
    treatment_col: str,
    time_col: str,
    cluster: str | None = None,
) -> tuple[pl.LazyFrame, str | None]:
    if reset == 0:
        return lf, cluster

    # -------------------------------------------------------
    # 1. Balance panel in one pass, no intermediate columns
    # -------------------------------------------------------
    lf = (
        lf.with_columns(
            pl.col(treatment_col).is_not_null()
            .cast(pl.Int8)
            .sum()
            .over(group_col)
            .alias("_count")
        )
        .filter(pl.col("_count") == pl.col("_count").max())
        .drop("_count")
        .sort([group_col, time_col])
    )

    # -------------------------------------------------------
    # 2-4. Intermediate columns
    # -------------------------------------------------------
    lf = lf.with_columns(
        pl.when(
            pl.col(time_col) == pl.col(time_col).min().over(group_col)
        )
        .then(pl.lit(0, dtype=pl.Int8))
        .when(
            pl.col(treatment_col) != pl.col(treatment_col).shift(1).over(group_col)
        )
        .then(pl.lit(1, dtype=pl.Int8))
        .otherwise(pl.lit(0, dtype=pl.Int8))
        .alias("_changed"),
    ).with_columns(
        pl.col("_changed").cum_sum().over(group_col).alias("_spell"),
    ).with_columns(
        pl.when(pl.col("_spell") == 0)
        .then(pl.lit(0, dtype=pl.Int32))
        .otherwise(
            pl.int_range(pl.len()).over([group_col, "_spell"])
        )
        .alias("_psc"),
    ).with_columns(
        (pl.col("_psc") == reset)
        .cast(pl.Int8)
        .cum_sum()
        .over(group_col)
        .alias("_rc"),
    )

    # -------------------------------------------------------
    # 5. New group: dense rank over (group, reset_count)
    # -------------------------------------------------------
    lf = lf.with_columns(
        pl.struct([group_col, "_rc"])
        .rank("dense")
        .alias(group_col)
    ).drop(["_changed", "_spell", "_psc", "_rc"])

    # -------------------------------------------------------
    # 6. Clustering default
    # -------------------------------------------------------
    if cluster is None:
        lf = lf.with_columns(
            pl.col(group_col).alias("old_group_XX")
        )
        cluster = "old_group_XX"

    return lf, cluster


lf, cluster = apply_reset(df.lazy(), 
                          reset=6, 
                          group_col = 'unique_small_grid_id',
                          treatment_col = 'downup_ac',
                          time_col = 'monthyear')

df_result = lf.collect()

model1 = DidMultiplegtDyn(
    df = df_result,
    outcome = "count",
    group = "unique_small_grid_id",
    time = "monthyear",
    treatment = "downup_ac",
    effects = 6,
    placebo = 6,
    controls = ["av_wind_speed",
        "wind_direction"],
    cluster = "ac_uq_id"
)
model1.fit()
model1.summary().to_csv('/groups/sgulzar/sa_fires/dCDH_reset6_year.csv', index = False)
import matplotlib.pyplot as plt
model1.plot()
plt.savefig('/groups/sgulzar/sa_fires/dCDH_reset6_year.png', dpi=300, bbox_inches='tight')



model1 = DidMultiplegtDyn(
    df = df_result,
    outcome = "count",
    group = "unique_small_grid_id",
    time = "monthyear",
    treatment = "downup_ac",
    effects = 6,
    placebo = 6,
    controls = ["av_wind_speed",
        "wind_direction"],
    cluster = "ac_uq_id",
    trends_nonparam = ['ac_uq_id']
)
model1.fit()
model1.summary().to_csv('/groups/sgulzar/sa_fires/dCDH_reset6_year_actrend.csv', index = False)
import matplotlib.pyplot as plt
model1.plot()
plt.savefig('/groups/sgulzar/sa_fires/dCDH_reset6_year_actrend.png', dpi=300, bbox_inches='tight')