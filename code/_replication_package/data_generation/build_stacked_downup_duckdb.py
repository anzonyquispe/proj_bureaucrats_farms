#!/usr/bin/env python3
"""Compatibility launcher for the standard ``downup_ac`` stack."""

from __future__ import annotations

import sys

from build_stacked_downup_13kmpl_duckdb import main


if __name__ == "__main__":
    raise SystemExit(main(["--spec", "downup_ac", *sys.argv[1:]]))
