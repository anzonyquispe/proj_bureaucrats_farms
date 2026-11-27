"""Crop-burning government documents by district and month, for _app_mech_tables.do.

Reads the document index (Dropbox sa_fires/data/crop_burning_documents/outputs/
07_index_2026-11-23_narrow_v5_passages.csv) and writes to --out:
  cb_district_month.csv  documents dated 2012m9-2022m8 by district and month: any, with a
                         crop-burning item, relevance 3 (only about crop burning) and
                         relevance 2-3 (mostly about crop burning)
  cb_entry.csv           month of the first document of any kind, by district
Districts are spelled as in the AC-month panel; year-only dates are dropped.
"""
import argparse
from pathlib import Path
import pandas as pd

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument("--index", type=Path, required=True, help="07_index_2026-11-23_narrow_v5_passages.csv")
ap.add_argument("--panel", type=Path, required=True, help="action_final_merged_kw.dta (district spelling)")
ap.add_argument("--out", type=Path, required=True, help="output folder (data_output/intermediate)")
a = ap.parse_args()

# Index spelling -> panel spelling. Districts not in the panel are dropped.
ALIAS = {"Kaimur (Bhabua)": "Kaimur (bhabua)", "Purbi Champaran": "Purba Champaran", "Ferozepur": "Firozpur",
         "S.A.S Nagar": "Sahibzada Ajit Singh Nag*"}

d = pd.read_csv(a.index)
panel = set(pd.read_stata(a.panel, columns=["district"]).district.unique())

# One row per document and assigned district
d = d[d.level == "district"].copy()
d["assigned"] = d.assigned_districts.fillna(d.district).astype(str).str.split(";")
d = d.explode("assigned")
d["district_panel"] = d.assigned.str.strip().map(lambda x: ALIAS.get(x, x))

s = d.date_used.astype(str)
prec = s.str.len().map({10: "day", 7: "month", 4: "year"}).fillna("none")
d["ym"] = pd.to_datetime(s.str[:7], format="%Y-%m", errors="coerce").where(prec.isin(["day", "month"]))
d["year"], d["month"] = d.ym.dt.year, d.ym.dt.month

d["all"] = 1
d["cb"] = (d.crop_burning_item == "yes").astype(int)
d["cb_rel3"] = ((d.cb == 1) & (d.relevance == 3)).astype(int)
d["cb_rel23"] = ((d.cb == 1) & (d.relevance >= 2)).astype(int)

ok = d[d.district_panel.isin(panel) & d.ym.notna()]
entry = ok.groupby("district_panel").ym.min().rename("first_doc").reset_index()
entry.to_csv(a.out / "cb_entry.csv", index=False)

w = ok[(ok.ym >= "2012-09-01") & (ok.ym <= "2022-08-01")]
cnt = ["all", "cb", "cb_rel3", "cb_rel23"]
w.groupby(["district_panel", "year", "month"])[cnt].sum().reset_index().rename(
    columns={c: f"n_{c}" for c in cnt}).to_csv(a.out / "cb_district_month.csv", index=False)

print("districts with a document (entry):", len(entry))
print("documents in 2012m9-2022m8: all", int(w["all"].sum()), "| crop-burning item", int(w.cb.sum()),
      "| relevance 2-3", int(w.cb_rel23.sum()), "| relevance 3", int(w.cb_rel3.sum()))
