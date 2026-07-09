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


def generate_12month_subgroups(
    df: pl.DataFrame,
    time_col: str,
    group_col: str,
) -> pl.DataFrame:
    """
    Splits each group into subgroups of 12-month windows.
    Assigns a new group ID = dense rank over (original group, 12-month bucket).

    Parameters
    ----------
    df        : input DataFrame
    time_col  : name of the time variable (numeric/integer periods)
    group_col : name of the group variable

    Returns
    -------
    DataFrame with group_col replaced by the new 12-month subgroup ID
    """
    return (
        df.with_columns(
            (
                (pl.col(time_col) - pl.col(time_col).min().over(group_col)) // 12
            )
            .cast(pl.Int32)
            .alias("_bucket")
        )
        .with_columns(
            pl.struct([group_col, "_bucket"])
            .rank("dense")
            .alias(group_col)
        )
        .drop("_bucket")
    )


df = generate_12month_subgroups(df, time_col="monthyear", group_col="unique_small_grid_id")


model1 = DidMultiplegtDyn(
    df = df,
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
model1.summary().to_csv('/groups/sgulzar/sa_fires/dCDH_reset12month_year_actrend.csv', index = False)
import matplotlib.pyplot as plt
model1.plot()
plt.savefig('/groups/sgulzar/sa_fires/dCDH_reset12month_year_actrend.png', dpi=300, bbox_inches='tight')

model1 = DidMultiplegtDyn(
    df = df,
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
model1.summary().to_csv('/groups/sgulzar/sa_fires/dCDH_reset12month_year.csv', index = False)
import matplotlib.pyplot as plt
model1.plot()
plt.savefig('/groups/sgulzar/sa_fires/dCDH_reset12month_year.png', dpi=300, bbox_inches='tight')