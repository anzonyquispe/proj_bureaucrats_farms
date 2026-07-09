#!/usr/bin/env python3
"""
_compile_tweets_pdf.py

Discover the PNGs in tmp_figs/ produced by _tweets_replot_from_ster.do,
group them by suffix (`_all`, `_own`) and prefix (n1, n2, n3, tw, em, rh,
pos, neg, neu, mix, unc), write a sectioned LaTeX document, and compile
it to PDF with pdflatex.

Layout:
  Section per suffix: "All Tweets", "Own Tweets"
    Subsection per prefix (n1, n2, n3, tw, em, rh, pos, neg, neu, mix, unc)
      One figure per outcome (alphabetical).
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PNG_DIR = Path(
    "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/"
    "proj_bureaucrats_farms/tex/paper/figures/tmp_figs"
)
OUT_TEX = PNG_DIR / "tweets_event_studies.tex"
OUT_PDF = PNG_DIR / "tweets_event_studies.pdf"

PREFIX_ORDER = ["n1", "n2", "n3", "tw", "em", "rh", "pos", "neg", "neu", "mix", "unc"]
PREFIX_LABEL = {
    "n1":  "n1 -- primary topic count",
    "n2":  "n2 -- secondary topic count",
    "n3":  "n3 -- tertiary topic count",
    "tw":  "tw -- sum across topic positions",
    "em":  "em -- emotional valence",
    "rh":  "rh -- rhetorical mode",
    "pos": "pos -- positive valence x topic",
    "neg": "neg -- negative valence x topic",
    "neu": "neu -- neutral valence x topic",
    "mix": "mix -- mixed valence x topic",
    "unc": "unc -- unclear valence x topic",
}
SUFFIX_LABEL = {"all": "All Tweets", "own": "Own Tweets (excluding quote-tweets)"}

# <prefix>_<topic-words-with-underscores>_<suffix>
NAME_RE = re.compile(r"^([a-z0-9]+)_(.+)_(all|own)$")


def latex_escape(s: str) -> str:
    return (
        s.replace("\\", r"\textbackslash{}")
         .replace("_", r"\_")
         .replace("%", r"\%")
         .replace("&", r"\&")
         .replace("#", r"\#")
         .replace("$", r"\$")
    )


def main() -> int:
    pngs = sorted(PNG_DIR.glob("*.png"))
    if not pngs:
        print(f"No PNGs in {PNG_DIR}", file=sys.stderr)
        return 1

    grouped: dict[str, dict[str, list[Path]]] = {
        "all": defaultdict(list),
        "own": defaultdict(list),
    }
    skipped = []
    for p in pngs:
        m = NAME_RE.match(p.stem)
        if not m:
            skipped.append(p.name)
            continue
        prefix, _topic, suffix = m.groups()
        if prefix not in PREFIX_ORDER:
            skipped.append(p.name)
            continue
        grouped[suffix][prefix].append(p)

    print(f"Discovered {len(pngs)} PNGs in {PNG_DIR}")
    for suf in ("all", "own"):
        total = sum(len(v) for v in grouped[suf].values())
        print(f"  {suf}: {total} figures across {len(grouped[suf])} prefixes")
    if skipped:
        print(f"Skipped {len(skipped)} files that didn't match the naming "
              f"convention: {skipped[:5]}{'...' if len(skipped) > 5 else ''}")

    # ------------------------------------------------------------------ .tex
    lines: list[str] = [
        r"\documentclass[11pt]{article}",
        r"\usepackage[margin=1in]{geometry}",
        r"\usepackage{graphicx}",
        r"\usepackage{hyperref}",
        r"\usepackage{float}",
        r"\hypersetup{colorlinks=true, linkcolor=blue}",
        r"\title{Tweets Event Studies}",
        r"\author{}",
        r"\date{\today}",
        r"\begin{document}",
        r"\maketitle",
        r"\tableofcontents",
        r"\clearpage",
        r"",
    ]

    for suffix in ("all", "own"):
        if not grouped[suffix]:
            continue
        lines.append(rf"\section{{{SUFFIX_LABEL[suffix]}}}")
        lines.append("")
        for prefix in PREFIX_ORDER:
            files = grouped[suffix].get(prefix, [])
            if not files:
                continue
            lines.append(rf"\subsection{{{latex_escape(PREFIX_LABEL[prefix])}}}")
            lines.append("")
            for f in sorted(files):
                lines.append(r"\begin{figure}[H]")
                lines.append(r"  \centering")
                lines.append(rf"  \includegraphics[width=0.8\textwidth]{{{f.name}}}")
                lines.append(rf"  \caption{{{latex_escape(f.stem)}}}")
                lines.append(r"\end{figure}")
                lines.append("")
            lines.append(r"\clearpage")
            lines.append("")
        lines.append("")

    lines.append(r"\end{document}")

    OUT_TEX.write_text("\n".join(lines))
    print(f"wrote {OUT_TEX}")

    # ----------------------------------------------------------------- pdf
    # Wipe stale auxiliary files from prior runs so pdflatex starts clean.
    for ext in (".aux", ".log", ".toc", ".out"):
        aux = OUT_TEX.with_suffix(ext)
        if aux.exists():
            aux.unlink()

    print("compiling with pdflatex (twice for TOC)...")
    pdflatex = "/Library/TeX/texbin/pdflatex"
    cmd = [
        pdflatex,
        "-interaction=nonstopmode",
        "-halt-on-error",
        "-output-directory", str(OUT_TEX.parent),
        str(OUT_TEX),
    ]
    try:
        for _ in range(2):
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0:
                print("pdflatex failed:")
                print(r.stdout[-2000:])
                print(r.stderr[-1000:])
                return 1
    except FileNotFoundError:
        print(f"pdflatex not found at {pdflatex}. Install MacTeX or compile manually:")
        print(f"  cd '{OUT_TEX.parent}' && pdflatex {OUT_TEX.name}")
        return 1

    # Clean up aux files
    for ext in (".aux", ".log", ".toc", ".out"):
        aux = OUT_TEX.with_suffix(ext)
        if aux.exists():
            aux.unlink()

    print(f"wrote {OUT_PDF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
