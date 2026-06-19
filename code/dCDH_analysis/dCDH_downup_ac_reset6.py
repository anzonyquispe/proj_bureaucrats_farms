#!/usr/bin/env python
"""
dCDH event-study run.

Treatment      : downup_ac
Reset rule     : adjacent-spell reset every 6 periods (apply_reset, reset=6)
Effects/placebo: 6 / 6
Model variants : 1) no trends, 2) trends_nonparam = ['ac_uq_id']
"""

import gc
import os

from _dCDH_lib import (
    load_panel, apply_reset, prune_for_fit, fit_and_save, OUT_DIRS,
)

TREATMENT = "downup_ac"
GROUP_COL = "unique_small_grid_id"
TIME_COL  = "monthyear"
EFFECTS   = 6
PLACEBO   = 6
RESET     = 6
CLUSTER   = "ac_uq_id"
TAG       = "dCDH_downup_ac_reset6"

# VARIANT controls which model variant(s) to fit:
#   ""        -> run both (notrend, then actrend)   <- _test_local.py default
#   "notrend" -> run only the no-trend fit
#   "actrend" -> run only the ac-trend fit
VARIANT = os.environ.get("VARIANT", "").lower()
print(f"[driver] VARIANT = {VARIANT!r}")

df = load_panel(treatment=TREATMENT)
df, _ = apply_reset(
    df, reset=RESET, group_col=GROUP_COL,
    treatment_col=TREATMENT, time_col=TIME_COL,
    cluster=CLUSTER,
)
df = prune_for_fit(df, treatment=TREATMENT, cluster=CLUSTER)
gc.collect()

if VARIANT in ("", "notrend"):
    fit_and_save(
        df, treatment=TREATMENT, with_actrend=False,
        effects=EFFECTS, placebo=PLACEBO, cluster=CLUSTER,
        out_basename=f"{TAG}_notrend", out_dirs=OUT_DIRS,
    )
if VARIANT in ("", "actrend"):
    fit_and_save(
        df, treatment=TREATMENT, with_actrend=True,
        effects=EFFECTS, placebo=PLACEBO, cluster=CLUSTER,
        out_basename=f"{TAG}_actrend", out_dirs=OUT_DIRS,
    )
