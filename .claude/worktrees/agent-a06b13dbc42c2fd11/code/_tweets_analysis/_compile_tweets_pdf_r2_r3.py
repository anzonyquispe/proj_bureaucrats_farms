#!/usr/bin/env python3
"""
_compile_tweets_pdf_r2_r3.py

Discover r2_*.png and r3_*.png files in ${shell}/tex/paper/figures/ produced by
_tweets_replot_r2_r3.do. For each outcome, the dofile saves TWO plots:

    <stem>.png            original event-study estimates
    <stem>_rotated.png    same outcome with linear pre-trend (fit on x<0
                           via OLS no-constant) extrapolated and subtracted

The compiler emits one LaTeX `figure` per outcome containing two subfigures
(Original on top, Rotated on bottom) plus a descriptive caption explaining
the field, the specific value, and the suffix universe.

Sections:
    1.  Rubric 2 -- All Tweets
    2.  Rubric 2 -- Own Tweets
    3.  Rubric 3 -- All Tweets
    4.  Rubric 3 -- Own Tweets

Output: ${shell}/tex/paper/figures/tweets_event_studies_r2_r3.pdf
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PNG_DIR = Path(
    "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/"
    "proj_bureaucrats_farms/tex/paper/figures"
)
OUT_TEX = PNG_DIR / "tweets_event_studies_r2_r3.tex"
OUT_PDF = PNG_DIR / "tweets_event_studies_r2_r3.pdf"


# ---------------------------------------------------------------------------
# Prefix order and field labels (subsection titles)
# ---------------------------------------------------------------------------
R2_PREFIXES = ["ar", "ff", "sf", "pr", "sl", "wp", "cc", "ba"]
R3_PREFIXES = ["cr", "pt", "bs", "sb", "pi", "pa", "ps", "cc", "ba"]

R2_FIELD = {
    "ar":  "ar -- agriculture_relevance (0--3)",
    "ff":  "ff -- farmer_framing",
    "sf":  "sf -- stance_farmers",
    "pr":  "pr -- farmer_protest_relevance (0--3)",
    "sl":  "sl -- stance_farm_laws",
    "wp":  "wp -- farmer_welfare_policy",
    "cc":  "cc -- credit_claiming (true/false)",
    "ba":  "ba -- blame_attribution",
}
R3_FIELD = {
    "cr":  "cr -- crop_burning_relevance (0--3)",
    "pt":  "pt -- pollution_type",
    "bs":  "bs -- burning_season_context (Oct/Nov flag)",
    "sb":  "sb -- stance_crop_burning",
    "pi":  "pi -- policy_instrument_mentioned",
    "pa":  "pa -- policy_action_type",
    "ps":  "ps -- policy_stage",
    "cc":  "cc -- credit_claiming (true/false)",
    "ba":  "ba -- blame_attribution",
}

SECTION_LABEL = {
    ("r2", "all"): "Rubric 2 (agriculture \\& farmers) -- All Tweets",
    ("r2", "own"): "Rubric 2 (agriculture \\& farmers) -- Own Tweets (excl. quote-tweets)",
    ("r3", "all"): "Rubric 3 (crop burning \\& policy) -- All Tweets",
    ("r3", "own"): "Rubric 3 (crop burning \\& policy) -- Own Tweets (excl. quote-tweets)",
}


# ---------------------------------------------------------------------------
# Value-level descriptions (used in figure captions). Concise but informative.
# Keys are (prefix, value).
# ---------------------------------------------------------------------------
R2_VALUE_DESC = {
    ("ar", "0"): "agriculture_relevance = 0: not relevant to agriculture",
    ("ar", "1"): "agriculture_relevance = 1: tangentially relevant (rural development / food prices / passing reference)",
    ("ar", "2"): "agriculture_relevance = 2: moderately relevant (ag-policy / farm income / farmer welfare as a component)",
    ("ar", "3"): "agriculture_relevance = 3: directly about agriculture, crop burning, farm laws, or farmer livelihoods",
    ("ff", "provider_hero"):     "farmer_framing = provider_hero: farmers as the nation's backbone, food providers, annadata",
    ("ff", "victim"):            "farmer_framing = victim: farmers as victims of policy failure, economic hardship, exploitation",
    ("ff", "protester_activist"):"farmer_framing = protester_activist: farmers as political actors, demanding rights, mobilizing",
    ("ff", "beneficiary"):       "farmer_framing = beneficiary: farmers as recipients of government programs / subsidies",
    ("ff", "problem_causer"):    "farmer_framing = problem_causer: farmers as a cause of pollution / non-compliance",
    ("ff", "neutral_reference"): "farmer_framing = neutral_reference: farmers mentioned without clear positive or negative framing",
    ("ff", "rhetorical"):        "farmer_framing = rhetorical: rhetorical mention",
    ("sf", "pro_farmer"):     "stance_farmers = pro_farmer: supportive of farmer interests, demands, welfare",
    ("sf", "anti_farmer"):    "stance_farmers = anti_farmer: critical of farmer demands or actions",
    ("sf", "neutral"):        "stance_farmers = neutral",
    ("sf", "not_applicable"): "stance_farmers = not_applicable",
    ("pr", "0"): "farmer_protest_relevance = 0: not relevant to the 2020--21 farmer protests",
    ("pr", "1"): "farmer_protest_relevance = 1: mentions protests / mobilization in a general context",
    ("pr", "2"): "farmer_protest_relevance = 2: farm laws / agricultural reform / farmer grievances in protest-era context",
    ("pr", "3"): "farmer_protest_relevance = 3: explicitly about the 2020--21 farmer protests, three farm laws, Singhu/Tikri/Ghazipur, repeal",
    ("sl", "pro_laws"):       "stance_farm_laws = pro_laws: supports the three farm laws",
    ("sl", "anti_laws"):      "stance_farm_laws = anti_laws: opposes the farm laws / supports repeal",
    ("sl", "neutral"):        "stance_farm_laws = neutral",
    ("sl", "not_applicable"): "stance_farm_laws = not_applicable",
    ("wp", "pm_kisan"):              "farmer_welfare_policy = pm_kisan: PM-Kisan direct income transfer",
    ("wp", "crop_insurance"):        "farmer_welfare_policy = crop_insurance: PM Fasal Bima Yojana / crop insurance",
    ("wp", "machinery_distribution"):"farmer_welfare_policy = machinery_distribution: Happy Seeders, balers, etc.",
    ("wp", "msp_procurement"):       "farmer_welfare_policy = msp_procurement: MSP / mandi procurement",
    ("wp", "debt_relief"):           "farmer_welfare_policy = debt_relief: farm loan waivers, debt restructuring",
    ("wp", "irrigation_scheme"):     "farmer_welfare_policy = irrigation_scheme: PM Krishi Sinchayee Yojana, irrigation projects",
    ("wp", "soil_health"):           "farmer_welfare_policy = soil_health: soil-health cards, soil testing",
    ("wp", "organic_farming"):       "farmer_welfare_policy = organic_farming: organic / zero-budget natural farming",
    ("wp", "other_farm_policy"):     "farmer_welfare_policy = other_farm_policy",
    ("wp", "none"):                  "farmer_welfare_policy = none: no specific policy mentioned",
    ("cc", "true"):  "credit_claiming = true: politician takes credit for an agri-policy / farmer-welfare outcome",
    ("cc", "false"): "credit_claiming = false: no credit-claiming",
    ("ba", "central_govt"): "blame_attribution = central_govt",
    ("ba", "state_govt"):   "blame_attribution = state_govt",
    ("ba", "opposition"):   "blame_attribution = opposition",
    ("ba", "middlemen"):    "blame_attribution = middlemen / intermediaries / market manipulation",
    ("ba", "bureaucracy"):  "blame_attribution = bureaucracy",
    ("ba", "other"):        "blame_attribution = other",
    ("ba", "none"):         "blame_attribution = none",
}

R3_VALUE_DESC = {
    ("cr", "0"): "crop_burning_relevance = 0: no relevance to crop burning or pollution",
    ("cr", "1"): "crop_burning_relevance = 1: mentions air pollution / smog without specifying crop burning",
    ("cr", "2"): "crop_burning_relevance = 2: pollution policy in a context likely linked to ag burning",
    ("cr", "3"): "crop_burning_relevance = 3: explicit stubble/parali, Happy Seeder, CAQM, burning fines, etc.",
    ("pt", "crop_burning_smoke"):    "pollution_type = crop_burning_smoke: pollution explicitly linked to stubble burning",
    ("pt", "general_air_pollution"): "pollution_type = general_air_pollution: smog/AQI without specifying source",
    ("pt", "industrial_pollution"):  "pollution_type = industrial_pollution: factory / vehicular emissions",
    ("pt", "water_pollution"):       "pollution_type = water_pollution",
    ("pt", "other_environmental"):   "pollution_type = other_environmental: deforestation, waste, etc.",
    ("bs", "true"):  "burning_season_context = true: tweet posted Oct--Nov (burning-season months)",
    ("bs", "false"): "burning_season_context = false: tweet posted outside Oct--Nov",
    ("sb", "pro_enforcement"):  "stance_crop_burning = pro_enforcement: supports anti-burning enforcement / alternatives",
    ("sb", "anti_enforcement"): "stance_crop_burning = anti_enforcement: opposes fines, frames enforcement as anti-farmer",
    ("sb", "permissive"):       "stance_crop_burning = permissive: sympathetic to burning, emphasizes farmer hardship",
    ("sb", "neutral"):          "stance_crop_burning = neutral: mentions burning without clear stance",
    ("sb", "not_applicable"):   "stance_crop_burning = not_applicable",
    ("pi", "happy_seeder"):         "policy_instrument = happy_seeder: machine that sows wheat into rice stubble without burning",
    ("pi", "super_sms"):            "policy_instrument = super_sms: Straw Management System attachment for combine harvesters",
    ("pi", "baler"):                "policy_instrument = baler: straw baler / baling machine",
    ("pi", "chc"):                  "policy_instrument = chc: Custom Hiring Centre (machinery rental for farmers)",
    ("pi", "bio_decomposer"):       "policy_instrument = bio_decomposer: Pusa bio-decomposer (stubble-decomposition spray)",
    ("pi", "biomass_plant"):        "policy_instrument = biomass_plant: industrial biomass / bioethanol plant",
    ("pi", "straw_market"):         "policy_instrument = straw_market: collection centres / markets for crop residue",
    ("pi", "satellite_monitoring"): "policy_instrument = satellite_monitoring: remote sensing / fire-hotspot monitoring",
    ("pi", "fines_penalties"):      "policy_instrument = fines_penalties: fines, FIRs, penal action for burning",
    ("pi", "caqm"):                 "policy_instrument = caqm: Commission for Air Quality Management actions/orders",
    ("pi", "compensation_payment"): "policy_instrument = compensation_payment: direct payments for not burning",
    ("pi", "awareness_campaign"):   "policy_instrument = awareness_campaign: farmer outreach, training, demonstrations",
    ("pi", "machinery_subsidy"):    "policy_instrument = machinery_subsidy: general machinery distribution / CRM subsidy",
    ("pi", "other_instrument"):     "policy_instrument = other_instrument",
    ("pa", "subsidy_scheme"):      "policy_action_type = subsidy_scheme",
    ("pa", "enforcement_penalty"): "policy_action_type = enforcement_penalty",
    ("pa", "infrastructure"):      "policy_action_type = infrastructure",
    ("pa", "regulation"):          "policy_action_type = regulation",
    ("pa", "awareness_campaign"):  "policy_action_type = awareness_campaign",
    ("pa", "compensation"):        "policy_action_type = compensation",
    ("pa", "other_policy"):        "policy_action_type = other_policy",
    ("ps", "announcement"):   "policy_stage = announcement",
    ("ps", "implementation"): "policy_stage = implementation",
    ("ps", "evaluation"):     "policy_stage = evaluation",
    ("ps", "criticism"):      "policy_stage = criticism",
    ("ps", "demand"):         "policy_stage = demand",
    ("cc", "true"):  "credit_claiming = true: politician takes credit for crop-burning / pollution policy",
    ("cc", "false"): "credit_claiming = false: no credit-claiming",
    ("ba", "central_govt"): "blame_attribution = central_govt",
    ("ba", "state_govt"):   "blame_attribution = state_govt",
    ("ba", "opposition"):   "blame_attribution = opposition",
    ("ba", "farmers"):      "blame_attribution = farmers (blames farmers for burning despite alternatives)",
    ("ba", "bureaucracy"):  "blame_attribution = bureaucracy",
    ("ba", "delhi_govt"):   "blame_attribution = delhi_govt",
    ("ba", "other"):        "blame_attribution = other",
}

SUFFIX_DESC = {
    "all": "all classified tweets (including quote-tweets)",
    "own": "own tweets only (is_quoted == False)",
}


# ---------------------------------------------------------------------------
def latex_escape(s: str) -> str:
    return (
        s.replace("\\", r"\textbackslash{}")
         .replace("_", r"\_")
         .replace("%", r"\%")
         .replace("&", r"\&")
         .replace("#", r"\#")
         .replace("$", r"\$")
    )


def parse_name(stem: str):
    """Parse 'r2_ar3_all' -> ('r2', 'all', 'ar', '3'). Numeric prefixes
    (ar/pr in r2, cr in r3) glue the value directly with no separator."""
    if stem.startswith("r2_"):
        rubric, prefixes, rest = "r2", R2_PREFIXES, stem[3:]
    elif stem.startswith("r3_"):
        rubric, prefixes, rest = "r3", R3_PREFIXES, stem[3:]
    else:
        return None

    if rest.endswith("_all"):
        suffix, body = "all", rest[:-4]
    elif rest.endswith("_own"):
        suffix, body = "own", rest[:-4]
    else:
        return None

    for pre in sorted(prefixes, key=len, reverse=True):
        if body == pre or body.startswith(pre + "_") or (
            body.startswith(pre) and len(body) > len(pre) and body[len(pre)].isdigit()
        ):
            value = body[len(pre):].lstrip("_")
            return rubric, suffix, pre, value
    return None


def caption_for(rubric: str, suffix: str, prefix: str, value: str, stem: str) -> str:
    """Build a descriptive LaTeX caption for an outcome's figure block."""
    desc_table = R2_VALUE_DESC if rubric == "r2" else R3_VALUE_DESC
    desc = desc_table.get((prefix, value), f"{prefix}={value}")
    suf_desc = SUFFIX_DESC[suffix]
    # Use texttt for the variable name; bold the field label.
    return (
        rf"\texttt{{{latex_escape(stem)}}} -- {latex_escape(desc)}. "
        rf"Count over {latex_escape(suf_desc)}. "
        r"\textit{did\_multiplegt\_dyn} event study, 5 placebos / 5 effects, "
        r"omitted reference at $t=0$, 95\% CIs (rcap bars), "
        r"SEs clustered at the state level."
    )


# ---------------------------------------------------------------------------
def main() -> int:
    # Only consider non-rotated PNGs as the "main" outcomes; the rotated
    # counterparts are matched via filename.
    all_pngs = sorted(PNG_DIR.glob("r[23]_*.png"))
    main_pngs = [p for p in all_pngs if not p.stem.endswith("_rotated")]
    rotated_set = {p.stem for p in all_pngs if p.stem.endswith("_rotated")}

    grouped: dict[tuple[str, str], dict[str, list[Path]]] = {
        ("r2", "all"): defaultdict(list),
        ("r2", "own"): defaultdict(list),
        ("r3", "all"): defaultdict(list),
        ("r3", "own"): defaultdict(list),
    }
    skipped = []
    for p in main_pngs:
        parsed = parse_name(p.stem)
        if parsed is None:
            skipped.append(p.name); continue
        rubric, suffix, pre, _value = parsed
        grouped[(rubric, suffix)][pre].append(p)

    total_main = sum(sum(len(v) for v in g.values()) for g in grouped.values())
    n_with_rot = sum(1 for p in main_pngs if f"{p.stem}_rotated" in rotated_set)
    print(f"Discovered {len(main_pngs)} main r[23]_*.png + "
          f"{len(rotated_set)} rotated variants ({n_with_rot} pair up).")
    for (r, s), g in grouped.items():
        n = sum(len(v) for v in g.values())
        print(f"  {r}/{s}: {n} outcomes across {len(g)} prefixes")
    if skipped:
        print(f"  skipped {len(skipped)} unparseable: {skipped[:5]}")

    # ------------------------------------------------------------------ .tex
    lines: list[str] = [
        r"\documentclass[11pt]{article}",
        r"\usepackage[margin=1in]{geometry}",
        r"\usepackage{graphicx}",
        r"\usepackage{subcaption}",
        r"\usepackage{hyperref}",
        r"\usepackage{float}",
        r"\hypersetup{colorlinks=true, linkcolor=blue}",
        r"\title{Tweets Event Studies --- Rubrics 2 \& 3 \\",
        r"\large Original and pre-trend--rotated estimates}",
        r"\author{}",
        r"\date{\today}",
        r"\begin{document}",
        r"\maketitle",
        r"",
        r"\section*{Notes}",
        r"Each figure shows two panels for the same outcome:",
        r"\begin{itemize}",
        r"  \item \textbf{Original} (navy): the raw \texttt{did\_multiplegt\_dyn}",
        r"        event-study estimates with 95\% CIs.",
        r"  \item \textbf{Rotated} (maroon): the same estimates with a linear",
        r"        pre-trend removed. The slope of $\hat\beta_t$ on $t$ is",
        r"        estimated by OLS without an intercept on the pre-treatment",
        r"        periods only ($t<0$), then extrapolated across $-5\leq t \leq 5$",
        r"        and subtracted from each estimate. This matches the rotation",
        r"        used in \texttt{code/\_replication\_rural/tools/plot\_event\_studies.R}.",
        r"\end{itemize}",
        r"",
        r"\tableofcontents",
        r"\clearpage",
        r"",
    ]

    section_order = [
        ("r2", "all", R2_PREFIXES, R2_FIELD),
        ("r2", "own", R2_PREFIXES, R2_FIELD),
        ("r3", "all", R3_PREFIXES, R3_FIELD),
        ("r3", "own", R3_PREFIXES, R3_FIELD),
    ]

    for rubric, suffix, prefix_order, prefix_label in section_order:
        bucket = grouped[(rubric, suffix)]
        if not bucket:
            continue
        lines.append(rf"\section{{{SECTION_LABEL[(rubric, suffix)]}}}")
        lines.append("")
        for pre in prefix_order:
            files = sorted(bucket.get(pre, []))
            if not files:
                continue
            lines.append(rf"\subsection{{{latex_escape(prefix_label[pre])}}}")
            lines.append("")
            for f in files:
                parsed = parse_name(f.stem)
                if parsed is None:
                    continue
                _, _, _, value = parsed
                rot = f"{f.stem}_rotated"
                has_rot = rot in rotated_set
                cap = caption_for(rubric, suffix, pre, value, f.stem)

                lines.append(r"\begin{figure}[H]")
                lines.append(r"  \centering")
                lines.append(r"  \begin{subfigure}[b]{0.85\textwidth}")
                lines.append(r"    \centering")
                lines.append(rf"    \includegraphics[width=\textwidth]{{{f.name}}}")
                lines.append(r"    \caption*{\small\textbf{Original}}")
                lines.append(r"  \end{subfigure}")
                if has_rot:
                    lines.append(r"  \vspace{0.4em}")
                    lines.append(r"  \begin{subfigure}[b]{0.85\textwidth}")
                    lines.append(r"    \centering")
                    lines.append(rf"    \includegraphics[width=\textwidth]{{{rot}.png}}")
                    lines.append(r"    \caption*{\small\textbf{Rotated (pre-trend removed)}}")
                    lines.append(r"  \end{subfigure}")
                lines.append(rf"  \caption{{{cap}}}")
                lines.append(r"\end{figure}")
                lines.append(r"\clearpage")
                lines.append("")
        lines.append("")

    lines.append(r"\end{document}")
    OUT_TEX.write_text("\n".join(lines))
    print(f"wrote {OUT_TEX}")

    # Wipe stale auxiliary files so pdflatex starts clean.
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
                print(r.stdout[-2500:])
                print(r.stderr[-1000:])
                return 1
    except FileNotFoundError:
        print(f"pdflatex not found at {pdflatex}. Install MacTeX or compile manually.")
        return 1

    for ext in (".aux", ".log", ".toc", ".out"):
        aux = OUT_TEX.with_suffix(ext)
        if aux.exists():
            aux.unlink()

    print(f"wrote {OUT_PDF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
