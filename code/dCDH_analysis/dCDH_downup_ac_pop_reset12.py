#!/usr/bin/env python
"""
dCDH event-study run.

Treatment      : downup_ac_pop
Reset rule     : fixed calendar 12-month buckets per grid
                 (generate_12month_subgroups, NO panel balancing per request)
Effects/placebo: 6 / 5
Model variants : 1) no trends, 2) trends_nonparam = ['ac_uq_id']
"""

import gc

from _dCDH_lib import (
    load_panel, generate_12month_subgroups, prune_for_fit, fit_and_save, OUT_DIRS,
)

TREATMENT = "downup_ac_pop"
GROUP_COL = "unique_small_grid_id"
TIME_COL  = "monthyear"
EFFECTS   = 6
PLACEBO   = 5
CLUSTER   = "ac_uq_id"
TAG       = "dCDH_downup_ac_pop_reset12"

df = load_panel(treatment=TREATMENT)
df, _ = generate_12month_subgroups(
    df, time_col=TIME_COL, group_col=GROUP_COL, cluster=CLUSTER,
)
df = prune_for_fit(df, treatment=TREATMENT, cluster=CLUSTER)
gc.collect()

fit_and_save(
    df, treatment=TREATMENT, with_actrend=False,
    effects=EFFECTS, placebo=PLACEBO, cluster=CLUSTER,
    out_basename=f"{TAG}_notrend", out_dirs=OUT_DIRS,
)
fit_and_save(
    df, treatment=TREATMENT, with_actrend=True,
    effects=EFFECTS, placebo=PLACEBO, cluster=CLUSTER,
    out_basename=f"{TAG}_actrend", out_dirs=OUT_DIRS,
)
