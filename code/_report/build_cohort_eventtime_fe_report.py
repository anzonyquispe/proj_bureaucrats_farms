#!/usr/bin/env python3
"""Build the current politician-only cohort-event-time FE report."""

from __future__ import annotations

from pathlib import Path
from textwrap import wrap

from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas


REPO = Path(__file__).resolve().parents[2]
FIGURES = REPO / "figures" / "exploratory_analysis" / "cohort_eventtime_fe_sweep"
OUTPUT = REPO / "output" / "pdf" / "cohort_eventtime_fe_sweep_report.pdf"

BASE_FE = {
    1: "Grid x cohort",
    2: "Grid x cohort; month-year x cohort",
    3: "Grid x cohort; province-cohort linear month-year trend",
    4: "Grid x cohort; government year",
    5: "Grid x cohort; province-cohort x election year",
    6: "Grid x cohort; province-cohort x election year x government year",
    7: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend",
    8: "Grid x cohort; month-year x cohort; government year",
    9: "Grid x cohort; month-year x cohort; province-cohort x election year",
    10: "Grid x cohort; month-year x cohort; province-cohort x election year x government year",
    11: "Grid x cohort; province-cohort linear month-year trend; government year",
    12: "Grid x cohort; province-cohort linear month-year trend; province-cohort x election year",
    13: "Grid x cohort; province-cohort linear month-year trend; province-cohort x election year x government year",
    14: "Grid x cohort; government year; province-cohort x election year",
    15: "Grid x cohort; government year; province-cohort x election year x government year",
    16: "Grid x cohort; province-cohort x election year; province-cohort x election year x government year",
    17: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; government year",
    18: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; province-cohort x election year",
    19: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; province-cohort x election year x government year",
    20: "Grid x cohort; month-year x cohort; government year; province-cohort x election year",
    21: "Grid x cohort; month-year x cohort; government year; province-cohort x election year x government year",
    22: "Grid x cohort; month-year x cohort; province-cohort x election year; province-cohort x election year x government year",
    23: "Grid x cohort; province-cohort linear month-year trend; government year; province-cohort x election year",
    24: "Grid x cohort; province-cohort linear month-year trend; government year; province-cohort x election year x government year",
    25: "Grid x cohort; province-cohort linear month-year trend; province-cohort x election year; province-cohort x election year x government year",
    26: "Grid x cohort; government year; province-cohort x election year; province-cohort x election year x government year",
    27: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; government year; province-cohort x election year",
    28: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; government year; province-cohort x election year x government year",
    29: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; province-cohort x election year; province-cohort x election year x government year",
    30: "Grid x cohort; month-year x cohort; government year; province-cohort x election year; province-cohort x election year x government year",
    31: "Grid x cohort; province-cohort linear month-year trend; government year; province-cohort x election year; province-cohort x election year x government year",
    32: "Grid x cohort; month-year x cohort; province-cohort linear month-year trend; government year; province-cohort x election year; province-cohort x election year x government year",
}

RAW_NAMES = {
    "Grid x cohort": "unique_small_grid_id_cohort",
    "month-year x cohort": "monthyearco",
    "province-cohort linear month-year trend": "province_cohort#c.monthyear",
    "government year": "yeargov",
    "province-cohort x election year": "province_cohort#election_year",
    "province-cohort x election year x government year": "province_cohort#election_year#yeargov",
}


def draw_wrapped(c: canvas.Canvas, text: str, x: float, y: float, width_chars: int,
                 font: str = "Helvetica", size: float = 8.5, leading: float = 10.5) -> float:
    c.setFont(font, size)
    for line in wrap(text, width=width_chars, break_long_words=False):
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_page_number(c: canvas.Canvas, page: int, width: float) -> None:
    c.setFont("Helvetica", 8)
    c.setFillColor(colors.HexColor("#555555"))
    c.drawRightString(width - 24, 16, f"Page {page}")
    c.setFillColor(colors.black)


def fit_image(c: canvas.Canvas, path: Path, x: float, y: float,
              width: float, height: float, label: str) -> None:
    c.setStrokeColor(colors.HexColor("#B8B8B8"))
    c.setLineWidth(0.5)
    c.rect(x, y, width, height, stroke=1, fill=0)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(x + 6, y + height - 13, label)
    image_box_y = y + 3
    image_box_h = height - 19
    if not path.exists() or path.stat().st_size == 0:
        c.setFillColor(colors.HexColor("#F2F2F2"))
        c.rect(x + 1, image_box_y, width - 2, image_box_h, stroke=0, fill=1)
        c.setFillColor(colors.HexColor("#8A2D2D"))
        c.setFont("Helvetica-Bold", 12)
        c.drawCentredString(x + width / 2, image_box_y + image_box_h / 2 + 4,
                            "RESULT PENDING")
        c.setFont("Helvetica", 8)
        c.drawCentredString(x + width / 2, image_box_y + image_box_h / 2 - 10,
                            "The corresponding figure was not available locally.")
        c.setFillColor(colors.black)
        return
    image = ImageReader(str(path))
    iw, ih = image.getSize()
    scale = min((width - 6) / iw, image_box_h / ih)
    draw_w, draw_h = iw * scale, ih * scale
    draw_x = x + (width - draw_w) / 2
    draw_y = image_box_y + (image_box_h - draw_h) / 2
    c.drawImage(image, draw_x, draw_y, draw_w, draw_h,
                preserveAspectRatio=True, mask="auto")


def result_paths(fe: int) -> dict[str, Path]:
    tag = f"{fe:02d}"
    return {
        "pol_event": FIGURES / f"politician_byprov_cohorttime_fe{tag}_event_rural_acpop_all_ori.png",
        "pol_rot": FIGURES / f"politician_byprov_cohorttime_fe{tag}_event_rural_acpop_all_rotated.png",
        "pol_did": FIGURES / f"politician_byprov_cohorttime_fe{tag}_did_interaction_rural_acpop_all_1.png",
    }


def build_report() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    width, height = landscape(letter)
    c = canvas.Canvas(str(OUTPUT), pagesize=(width, height), pageCompression=1)
    c.setTitle("Cohort-specific event-time fixed-effect sweep")
    page = 1

    # Cover.
    c.setFillColor(colors.HexColor("#17365D"))
    c.rect(0, 0, width, height, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 24)
    c.drawString(48, height - 88, "Politician cohort-event-time FE sweep")
    c.setFont("Helvetica", 14)
    c.drawString(48, height - 118, "Current politicians_characteristics_byprov.csv")
    c.setFont("Helvetica", 10)
    cover_lines = [
        "Treatment definition: downup_ac_pop",
        "Politician event window: relative years -5 to 4; omitted period -1",
        "Common addition to every specification: cohort-specific relative-year fixed effects",
        "Politicians: relative_year_bin_aux#cohort_id",
        "Interaction plots: every displayed lincom subtracts the control-pre estimate; control pre is normalized to zero",
        "The treated-control post contrast is unchanged because the common control-pre baseline cancels",
        "Interaction figures omit confidence intervals and report exact p-values rounded to three decimals",
    ]
    y = height - 180
    for line in cover_lines:
        c.drawString(52, y, line)
        y -= 20
    c.setFillColor(colors.HexColor("#FFE8A1"))
    c.roundRect(48, 72, width - 96, 78, 6, stroke=0, fill=1)
    c.setFillColor(colors.HexColor("#3D3200"))
    c.setFont("Helvetica-Bold", 10)
    c.drawString(60, 130, "Availability note")
    c.setFont("Helvetica", 9)
    c.drawString(60, 112, "All 32 politician event studies are included in original and rotated form.")
    c.drawString(60, 96, "All 32 politician DiD interaction plots are included.")
    c.drawString(60, 82, "No protest analysis is included in this report.")
    draw_page_number(c, page, width)
    c.showPage()
    page += 1

    # Variable legend.
    c.setFont("Helvetica-Bold", 18)
    c.drawString(30, height - 36, "Fixed-effect variables used")
    c.setFont("Helvetica", 9)
    c.drawString(30, height - 54, "The labels below correspond to the exact Stata variables used in the FE definitions.")
    y = height - 84
    for label, raw in RAW_NAMES.items():
        c.setFont("Helvetica-Bold", 9)
        c.drawString(40, y, label)
        c.setFont("Courier", 8.5)
        c.drawString(300, y, raw)
        y -= 24
    c.setFont("Helvetica-Bold", 10)
    c.drawString(40, y - 6, "Added to every politician FE:")
    c.setFont("Courier", 8.5)
    c.drawString(300, y - 6, "relative_year_bin_aux#cohort_id")
    draw_page_number(c, page, width)
    c.showPage()
    page += 1

    # FE specification index, eight rows per page.
    for start in range(1, 33, 8):
        c.setFont("Helvetica-Bold", 16)
        c.drawString(28, height - 32, f"Fixed-effect specifications FE{start}-FE{min(start + 7, 32)}")
        y = height - 60
        for fe in range(start, min(start + 8, 33)):
            c.setFillColor(colors.HexColor("#EAF1F8") if fe % 2 else colors.HexColor("#F7F7F7"))
            c.rect(28, y - 53, width - 56, 58, stroke=0, fill=1)
            c.setFillColor(colors.black)
            c.setFont("Helvetica-Bold", 10)
            c.drawString(38, y - 10, f"FE{fe:02d}")
            draw_wrapped(c, BASE_FE[fe], 82, y - 10, 116, size=8.5, leading=10)
            y -= 64
        draw_page_number(c, page, width)
        c.showPage()
        page += 1

    # Main results: original event studies and DiD interactions.
    for fe in range(1, 33):
        paths = result_paths(fe)
        c.setFont("Helvetica-Bold", 15)
        c.drawString(24, height - 25, f"FE{fe:02d}: politician event study and DiD interaction")
        spec = BASE_FE[fe]
        header_y = draw_wrapped(
            c, f"Base absorbed variables: {spec}", 24, height - 48,
            145, size=7.5, leading=9,
        )
        c.setFont("Helvetica", 7.5)
        c.drawString(24, header_y,
                     "Additional cohort-event-time FE: relative_year_bin_aux#cohort_id.")
        c.drawString(24, header_y - 10,
                     "Interaction panels omit CIs and show exact p-values rounded to three decimals; the post contrast is unchanged.")
        gap = 10
        panel_w = (width - 48 - gap) / 2
        panel_h = height - 112
        left = 24
        right = left + panel_w + gap
        bottom = 28
        fit_image(c, paths["pol_event"], left, bottom, panel_w, panel_h,
                  "Politician event study")
        fit_image(c, paths["pol_did"], right, bottom, panel_w, panel_h,
                  "Politician DiD interaction with downup_ac_pop")
        draw_page_number(c, page, width)
        c.showPage()
        page += 1

    # Rotated event-study appendix.
    c.setFont("Helvetica-Bold", 21)
    c.drawString(42, height - 76, "Appendix: detrended event studies")
    c.setFont("Helvetica", 10)
    c.drawString(42, height - 104,
                 "Each page presents the rotated politician event-study estimates for one FE specification.")
    c.drawString(42, height - 122,
                 "Pre- and post-treatment averages and standard errors are recomputed after the pretrend rotation.")
    draw_page_number(c, page, width)
    c.showPage()
    page += 1

    for fe in range(1, 33):
        paths = result_paths(fe)
        c.setFont("Helvetica-Bold", 15)
        c.drawString(24, height - 27, f"FE{fe:02d}: rotated event studies")
        c.setFont("Helvetica", 8)
        c.drawString(24, height - 42, BASE_FE[fe])
        panel_w = width - 120
        panel_h = height - 86
        fit_image(c, paths["pol_rot"], 60, 28, panel_w, panel_h,
                  "Politician rotated event study")
        draw_page_number(c, page, width)
        c.showPage()
        page += 1

    c.save()


if __name__ == "__main__":
    build_report()
    print(OUTPUT)
