# DISHA meeting dates (date fix)

`code/_stacked_downup_replication/_app_disha_datefix.py` rebuilds the DISHA district × meeting-month
panel with the meeting dates read correctly. Its outputs are in Dropbox
`sa_fires/data/DISHA/DISHA_Meetings/panel_datefix/`.

## The error
- The dates in `documents_date_with_upload_year.csv` are written as DD-MM-YYYY, as `rubric_date.md`
  requires. In 1,206 of 2,860 dates the first field is above 12; the second never is.
- `31_DISHA_process.ipynb` read them with `pd.to_datetime(date, errors='coerce')` and no format, so
  pandas assumed MM-DD-YYYY:
  - days up to 12 swap day and month (`03-04-2021`, 3 April, becomes 4 March);
  - days above 12 cannot be read, so those documents are dropped (`30-11-2017`).
- The fix is `format='%d-%m-%Y'`.
- The day-first reading matches the upload dates. Among dates readable either way, the median gap
  between meeting and upload is 13 days under DD-MM and 134 days under MM-DD.

## Effect, 2012m9–2022m8

| | Notebook (original panel) | Dates fixed |
|---|---|---|
| Documents | 488 | 848 |
| District-months with documents | 330 | 533 |
| Districts | 97 | 110 |
| Documents in October–November | 9 | 86 |

Under the notebook reading, 264 of the 488 documents fall in January.

## Use
```
python _app_disha_datefix.py --src <Dropbox>/sa_fires/data/DISHA/DISHA_Meetings \
    --out <Dropbox>/sa_fires/data/DISHA/DISHA_Meetings/panel_datefix
```
- The script first checks that the notebook reading reproduces `documents_district_panel.csv`.
- `documents_district_panel_datefix.csv` (plus `_minutes` and `_no_other`) has the columns of
  `documents_district_panel.csv`, so the DISHA code runs on it unchanged.
- The DISHA tables built from the original panel (`_app_disha.do`, the `action_final*` tables) still
  use the notebook dates. No table in `main.tex` uses DISHA documents as of 2026-11-27.
