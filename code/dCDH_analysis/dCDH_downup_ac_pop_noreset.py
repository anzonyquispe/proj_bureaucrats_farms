#!/usr/bin/env python
"""
dCDH event-study run.

Treatment      : downup_ac_pop
Reset rule     : NONE (no apply_reset, no 12-month bucketing -- raw panel,
                 each grid is its own group)
Effects/placebo: 6 / 6
Model variants : 1) no trends, 2) trends_nonparam = ['ac_uq_id']
"""

import gc
import os

from _dCDH_lib import (
    load_panel, prune_for_fit, fit_and_save, OUT_DIRS,
)

TREATMENT = "downup_ac_pop"
GROUP_COL = "unique_small_grid_id"
TIME_COL  = "monthyear"
EFFECTS   = 6
PLACEBO   = 6
CLUSTER   = "ac_uq_id"
TAG       = "dCDH_downup_ac_pop_noreset"

VARIANT = os.environ.get("VARIANT", "").lower()
print(f"[driver] VARIANT = {VARIANT!r}")

df = load_panel(treatment=TREATMENT)
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
