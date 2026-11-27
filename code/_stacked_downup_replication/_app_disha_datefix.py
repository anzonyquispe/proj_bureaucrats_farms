"""DISHA district x meeting-month panels with the meeting dates read as DD-MM-YYYY.

31_DISHA_process.ipynb parsed the dates with pd.to_datetime and no format, i.e. as
MM-DD-YYYY: days <= 12 swap day and month, days > 12 are dropped. This script rebuilds the
panel with format '%d-%m-%Y' (the format rubric_date.md asks for). It first checks that the
notebook reading reproduces documents_district_panel.csv, then writes to --out:
  documents_district_panel_type_datefix.csv   panel with counts by document type, minutes-only
                                              (_meeting_sum) and no-other (_no_other) versions
  documents_district_panel_datefix{,_minutes,_no_other}.csv
                                              drop-ins with the columns of documents_district_panel.csv
  disha_documents_type_datefix.csv            one row per document
Inputs (--src, Dropbox sa_fires/data/DISHA/DISHA_Meetings): type_output.csv, topic_output.csv,
documents_date_with_upload_year.csv, documents_district_panel.csv. Details: docs/disha_date_fix.md.
"""
import argparse
import sys
from pathlib import Path
import pandas as pd

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--src", type=Path, required=True, help="DISHA_Meetings folder")
ap.add_argument("--out", type=Path, required=True, help="output folder (DISHA_Meetings/panel_datefix)")
a = ap.parse_args()
SRC, OUT = a.src, a.out
KEYS = ["State", "District", "month", "year"]


def clean_id(s):
    return s.str.replace("_pan_t", "").str.replace("_t", "")


def load(date_format):
    """Cell 1 of the notebook; only the date parsing differs."""
    dtype = pd.read_csv(SRC / "type_output.csv")
    dtype["DISHA_Meeting_ID"] = clean_id(
        dtype["document_path"].str.split("/", expand=True)[3].str.split(".", expand=True)[0])
    date = pd.read_csv(SRC / "documents_date_with_upload_year.csv")
    topic = pd.read_csv(SRC / "topic_output.csv").merge(date, how="left", on="DISHA_Meeting_ID")
    topic["State"] = topic["DISHA_Meeting_ID"].str.split("_").str[0]
    topic["District"] = topic["DISHA_Meeting_ID"].str.split("_").str[1]
    topic["date"] = pd.to_datetime(topic["date"], format=date_format, errors="coerce")
    topic["year"] = topic["date"].dt.year
    topic["month"] = topic["date"].dt.month
    topic["DISHA_Meeting_ID"] = clean_id(topic["DISHA_Meeting_ID"])
    topic = topic.sort_values(["DISHA_Meeting_ID", "topic_primary"]).drop_duplicates()
    topic["DISHA_Meeting_ID"] = clean_id(topic["DISHA_Meeting_ID"].astype(str).str.split("_t.", expand=True)[0])
    topic["DISHA_Meeting_ID"] = topic["DISHA_Meeting_ID"].str.split(".", expand=True)[0]
    return topic, topic.merge(dtype, how="left", on="DISHA_Meeting_ID")


def wide(df, by, prefix):
    """Unique documents per district-month and category, one column per category."""
    w = (df.groupby(KEYS + [by])["DISHA_Meeting_ID"].nunique().reset_index()
         .pivot_table(index=KEYS, columns=by, values="DISHA_Meeting_ID", fill_value=0))
    return w.add_prefix(prefix).reset_index()


def panel(df, suffix=""):
    """Cell 2 of the notebook: number_docs plus topic and relevance counts."""
    out = (df.groupby(KEYS)["DISHA_Meeting_ID"].nunique().reset_index()
           .rename(columns={"DISHA_Meeting_ID": "number_docs"}))
    for by, prefix in [("topic_primary", "topic_primary_"), ("agriculture_relevance", "agri_rel_"),
                       ("farmer_protest_relevance", "protest_rel_"), ("air_pollution_relevance", "air_poll_rel_")]:
        out = out.merge(wide(df, by, prefix), how="left", on=KEYS)
    return out.rename(columns={c: c + suffix for c in out.columns if c not in KEYS})


# Check: the notebook reading (no format) reproduces documents_district_panel.csv
orig = pd.read_csv(SRC / "documents_district_panel.csv", index_col=0)
chk = orig.merge(panel(load(None)[0]), on=KEYS, how="outer", suffixes=("_o", "_n"), indicator=True)
bad = (chk["_merge"] != "both").sum()
for c in orig.columns:
    if c not in KEYS:
        bad += (chk[c + "_o"].fillna(-1) != chk[c + "_n"].fillna(-1)).sum()
if bad:
    sys.exit(f"Notebook reading differs from documents_district_panel.csv in {bad} cells")
print(f"notebook reading reproduces documents_district_panel.csv ({len(orig)} rows)")

# Dates read as DD-MM-YYYY
topic, topic_a = load("%d-%m-%Y")
base = panel(topic)
topic_a["type_of_document"] = topic_a["type_of_document"].fillna("missing")
types = wide(topic_a, "type_of_document", "number_docs_")
minutes = panel(topic_a[topic_a["type_of_document"] == "meeting_summary"], "_meeting_sum")
no_other = panel(topic_a[~topic_a["type_of_document"].isin(["other", "unclear", "missing"])], "_no_other")
full = base.merge(types, how="left", on=KEYS).merge(minutes, how="left", on=KEYS).merge(no_other, how="left", on=KEYS)
new = [c for c in full.columns if c not in base.columns]
full[new] = full[new].fillna(0)
full.to_csv(OUT / "documents_district_panel_type_datefix.csv")

# Drop-ins with the columns of documents_district_panel.csv, so the old code runs unchanged
for name, sfx in [("", ""), ("_minutes", "_meeting_sum"), ("_no_other", "_no_other")]:
    sub = full[full["number_docs" + sfx] > 0]
    drop = pd.DataFrame({c: sub[c] if c in KEYS else sub.get(c + sfx, 0) for c in orig.columns}).reset_index(drop=True)
    drop.to_csv(OUT / f"documents_district_panel_datefix{name}.csv")

cols = ["DISHA_Meeting_ID", "State", "District", "date", "year", "month", "upload_year", "upload_month",
        "topic_primary", "agriculture_relevance", "farmer_protest_relevance", "air_pollution_relevance",
        "type_of_document", "other_specification", "document_path"]
topic_a[cols].to_csv(OUT / "disha_documents_type_datefix.csv", index=False)
print(f"datefix: {len(full)} district-months, {topic_a.year.notna().sum()} dated rows")
