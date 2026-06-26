#!/usr/bin/env python
"""
Local sanity-test for the dCDH pipeline with SWITCHERS variants.

Runs all 6 driver scripts twice each — once with SWITCHERS=in and once with
SWITCHERS=out — on the SAMPLE dataset, each in its own subprocess so memory
is reset between runs. Use this to verify the full switchers matrix end-to-end
on your Mac before submitting any cluster job.

Usage (from this directory):
    python _test_local_switchers.py

SAMPLE defaults to "_sample". VARIANT is left unset so each script exercises
both notrend and actrend.

Logs are written to  _test_switchers_logs/<script_stem>_<switchers>.log
A summary is printed at the end.
"""

import os
import subprocess
import sys
from pathlib import Path

HERE   = Path(__file__).resolve().parent
PYTHON = os.environ.get("PYTHON", sys.executable)

os.environ.setdefault("SAMPLE", "_sample")

LOG_DIR = HERE / "_test_switchers_logs"
LOG_DIR.mkdir(exist_ok=True)

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
results  = []

for switchers in SWITCHERS_VALUES:
    for s in SCRIPTS:
        stem     = Path(s).stem
        log_path = LOG_DIR / f"{stem}_{switchers}.log"
        env      = {**os.environ, "SWITCHERS": switchers}

        print("=" * 72)
        print(f"RUNNING {s}  (SAMPLE={os.environ['SAMPLE']}, SWITCHERS={switchers})")
        print(f"  log → {log_path}")
        print("=" * 72)

        with open(log_path, "w") as fh:
            proc = subprocess.run(
                [PYTHON, str(HERE / s)],
                cwd=str(HERE),
                env=env,
                stdout=fh,
                stderr=subprocess.STDOUT,
            )

        rc = proc.returncode
        status = "OK" if rc == 0 else f"FAILED (exit {rc})"
        results.append((s, switchers, rc, log_path))
        if rc != 0:
            failures.append((s, switchers, rc, log_path))
        print(f"  → {status}\n")

# ---- Summary -----------------------------------------------------------------
print("=" * 72)
print("SUMMARY")
print("=" * 72)
for s, sw, rc, log_path in results:
    tag = "OK  " if rc == 0 else "FAIL"
    print(f"  [{tag}] {s}  SWITCHERS={sw}  (log: {log_path.name})")

print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for s, sw, rc, log_path in failures:
        print(f"  {s}  SWITCHERS={sw}  exit={rc}")
        print(f"  last 20 lines of log:")
        try:
            lines = log_path.read_text().splitlines()
            for line in lines[-20:]:
                print(f"    {line}")
        except Exception:
            pass
        print()
    sys.exit(1)

print(f"All {len(SCRIPTS) * len(SWITCHERS_VALUES)} runs completed successfully.")
print(f"Logs in: {LOG_DIR}")
