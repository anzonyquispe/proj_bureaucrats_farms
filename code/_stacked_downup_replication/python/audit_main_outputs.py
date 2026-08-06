#!/usr/bin/env python3
r"""Audit only active table and figure references in main.tex.

Percent comments, comment environments, ``\iffalse`` blocks, and everything
after the first active ``\end{document}`` are excluded from the audit.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
import re
import sys


TABLE_SOURCES = {
    "tables/main_did_downup_ac_rural_acpop": "_main_1_did.do; _generate_all_tables.do",
    "tables/_main_3_bureau_polisc_did_rural_acpop": "_main_3_bureau_polisc_did.do; _generate_all_tables.do",
    "tables/descriptives_main": "app_main_descriptive.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new": "_app_6_main_did_treat_definition.do; _generate_all_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new2": "_app_6_main_did_treat_definition.do; _generate_all_tables.do",
    "tables/_app_6_main_did_treat_definition_rural_acpop_new3": "_app_6_main_did_treat_definition.do; _generate_all_tables.do",
    "tables/_app_7_main_did_downup_area_ac_dv_rural_acpop": "_app_7_main_did_downup_area_ac_dv.do; _generate_all_tables.do",
    "tables/_app_8_main_did_by_year_rural_acpop": "_app_8_main_did_by_year.do; _generate_all_tables.do",
    "tables/_app_9_main_did_by_state_rural_acpop": "_app_9_main_did_by_state.do; _generate_all_tables.do",
    "tables/_app_11_placebo_pop_13km_rural": "_app_11_placebo_pop_13km.do; _generate_all_tables.do",
    "tables/_protest_stacked_descriptive.tex": "app_5km_descriptive.do",
    "tables/_main_4_protest_5km_fe12_did_downup_rural_acpop_new": "_main_4_protest_5km_fe12_did_downup.do; _generate_all_tables.do",
    "tables/_politicians_stacked_descriptive": "app_polischar_descriptive.do",
    "tables/_main_5_polischar_fe12_did_downup_inter_rural_acpop.tex": "_main_5_polischar_fe12_did_downup_inter.do; _generate_all_tables.do",
}

PYTHON_FIGURES = {
    **{f"figures/{name}": "python/generate_design_maps.py" for name in (
        "map_grids.png", "panel_A_downwind.png", "panel_B_downwind.png",
        "panel_C_upwind.png", "march2013_plot.png", "october2013_plot.png",
        "acs_grids_radius12km.png",
    )},
    **{f"figures/{name}": "python/generate_descriptive_figures.py" for name in (
        "monthly_fires.png", "monthly_wind_direction.png",
        "downup_evtime_hist.png", "panelview_self_profession.png",
    )},
    **{f"figures/{name}": "python/generate_protest_figures.py" for name in (
        "5km_plot.png", "protests_monthly_bars.png", "ac_protest_plot.png",
    )},
}

STATA_FIGURES = {
    "figures/neighbor_output.pdf": "_main_6_neighbour.do; _main_6_neighbour_plot.do",
    "figures/_app_18_protest_5km_fe12_did_downup_plot_rural_acpop_1.png": "_app_18_protest_5km_fe12_did_downup_plot.do; _generate_interaction_plots.do; interaction_graph.ado",
    "figures/_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop_1.png": "_app_19_polischar_fe12_did_downup_inter_plot.do; _generate_interaction_plots.do; interaction_graph.ado",
}

EVENT_FIGURES = {
    "figures/stacked_event_study_5pre_rural_1_rotated.png": "_main_2_stacked_event_study_5pre_area.do; plotting_event_studies.R",
    "figures/stacked_event_study_pop_5pre_rural_1_ori.png": "_main_2_stacked_event_study_5pre.do; plotting_event_studies.R",
    "figures/stacked_event_study_pop_5pre_rural_1_rotated.png": "_main_2_stacked_event_study_5pre.do; plotting_event_studies.R",
    "figures/stacked_event_study_pop_5pre_rural_1_rot_honest2.png": "_main_2_stacked_event_study_5pre.do; plotting_event_studies.R",
    "figures/stacked_event_study_pop_5pre_rural_riceP_rotated": "_main_2_stacked_event_study_5pre.do; plotting_event_studies.R",
}
for analysis, dofile in (
    ("_app_16_polischar_fe12_evst_all", "_app_16_polischar_fe12_evst_all.do"),
    ("_app_17_5km_fe12_evst_all", "_app_17_5km_fe12_evst_all.do"),
):
    prefix = f"figures/{analysis}_rural_acpop_1"
    EVENT_FIGURES[f"{prefix}_ori.png"] = f"{dofile}; plotting_event_studies.R"
    EVENT_FIGURES[f"{prefix}_rotated.png"] = f"{dofile}; plotting_event_studies.R"
    honest = "rot_honest2" if analysis.startswith("_app_16") else "honest2"
    EVENT_FIGURES[f"{prefix}_{honest}.png"] = f"{dofile}; plotting_event_studies.R"
EVENT_FIGURES[
    "figures/_app_16_polischar_fe12_evst_all_rural_acpop_riceP_5_rotated.png"
] = "_app_16_polischar_fe12_evst_all.do; plotting_event_studies.R"

STATIC_ASSETS = {
    "figures/cnn.png": "externally supplied illustration",
    "figures/2020_Indian_farmers_protest.jpg": "externally supplied photograph",
    "figures/myneta_example2.png": "externally supplied MyNeta screenshot",
    "figures/rices_grids_150dpi_q75.pdf": "externally supplied/compressed rice map",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tex", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--check-files", action="store_true")
    parser.add_argument("--strict", action="store_true")
    return parser.parse_args()


def strip_line_comment(line: str) -> str:
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


def active_references(path: Path) -> list[tuple[int, str, str]]:
    patterns = {
        "table": re.compile(r"\\input\{(tables/[^}]+)\}"),
        "figure": re.compile(r"\\includegraphics(?:\[[^]]*\])?\{([^}]+)\}"),
    }
    found: list[tuple[int, str, str]] = []
    comment_depth = 0
    false_depth = 0
    begin_comment = r"\begin{comment}"
    end_comment = r"\end{comment}"

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = strip_line_comment(raw_line)
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

        if false_depth:
            false_depth += len(re.findall(r"\\if(?:false|true)\b", line))
            false_depth -= len(re.findall(r"\\fi\b", line))
            if false_depth < 0:
                raise ValueError(f"Unbalanced \\fi near {path}:{line_number}")
            continue
        if re.search(r"\\iffalse\b", line):
            false_depth = 1
            continue

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
    if kind == "table" and reference in TABLE_SOURCES:
        return "generated", TABLE_SOURCES[reference]
    if reference in PYTHON_FIGURES:
        return "generated", PYTHON_FIGURES[reference]
    if reference in STATA_FIGURES:
        return "generated", STATA_FIGURES[reference]
    if reference in EVENT_FIGURES:
        return "generated", EVENT_FIGURES[reference]
    if reference in STATIC_ASSETS:
        return "static_asset", STATIC_ASSETS[reference]
    return "code_not_found", "No generating code located in this package or the original package"


def generator_files_exist(package: Path, source: str) -> bool:
    return all((package / item.strip()).is_file() for item in source.split(";") if item.strip())


def output_candidates(root: Path, kind: str, reference: str) -> list[Path]:
    paper = root / "tex" / "paper"
    base = paper / reference
    if kind == "table":
        return [base] if base.suffix else [base.with_suffix(".tex")]
    if base.suffix:
        return [base]
    return [base.with_suffix(extension) for extension in (".pdf", ".png", ".jpg", ".jpeg", ".eps")]


def main() -> int:
    options = parse_args()
    grouped: dict[tuple[str, str], list[int]] = defaultdict(list)
    for line, kind, reference in active_references(options.tex):
        grouped[(kind, reference)].append(line)

    rows = []
    for (kind, reference), lines in sorted(grouped.items()):
        status, source = classify(kind, reference)
        source_ok = ""
        if status == "generated":
            source_ok = str(generator_files_exist(options.package, source)).lower()
            if source_ok == "false":
                status = "generator_file_missing"
        output_ok = ""
        if options.check_files:
            if options.root is None:
                raise ValueError("--root is required with --check-files")
            output_ok = str(any(path.is_file() for path in output_candidates(
                options.root, kind, reference
            ))).lower()
        rows.append({
            "type": kind,
            "reference": reference,
            "main_tex_lines": ",".join(map(str, lines)),
            "status": status,
            "package_source": source,
            "generator_files_exist": source_ok,
            "output_exists": output_ok,
        })

    options.package.mkdir(parents=True, exist_ok=True)
    manifest = options.package / "output_manifest.csv"
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    code_gaps = [row for row in rows if row["status"] in {"code_not_found", "generator_file_missing"}]
    missing_outputs = [
        row for row in rows
        if options.check_files and row["status"] == "generated" and row["output_exists"] == "false"
    ]
    static = [row for row in rows if row["status"] == "static_asset"]
    missing_static = [
        row for row in static
        if options.check_files and row["output_exists"] == "false"
    ]
    generated = [row for row in rows if row["status"] == "generated"]
    generated_tables = [row for row in generated if row["type"] == "table"]
    generated_figures = [row for row in generated if row["type"] == "figure"]
    report = [
        "# Active main.tex output audit",
        "",
        "Only active table inputs and figure references are counted. Percent comments, `comment` environments, `\\iffalse` blocks, and material after the first active `\\end{document}` are excluded.",
        "",
        f"- Unique active tables/figures: {len(rows)}",
        f"- Mapped to generators in this package: {len(generated)}",
        f"  - Active generated tables: {len(generated_tables)}",
        f"  - Active generated figures: {len(generated_figures)}",
        f"- Static/external assets: {len(static)}",
        f"- Outputs without located generating code: {len(code_gaps)}",
    ]
    if options.check_files:
        report.append(f"- Generated outputs absent on disk: {len(missing_outputs)}")
        report.append(f"- Static/external assets absent on disk: {len(missing_static)}")
    report.append("")
    if code_gaps:
        report.extend(["## Outputs without corresponding code", ""])
        report.extend(
            f"- `{row['reference']}` (main.tex line {row['main_tex_lines']})"
            for row in code_gaps
        )
        report.append("")
    if missing_outputs:
        report.extend(["## Mapped outputs not found after the run", ""])
        report.extend(
            f"- `{row['reference']}` (main.tex line {row['main_tex_lines']})"
            for row in missing_outputs
        )
        report.append("")
    if static:
        report.extend(["## Static/external assets", ""])
        report.extend(
            f"- `{row['reference']}` -- {row['package_source']}"
            for row in static
        )
        report.append("")
    report.append("See `output_manifest.csv` for the complete line-by-line mapping.")
    (options.package / "OUTPUT_GAPS.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"Wrote {manifest}")
    print(f"Wrote {options.package / 'OUTPUT_GAPS.md'}")

    if options.strict and (code_gaps or missing_outputs or missing_static):
        print(
            f"Strict audit failed: {len(code_gaps)} code gaps, "
            f"{len(missing_outputs)} missing generated outputs, and "
            f"{len(missing_static)} missing static assets.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
