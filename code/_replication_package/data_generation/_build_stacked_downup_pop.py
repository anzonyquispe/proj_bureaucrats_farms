#!/usr/bin/env python3
"""Build the population-based stacked downwind/upwind panel."""

import sys

from _build_stacked_downup import run


if __name__ == "__main__":
    sys.exit(
        run(
            default_treatment="downup_ac_pop",
            default_treatment_output_name="downup_ac_pop",
            default_output_stem="combined_dt_pop",
        )
    )
