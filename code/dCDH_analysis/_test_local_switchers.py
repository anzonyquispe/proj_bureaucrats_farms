#!/usr/bin/env python
"""
Local sanity-test for the dCDH pipeline with SWITCHERS variants.

Runs all 6 driver scripts twice each — once with SWITCHERS=in and once with
SWITCHERS=out — on the SAMPLE dataset, each in its own subprocess so memory
is reset between runs. Use this to verify the full switchers matrix end-to-end
on your Mac before submitting any cluster job.

Usage (from this directory):
    python _test_local_switchers.py

SAMPLE defaults to "_sample" so you don't have to set it. VARIANT is left
unset (empty string) so each script exercises its own default behaviour.

Override anything with env vars if needed, e.g.:
    ROOT=/some/other/proj_bureaucrats_farms python _test_local_switchers.py
    SAMPLE="" python _test_local_switchers.py

Outputs land in:
    ${ROOT}/data_output/intermediate/dCDH/
    ${DCDH_LOCAL_OUT}                   (defaults to cluster home path,
                                         silently skipped on a Mac)
"""

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PYTHON = os.environ.get("PYTHON", sys.executable)

# Default to the sample so runs stay fast.
os.environ.setdefault("SAMPLE", "_sample")

SCRIPTS = [
    "dCDH_downup_ac_noreset.py",
    "dCDH_downup_ac_reset6.py",
    "dCDH_downup_ac_reset12.py",
    "dCDH_downup_ac_pop_noreset.py",
    "dCDH_downup_ac_pop_reset6.py",
    "dCDH_downup_ac_pop_reset12.py",
]

SWITCHERS_VALUES = ["in", "out"]

failures = []
for switchers in SWITCHERS_VALUES:
    for s in SCRIPTS:
        print("=" * 72)
        print(
            f"RUNNING {s}  "
            f"(SAMPLE={os.environ['SAMPLE']}, SWITCHERS={switchers})"
        )
        print("=" * 72)
        env = {**os.environ, "SWITCHERS": switchers}
        rc = subprocess.call([PYTHON, str(HERE / s)], cwd=str(HERE), env=env)
        if rc != 0:
            failures.append((s, switchers, rc))

print()
if failures:
    print("FAILURES:")
    for s, sw, rc in failures:
        print(f"  {s}  SWITCHERS={sw}  exit={rc}")
    sys.exit(1)
print(f"All {len(SCRIPTS) * len(SWITCHERS_VALUES)} runs completed successfully.")
