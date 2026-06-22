#!/usr/bin/env python
"""
Local sanity-test entry point for the dCDH pipeline.

Runs all 4 driver scripts on the SAMPLE dataset, each in its own subprocess so
memory is reset between them. Useful to verify the pipeline end-to-end on your
Mac before submitting any cluster job.

Usage (from this directory):
    python _test_local.py

The lib auto-detects ROOT: it tries the cluster path first, then the Mac
Dropbox path. SAMPLE defaults to "_sample" here so you don't have to set it.

Override anything with env vars if needed, e.g.:
    ROOT=/some/other/proj_bureaucrats_farms python _test_local.py
    DCDH_LOCAL_OUT=$HOME/Downloads/dCDH_out python _test_local.py

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

# Default to the sample so it stays fast even if user forgets to set it.
os.environ.setdefault("SAMPLE", "_sample")

SCRIPTS = [
    "dCDH_downup_ac_noreset.py",
    "dCDH_downup_ac_reset6.py",
    "dCDH_downup_ac_reset12.py",
    "dCDH_downup_ac_pop_noreset.py",
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
