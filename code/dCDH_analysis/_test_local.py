#!/usr/bin/env python
"""
Local sanity-test entry point for the dCDH pipeline.

Runs all 4 driver scripts on the SAMPLE dataset, each in its own subprocess so
memory is reset between them. Useful to verify the pipeline end-to-end before
submitting any cluster job.

Usage (from this directory):
    SAMPLE=_sample python _test_local.py
or
    ROOT=/path/to/local/proj_bureaucrats_farms SAMPLE=_sample \
    DCDH_LOCAL_OUT=/tmp/dCDH_local_out \
    python _test_local.py

Outputs land in:
    ${ROOT}/data_output/intermediate/dCDH/
    ${DCDH_LOCAL_OUT}  (default: /users/aquisper/proj_bureaucrats_farms/code/dCDH_analysis)
"""

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PYTHON = os.environ.get("PYTHON", sys.executable)

# Default to the sample so it stays fast even if user forgets to set it.
os.environ.setdefault("SAMPLE", "_sample")

SCRIPTS = [
    "dCDH_downup_ac_reset6.py",
    "dCDH_downup_ac_reset12.py",
    "dCDH_downup_ac_pop_reset6.py",
    "dCDH_downup_ac_pop_reset12.py",
]

failures = []
for s in SCRIPTS:
    print("=" * 72)
    print(f"RUNNING {s}  (SAMPLE={os.environ['SAMPLE']})")
    print("=" * 72)
    rc = subprocess.call([PYTHON, str(HERE / s)], cwd=str(HERE))
    if rc != 0:
        failures.append((s, rc))

print()
if failures:
    print("FAILURES:")
    for s, rc in failures:
        print(f"  {s}  exit={rc}")
    sys.exit(1)
print("All 4 driver scripts completed.")
