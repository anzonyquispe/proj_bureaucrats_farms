"""Write the appendix mechanism tables (Section B.6) from the output of _app_mech_tables.do.

Reads tables/mech_results.csv and tables/mech_descriptives.csv and writes, in the paper's
esttab style (constituency-clustered SE in parentheses):
  descriptives_mech.tex  B.8  descriptive statistics (panel A documents, panel B court cases)
  cb_fires.tex           B.9  number of fires on exposure, month and quarter
  cb_docs_courts.tex     B.10 crop-burning documents and Air Act court cases
  courts_leads_t3.tex    B.11 Air Act court cases, t to t+3
Captions and notes are in main.tex. Usage: python _app_mech_tables.py [tables folder]
"""
import math
import sys
from pathlib import Path
import pandas as pd

T = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "tables"
r = pd.read_csv(T / "mech_results.csv")
d = pd.read_csv(T / "mech_descriptives.csv")


def a3(x):
    """esttab's a3 format: 3 significant digits below 1, 3 decimals from 1 to 10."""
    if x == 0:
        return "0"
    m = math.floor(math.log10(abs(x)))
    return f"{x:.{2 - m if abs(x) < 1 else max(0, 3 - m)}f}"


def sym(p):
    s = "***" if p < .01 else "**" if p < .05 else "*" if p < .1 else ""
    return rf"\sym{{{s}}}" if s else ""


def get(tab, col, var="z", lead=0):
    q = r[(r.tab == tab) & (r.col == col) & (r["var"] == var) & (r.lead == lead)]
    assert len(q) == 1, (tab, col, var, lead)
    return q.iloc[0]


def mc(s, n=1):
    return rf"\multicolumn{{{n}}}{{c}}{{{s}}}"


def bf2(a, b):
    return rf"\makecell{{\textbf{{{a}}} \\ \textbf{{{b}}}}}"


def coef(label, xs):
    """Coefficient row with stars and SE row; None leaves the cell empty."""
    return [f"{label}&" + "&".join(f"{a3(x.b)}{sym(x.p)}" if x is not None else "" for x in xs) + r"\\",
            "            &" + "&".join(f"({a3(x.se)})" if x is not None else "" for x in xs) + r"\\"]


def body(head, coef_rows, stats, fe_rows, n):
    return "\n".join([r"{", r"\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}", rf"\begin{{tabular}}{{l*{{{n}}}{{c}}}}",
                      r"\toprule", *head, r"\midrule", *coef_rows, r"\midrule",
                      "Observations&" + "&".join(f"{int(x.N):,}" for x in stats) + r"\\", *fe_rows,
                      "Mean DV     &" + "&".join(f"{x.ymean:.3f}" for x in stats) + r"\\",
                      r"\bottomrule", r"\end{tabular}", r"}"]) + "\n"


# B.10: documents (most / only about crop burning) and court cases, month and quarter
A = [get("B10", c) for c in ["c1", "c2", "c3", "c4", "c5", "c6"]]
headA = [
    r"            &\multicolumn{4}{c}{\textbf{Government documents}}&\multicolumn{2}{c}{\textbf{Court Data}}\\"
    r"\cmidrule(lr){2-5}\cmidrule(lr){6-7}",
    r"            &\multicolumn{2}{c}{\textbf{Month}}&\multicolumn{2}{c}{\textbf{Quarter}}&" + mc(r"\textbf{Month}") + "&"
    + mc(r"\textbf{Quarter}") + r"\\\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-6}\cmidrule(lr){7-7}",
    "            &" + "&".join(mc(f"({i})") for i in range(1, 7)) + r"\\",
    "            &" + "&".join(mc(s) for s in [bf2("Most about", "crop burning"), bf2("Only about", "crop burning")] * 2)
    + "&" + mc(r"\textbf{Cases}", 2) + r"\\"]
feA = [r"AC FE       &Y&Y&Y&Y&Y&Y\\", r"Month-Year FE&Y&Y&N&N&Y&N\\", r"Quarter-Year FE&N&N&Y&Y&N&Y\\"]
tabA = body(headA, coef("Exposure    ", A), A, feA, 6)

# B.11: court cases t..t+3
B = [get("B11", "t", lead=k) for k in range(4)]
headB = [r"            &\multicolumn{4}{c}{\textbf{Air Act court cases (any case)}}\\\cmidrule(lr){2-5}",
         "            &" + "&".join(mc(f"({i})") for i in range(1, 5)) + r"\\",
         "            &" + "&".join(mc(rf"$\boldsymbol{{t{s}}}$") for s in ["", "+1", "+2", "+3"]) + r"\\"]
tabB = body(headB, coef("Exposure    ", B), B, [r"AC FE       &Y&Y&Y&Y\\", r"Month-Year FE&Y&Y&Y&Y\\"], 4)

# B.9: number of fires, month (1-2) and quarter (3-4)
Z = [get("B9", c) for c in ["c1", "c2", "c3", "c4"]]
L = [None, get("B9", "c2", "count_prev_year"), None, get("B9", "c4", "count_prev_year")]
headC = [r"            &\multicolumn{4}{c}{Number of Fires}\\\cmidrule(lr){2-5}",
         r"            &\multicolumn{2}{c}{Month}&\multicolumn{2}{c}{Quarter}\\\cmidrule(lr){2-3}\cmidrule(lr){4-5}",
         "            &" + "&".join(mc(f"({i})") for i in range(1, 5)) + r"\\"]
tabC = body(headC, coef("Exposure    ", Z) + coef(r"Number of Fires$_{t-12}$", L), Z,
            [r"AC FE       &Y&Y&Y&Y\\", r"Month-Year FE&Y&Y&N&N\\", r"Quarter-Year FE&N&N&Y&Y\\"], 4)

# B.8: descriptive statistics
LAB = {"ac_uq_id": "Assembly Constituency", "distr_id": "District", "year": "Year", "month": "Month",
       "province": "Province", "fires": "Number of Fires", "fires_l12": r"Number of Fires$_{t-12}$",
       "most": r"Any Document Mostly About Crop Burning (\%)", "only": r"Any Document Only About Crop Burning (\%)",
       "expo": "Exposure", "q_fires": "Quarterly Number of Fires",
       "q_most": r"Quarterly Any Document Mostly About Crop Burning (\%)",
       "q_only": r"Quarterly Any Document Only About Crop Burning (\%)", "q_expo": "Quarterly Exposure",
       "court": r"Any Air Act Court Case (\%)", "q_court": r"Quarterly Any Air Act Court Case (\%)"}
ORDER = {"A": ["ac_uq_id", "distr_id", "year", "month", "province", "fires", "fires_l12", "most", "only", "expo",
               "q_fires", "q_most", "q_only", "q_expo"],
         "B": ["ac_uq_id", "distr_id", "year", "month", "province", "court", "expo", "q_court", "q_expo"]}
TITLE = {"A": "Panel A: Government documents sample", "B": "Panel B: Court cases sample"}


def drow(panel, key):
    q = d[(d.panel == panel) & (d.key == key)]
    assert len(q) == 1, (panel, key)
    x = q.iloc[0]
    if pd.notna(x["unique"]):
        return f"{LAB[key]} &  &  &  &  & {int(x.N):,} & {int(x['unique']):,}\\\\"
    return (f"{LAB[key]} & " + " & ".join(f"{v:,.3f}" for v in [x["mean"], x.sd, x["min"], x["max"]])
            + f" & {int(x.N):,} & \\\\")


rows = [r"\begin{tabular}{lrrrrrr}", r"\toprule", r" & Mean & SD & Min & Max & Observations & Unique Obs.\\"]
for pnl in ["A", "B"]:
    rows += [r"\midrule", rf"\multicolumn{{7}}{{l}}{{\textit{{{TITLE[pnl]}}}}}\\"] + [drow(pnl, k) for k in ORDER[pnl]]
rows += [r"\bottomrule", r"\end{tabular}"]

for fn, t in [("cb_docs_courts.tex", tabA), ("courts_leads_t3.tex", tabB), ("cb_fires.tex", tabC),
              ("descriptives_mech.tex", "\n".join(rows) + "\n")]:
    (T / fn).write_text(t)
    print("written:", T / fn)
