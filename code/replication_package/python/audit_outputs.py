#!/usr/bin/env python3
"""Audit uncommented main.tex outputs against the consolidated package."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
import re


TABLE_SOURCES = {
    "tables/main_did_downup_area_ac_rural": "analysis/main_did_area.do; generate_tables.do",
    "tables/main_did_downup_area_ac_rural_acpop": "analysis/main_did_acpop_stacked.do; generate_tables.do",
    "tables/main_did_downup_ac_rural_acpop": "code/_stacked_downup_replication/_main_1_did.do; code/_stacked_downup_replication/_generate_all_tables.do",
    "tables/_main_3_bureau_polisc_did_rural": "analysis/bureaucrat_politician_area.do; generate_tables.do",
    "tables/_main_3_bureau_polisc_did_rural_acpop": "analysis/bureaucrat_politician_acpop_stacked.do; generate_tables.do",
    "tables/_app_6_main_did_treat_definition_rural": "analysis/treatment_definitions_area.do; generate_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop": "analysis/treatment_definitions_acpop.do; generate_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new": "code/_stacked_downup_replication/_app_6_main_did_treat_definition.do; code/_stacked_downup_replication/_generate_all_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new2": "code/_stacked_downup_replication/_app_6_main_did_treat_definition.do; code/_stacked_downup_replication/_generate_all_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new3": "code/_stacked_downup_replication/_app_6_main_did_treat_definition.do; code/_stacked_downup_replication/_generate_all_tables.do",
    "tables/_app_7_main_did_downup_area_ac_dv_rural": "analysis/alternative_outcomes_area.do; generate_tables.do",
    "tables/_app_7_main_did_downup_area_ac_dv_rural_acpop": "analysis/alternative_outcomes_acpop_stacked.do; generate_tables.do",
    "tables/_app_8_main_did_by_year_rural": "analysis/by_year_area.do; generate_tables.do",
    "tables/_app_8_main_did_by_year_rural_acpop": "analysis/by_year_acpop_stacked.do; generate_tables.do",
    "tables/_app_9_main_did_by_state_rural": "analysis/by_state_area.do; generate_tables.do",
    "tables/_app_9_main_did_by_state_rural_acpop": "analysis/by_state_acpop_stacked.do; generate_tables.do",
    "tables/_app_11_placebo_pop_13km_rural": "analysis/placebo_13km.do; generate_tables.do",
    "tables/_app_12_protest_5km_fe_did_rural": "analysis/protest_did_area.do; generate_tables.do",
    "tables/_main_4_protest_5km_fe12_did_downup_rural": "analysis/protest_downup_area.do; generate_tables.do",
    "tables/_main_4_protest_5km_fe12_did_downup_rural_acpop_new": "analysis/protest_downup_acpop.do; generate_tables.do",
    "tables/_main_5_polischar_fe12_did_downup_inter_rural.tex": "analysis/politician_characteristics_area.do; generate_tables.do",
    "tables/_main_5_polischar_fe12_did_downup_inter_rural_acpop.tex": "analysis/politician_characteristics_acpop.do; generate_tables.do",
    "tables/descriptives_main": "python/generate_descriptive_tables.py (called by generate_tables.do)",
    "tables/_protest_stacked_descriptive.tex": "python/generate_descriptive_tables.py (called by generate_tables.do)",
    "tables/_politicians_stacked_descriptive": "python/generate_descriptive_tables.py (called by generate_tables.do)",
}

PYTHON_FIGURES = {
    "figures/map_grids.png": "python/generate_design_maps.py",
    "figures/panel_A_downwind.png": "python/generate_design_maps.py",
    "figures/panel_B_downwind.png": "python/generate_design_maps.py",
    "figures/panel_C_upwind.png": "python/generate_design_maps.py",
    "figures/march2013_plot.png": "python/generate_design_maps.py",
    "figures/october2013_plot.png": "python/generate_design_maps.py",
    "figures/acs_grids_radius12km.png": "python/generate_design_maps.py",
    "figures/monthly_fires.png": "python/generate_descriptive_figures.py",
    "figures/monthly_wind_direction.png": "python/generate_descriptive_figures.py",
    "figures/downup_evtime_hist.png": "python/generate_descriptive_figures.py",
    "figures/panelview_self_profession.png": "python/generate_descriptive_figures.py",
    "figures/5km_plot.png": "python/generate_protest_figures.py",
    "figures/protests_monthly_bars.png": "python/generate_protest_figures.py",
    "figures/ac_protest_plot.png": "python/generate_protest_figures.py",
}

STATA_FIGURES = {
    "figures/neighbor_output.pdf": "analysis/neighbour_effects.do; generate_neighbour_plot.do",
    "figures/Interaction_downwind/_app_downup_rel_protest.png": "analysis/protest_interaction_area.do; generate_interaction_plots.do",
    "figures/Interaction_downwind/_app_downup_rel_polischar.png": "analysis/politician_interaction_area.do; generate_interaction_plots.do",
    "figures/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop_1.png": "analysis/protest_interaction_acpop.do; generate_interaction_plots.do",
    "figures/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop_1.png": "analysis/politician_interaction_acpop.do; generate_interaction_plots.do",
}

EVENT_FIGURES = {
    "figures/main_event_study_rural_1_ori.png",
    "figures/main_event_study_rural_1_rotated.png",
    "figures/main_event_study_rural_1_rot_honest2.png",
    "figures/main_event_study_rural_riceP_rotated.png",
    "figures/stacked_event_study_5pre_rural_1_rotated.png",
    "figures/stacked_event_study_pop_5pre_rural_1_ori.png",
    "figures/stacked_event_study_pop_5pre_rural_1_rotated.png",
    "figures/stacked_event_study_pop_5pre_rural_1_rot_honest2.png",
    "figures/stacked_event_study_pop_5pre_rural_riceP_rotated",
}
for analysis in ("_app_16_polischar_fe12_evst_all", "_app_17_5km_fe12_evst_all"):
    for suffix in ("", "_acpop"):
        prefix = f"figures/{analysis}_rural{suffix}_1"
        EVENT_FIGURES.update({f"{prefix}_ori.png", f"{prefix}_rotated.png"})
        EVENT_FIGURES.add(
            f"{prefix}_{'rot_honest2' if analysis.startswith('_app_16') else 'honest2'}.png"
        )
for suffix in ("", "_acpop"):
    EVENT_FIGURES.add(
        f"figures/_app_16_polischar_fe12_evst_all_rural{suffix}_riceP_5_rotated.png"
    )

STATIC_ASSETS = {
    ("input", "auxiliaries/preamble"): "LaTeX source asset; not present in this repository snapshot",
    ("bibliography", "all_references"): "bibliography source asset; not present in this repository snapshot",
    ("figure", "figures/cnn.png"): "externally supplied illustration; not present in this repository snapshot",
    ("figure", "figures/2020_Indian_farmers_protest.jpg"): "externally supplied photograph; not present in this repository snapshot",
    ("figure", "figures/rices_grids_150dpi_q75.pdf"): "externally supplied/compressed map; not present in this repository snapshot",
    ("figure", "figures/myneta_example2.png"): "externally supplied MyNeta example image; no generating script is expected",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tex", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    return parser.parse_args()


def active_references(path: Path) -> list[tuple[int, str, str]]:
    patterns = {
        "input": re.compile(r"\\input\{([^}]+)\}"),
        "figure": re.compile(r"\\includegraphics(?:\[[^]]*\])?\{([^}]+)\}"),
        "bibliography": re.compile(r"\\bibliography\{([^}]+)\}"),
    }

    def strip_line_comment(line: str) -> str:
        """Remove a TeX comment while retaining escaped percent signs."""
        for index, character in enumerate(line):
            if character != "%":
                continue
            backslashes = 0
            cursor = index - 1
            while cursor >= 0 and line[cursor] == "\\":
                backslashes += 1
                cursor -= 1
            if backslashes % 2 == 0:
                return line[:index]
        return line

    found: list[tuple[int, str, str]] = []
    comment_depth = 0
    false_depth = 0
    begin_comment = r"\begin{comment}"
    end_comment = r"\end{comment}"

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = strip_line_comment(raw_line)

        # Remove comment-environment content without deleting physical lines,
        # so reported main.tex line numbers remain exact.
        active_parts: list[str] = []
        cursor = 0
        while cursor < len(line):
            if comment_depth:
                end = line.find(end_comment, cursor)
                if end < 0:
                    cursor = len(line)
                    break
                comment_depth -= 1
                cursor = end + len(end_comment)
                continue
            begin = line.find(begin_comment, cursor)
            if begin < 0:
                active_parts.append(line[cursor:])
                break
            active_parts.append(line[cursor:begin])
            comment_depth += 1
            cursor = begin + len(begin_comment)
        line = "".join(active_parts)
        if comment_depth:
            continue

        # Treat \iffalse ... \fi as disabled code. This file currently does
        # not rely on it, but respecting it keeps the audit TeX-aware.
        if false_depth:
            false_depth += len(re.findall(r"\\if(?:false|true)\b", line))
            false_depth -= len(re.findall(r"\\fi\b", line))
            if false_depth < 0:
                raise ValueError(f"Unbalanced \\fi near {path}:{line_number}")
            continue
        if re.search(r"\\iffalse\b", line):
            false_depth = 1
            continue

        # TeX ignores everything after the first active end-of-document (or
        # end-of-input) command, even if more valid-looking LaTeX follows it.
        end_match = re.search(r"\\(?:end\{document\}|endinput)", line)
        if end_match:
            line = line[:end_match.start()]

        for kind, pattern in patterns.items():
            found.extend((line_number, kind, match.group(1)) for match in pattern.finditer(line))
        if end_match:
            break

    if comment_depth:
        raise ValueError(f"Unclosed comment environment in {path}")
    if false_depth:
        raise ValueError(f"Unclosed \\iffalse block in {path}")
    return found


def classify(kind: str, reference: str) -> tuple[str, str]:
    if reference in TABLE_SOURCES:
        return "generated", TABLE_SOURCES[reference]
    if reference in PYTHON_FIGURES:
        return "generated", PYTHON_FIGURES[reference]
    if reference in STATA_FIGURES:
        return "generated", STATA_FIGURES[reference]
    if reference in EVENT_FIGURES:
        return "generated", "event-study analysis dofile; plot_event_studies.R"
    if (kind, reference) in STATIC_ASSETS:
        return "static_asset", STATIC_ASSETS[(kind, reference)]
    return "code_not_found", "No generating code located in the audited repository folders"


def main() -> None:
    options = parse_args()
    grouped: dict[tuple[str, str], list[int]] = defaultdict(list)
    for line, kind, reference in active_references(options.tex):
        grouped[(kind, reference)].append(line)

    rows = []
    for (kind, reference), lines in sorted(grouped.items()):
        status, source = classify(kind, reference)
        rows.append({
            "type": kind,
            "reference": reference,
            "main_tex_lines": ",".join(map(str, lines)),
            "status": status,
            "package_source": source,
        })

    options.package.mkdir(parents=True, exist_ok=True)
    manifest = options.package / "output_manifest.csv"
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    missing = [row for row in rows if row["status"] == "code_not_found"]
    static = [row for row in rows if row["status"] == "static_asset"]
    counts = defaultdict(int)
    for row in rows:
        counts[row["status"]] += 1
    report = [
        "# Active outputs without located generating code",
        "",
        "This audit includes only executable `\\input`, `\\includegraphics`, and bibliography references in `code/_report/main.tex`. References in `%` comments, `comment` environments, disabled `\\iffalse` blocks, or after the first active `\\end{document}` are excluded.",
        "",
        f"- Unique active references: {len(rows)}",
        f"- Covered by this replication package: {counts['generated']}",
        f"- Static/external assets: {counts['static_asset']}",
        f"- Generating code not found: {counts['code_not_found']}",
        "",
    ]
    for kind in ("input", "figure", "bibliography"):
        subset = [row for row in missing if row["type"] == kind]
        if subset:
            report.extend([f"## Missing {kind} code", ""])
            report.extend(
                f"- `{row['reference']}` (main.tex lines {row['main_tex_lines']})" for row in subset
            )
            report.append("")
    if static:
        report.extend(["## Static or externally supplied assets", ""])
        report.extend(
            f"- `{row['reference']}` — {row['package_source']}" for row in static
        )
        report.append("")
    report.append("The machine-readable version, including every covered output and its package source, is `output_manifest.csv`.")
    (options.package / "CODE_NOT_FOUND.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"Wrote {manifest}")
    print(f"Wrote {options.package / 'CODE_NOT_FOUND.md'}")


if __name__ == "__main__":
    main()
