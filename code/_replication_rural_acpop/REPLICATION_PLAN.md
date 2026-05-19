# Rural Replication — `downup_ac_pop` Variant

This folder (`code/_replication_rural_acpop/`) replicates the rural analyses in
`code/_replication_rural/` but swaps the treatment variable from `downup_ac`
to `downup_ac_pop` (population-weighted "downwind > upwind" indicator).

It produces:

1. New `.ster` files (per analysis dofile) suffixed `_rural_acpop` in the
   Dropbox tables folder.
2. New `.tex` tables rendered from those `.ster` files, also suffixed
   `_rural_acpop`.
3. A single side-by-side comparison document,
   `_comparison_downup_ac_vs_acpop${sample}.tex`, in the same Dropbox tables
   folder, that `\input`s the original (`_rural.tex`) and the new
   (`_rural_acpop.tex`) for every section.

---

## 1. Goal

Re-run every rural analysis where `downup_ac` is the active treatment,
re-render the tables with the new variable, and produce one PDF that shows
the old and new results side by side so the team can eyeball the impact of
the change.

---

## 2. Scope — which dofiles were swapped

### Re-run with `downup_ac_pop` (16 dofiles)

| Original dofile                                  | Data input                            | Treatment role          |
| ------------------------------------------------ | ------------------------------------- | ----------------------- |
| `_main_1_did.do`                                 | `0_master_merge_data_gen.csv`         | main regressor          |
| `_main_2_event_study.do`                         | `0_master_merge_data_gen.csv`         | event-time treatment    |
| `_main_3_bureau_polisc_did.do`                   | `0_master_merge_data_gen.csv`         | politician treatment (bureaucrat side `downup_dummy` left untouched; interaction term rebuilt as `downup_interaction = downup_ac_pop * downup_dummy`) |
| `_main_4_protest_5km_fe12_did_downup.do`         | `stacked_data_protest.csv`            | moderator on Post×Protest |
| `_main_5_polischar_fe12_did_downup_inter.do`     | `politicians_characteristics.csv`     | moderator on Post×Agric. |
| `_app_7_main_did_downup_area_ac_dv.do`           | `0_master_merge_data_gen.csv`         | main regressor (alt DVs) |
| `_app_8_main_did_by_year.do`                     | `0_master_merge_data_gen.csv`         | by-year split           |
| `_app_9_main_did_by_state.do`                    | `0_master_merge_data_gen.csv`         | by-state split          |
| `_app_10_did_rice_moderators.do`                 | `0_master_merge_data_gen.csv`         | `downup_ac × rice_*`    |
| `_app_14_polischar_fe12_did_ricemods.do`         | `politicians_characteristics.csv`     | TREAT cell construction |
| `_app_15_polischar_fe12_did.do`                  | `politicians_characteristics.csv`     | TREAT cell construction |
| `_app_16_polischar_fe12_evst_all.do`             | `politicians_characteristics.csv`     | event-study moderator   |
| `_app_17_5km_fe12_evst_all.do`                   | `stacked_data_protest.csv`            | event-study moderator   |
| `_app_18_protest_5km_fe12_did_downup_plot.do`    | `stacked_data_protest.csv`            | moderator (plot input)  |
| `_app_19_polischar_fe12_did_downup_inter_plot.do`| `politicians_characteristics.csv`     | moderator (plot input)  |
| `_app_20_did_downwind_hm.do`                     | `0_master_merge_data_gen.csv`         | `downup_ac × rice_prod` |

### Skipped (intentionally)

| Dofile                                          | Reason                                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `_app_6_main_did_treat_definition.do`           | Already shows `downup_ac` and `downup_ac_pop` as separate columns; swapping makes eq1 ≡ eq2. |
| `_app_11_placebo_pop_13km.do`                   | Placebo whose treatment is `downup_pop_13km`; `downup_ac` is only a conditioning variable.   |
| `_app_12_protest_5km_fe_did.do`                 | Does not actually use `downup_ac` (only mentioned in header comment).                        |
| `_app_13_protest_5km_fe12_did_ricemods.do`      | Does not reference `downup_ac` at all.                                                       |

---

## 3. Plan executed

### Step 1 — Map the codebase
Read `code/_replication_rural/` in full: master orchestrator, per-section
analysis dofiles, table generator, sbatch jobs, helper ados. Identified data
sources and how each dofile uses `downup_ac` (main regressor, moderator,
treatment-cell construction, or filter).

### Step 2 — Triage dofiles
Grep'd every dofile for `\bdownup_ac\b` to split into "swap" vs "skip" lists
(see Section 2). Confirmed special cases with the user before writing code.

### Step 3 — Set up new folder
```
code/_replication_rural_acpop/
├── estsave_csv.ado          (copied unchanged)
├── estload_csv.ado          (copied unchanged)
└── sbatch/
```

### Step 4 — Transform the 16 analysis dofiles
Used `sed -E` with word-boundary anchors so derived variables don't collide:

```bash
sed -E \
  -e 's/\bdownup_ac\b/downup_ac_pop/g' \
  -e 's/_rural\.ster/_rural_acpop.ster/g' \
  -e 's/_rural\.csv/_rural_acpop.csv/g' \
  -e 's/_rural\.dta/_rural_acpop.dta/g' \
  -e 's/_rural\.tex/_rural_acpop.tex/g' \
  ORIG.do > NEW.do
```

- `\bdownup_ac\b` matches the token only — `downup_ac_pop`, `downup_dummy`,
  `downup_pop_13km`, `downup_interaction`, etc. are **not** touched.
- Output filenames get `_acpop` at the very end of the rural stem (e.g.
  `main_did_downup_area_ac_rural.ster` → `main_did_downup_area_ac_rural_acpop.ster`).
- `_main_3`: `downup_dummy` (bureaucrat side) is intentionally left untouched.
  The interaction term becomes `downup_interaction = downup_ac_pop * downup_dummy`.
- Re-pointed three dofiles' `qui do ".../estsave_csv.ado"` reference from
  `_replication_rural` to `_replication_rural_acpop`.

### Step 5 — Inject `downup_ac_pop` merge for non-master datasets
Eight dofiles load data that does **not** already contain `downup_ac_pop`:

- `stacked_data_protest.csv`: `_main_4`, `_app_17`, `_app_18`
- `politicians_characteristics.csv`: `_main_5`, `_app_14`, `_app_15`, `_app_16`,
  `_app_19`

For each, a `preserve/restore` merge block was inserted right after the
`grids_with_more_1_ac` filter (the last pre-analysis merge):

```stata
preserve
import delimited "${root}/data_output/intermediate/0_master_merge_data_gen${sample}.csv", ///
    clear varnames(1)
keep unique_small_grid_id <KEYS> downup_ac_pop
duplicates drop unique_small_grid_id <KEYS>, force
tempfile downup_ac_pop_lookup
save `downup_ac_pop_lookup'
restore
merge m:1 unique_small_grid_id <KEYS> using `downup_ac_pop_lookup', ///
    keep(master match) keepusing(downup_ac_pop) nogen
```

**Merge keys per dataset** (chosen to match the columns that actually
exist in each dataset):

| Dataset                            | Merge keys                                   |
| ---------------------------------- | -------------------------------------------- |
| `stacked_data_protest.csv`         | `unique_small_grid_id`, `monthyear`          |
| `politicians_characteristics.csv`  | `unique_small_grid_id`, `year`, `month`      |

The protest dataset uses `monthyear` only (no separate `year`/`month`
columns); the politician dataset uses `year` and `month` directly (see
`_main_5` line 59: `gen date_ym = ym(year, month)`). The master CSV has
both, so `keep` is adjusted per file.

### Step 6 — Master orchestrator
Wrote `_master_replication.do` mirroring the original but pointing
`$code` to `_replication_rural_acpop` and listing only the 16 swapped
dofiles. Skipped sections are explained in the header comment.

### Step 7 — Table generator
Wrote `_generate_all_tables.do` to render 11 per-section
`_rural_acpop.tex` files (the same set the original generator renders,
minus `_app_6`, `_app_11`, `_app_12`, `_app_13` — and `_main_2` /
`_app_16-19`, which are event-study scripts that feed plot generation
rather than `esttab` rendering).

For sections whose `keep`/`varlabels` reference `downup_ac` directly
(`_main_1`, `_main_3`, `_app_7`, `_app_8`, `_app_9`, `_app_10`,
`_app_20`), those identifiers were updated to `downup_ac_pop`. Sections
that key off `1.post_#1.treat...` or `moderator` (an abstract handle)
were left as-is, since the underlying ster file already encodes the new
treatment.

### Step 8 — Side-by-side comparison document
The same generator appends one extra section that writes
`_comparison_downup_ac_vs_acpop${sample}.tex` into the Dropbox tables
folder. The document defines two boxed macros — `\OLD{...}` (red,
"ORIGINAL (downup_ac)") and `\NEW{...}` (green, "NEW (downup_ac_pop)") —
and emits one section per re-run analysis, each `\input`'ing both the
original `_rural.tex` and the new `_rural_acpop.tex`. Sections that
can't be found are flagged with `\IfFileExists{...}{...}{(missing)}`.
A `\clearpage` sits between sections so each comparison gets its own
page.

The output lives next to all the per-section tex files
(`${tables}/_comparison_downup_ac_vs_acpop${sample}.tex`), so the
relative `\input` paths just need bare filenames.

### Step 9 — HPC submission
Mirrored the original `sbatch/` folder one-for-one:

- 16 per-dofile `.sbatch` files + one for `_generate_all_tables.do`
- Same SGE preamble (`set -euo pipefail`, fresh `module purge && module load
  stata`, per-job `TMPDIR`, log-wipe before run)
- `CODE_DIR=/users/aquisper/proj_bureaucrats_farms/code/_replication_rural_acpop`
- Same core allocation as the originals (master_data=2, protest=10,
  politicians=5; generator=4)
- `submit_all_jobs.sh` `qsub`s all jobs grouped by data source

---

## 4. Folder layout

```
code/_replication_rural_acpop/
├── REPLICATION_PLAN.md                              ← this file
├── _master_replication.do                            ← orchestrator
├── _generate_all_tables.do                           ← renderer + comparison
├── estsave_csv.ado
├── estload_csv.ado
├── submit_all_jobs.sh
├── _main_1_did.do
├── _main_2_event_study.do
├── _main_3_bureau_polisc_did.do
├── _main_4_protest_5km_fe12_did_downup.do
├── _main_5_polischar_fe12_did_downup_inter.do
├── _app_7_main_did_downup_area_ac_dv.do
├── _app_8_main_did_by_year.do
├── _app_9_main_did_by_state.do
├── _app_10_did_rice_moderators.do
├── _app_14_polischar_fe12_did_ricemods.do
├── _app_15_polischar_fe12_did.do
├── _app_16_polischar_fe12_evst_all.do
├── _app_17_5km_fe12_evst_all.do
├── _app_18_protest_5km_fe12_did_downup_plot.do
├── _app_19_polischar_fe12_did_downup_inter_plot.do
├── _app_20_did_downwind_hm.do
└── sbatch/
    ├── main_1_did_rural.sbatch
    ├── main_2_event_study_rural.sbatch
    ├── main_3_bureau_polisc_did_rural.sbatch
    ├── main_4_protest_5km_fe12_did_downup_rural.sbatch
    ├── main_5_polischar_fe12_did_downup_inter_rural.sbatch
    ├── app_7_main_did_downup_area_ac_dv_rural.sbatch
    ├── app_8_main_did_by_year_rural.sbatch
    ├── app_9_main_did_by_state_rural.sbatch
    ├── app_10_did_rice_moderators_rural.sbatch
    ├── app_14_polischar_fe12_did_ricemods_rural.sbatch
    ├── app_15_polischar_fe12_did_rural.sbatch
    ├── app_16_polischar_fe12_evst_all_rural.sbatch
    ├── app_17_5km_fe12_evst_all_rural.sbatch
    ├── app_18_protest_5km_fe12_did_downup_plot.sbatch
    ├── app_19_polischar_fe12_did_downup_inter_plot.sbatch
    ├── app_20_did_downwind_hm_rural.sbatch
    └── generate_plots_tables_rural.sbatch
```

---

## 5. How to run

### On the cluster (analysis)

```bash
ssh <cluster>
cd /users/aquisper/proj_bureaucrats_farms/code/_replication_rural_acpop
./submit_all_jobs.sh
```

Wait for `qstat` to drain. Outputs:
`/users/aquisper/proj_bureaucrats_farms/tex/paper/tables/*_rural_acpop.ster`

Sync the ster files down via Dropbox.

### Locally (rendering tables + comparison PDF)

```bash
cd /Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_replication_rural_acpop
stata -b do _generate_all_tables.do
```

This writes, into `~/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/tables/`:

- 11 per-section `*_rural_acpop.tex` files
- `_comparison_downup_ac_vs_acpop.tex`

Compile the comparison PDF from that folder so the relative `\input` paths
resolve:

```bash
cd ~/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms/tex/paper/tables
pdflatex -interaction=nonstopmode _comparison_downup_ac_vs_acpop.tex
```

The comparison PDF expects the **original** `*_rural.tex` files to already
exist in the same folder. If any are missing, run the original
`_generate_all_tables.do` in `code/_replication_rural/` first to refresh
them. Missing files are flagged inline in the PDF instead of breaking the
compile.

---

## 6. Key decisions (and why)

1. **Word-boundary sed swap.** `\bdownup_ac\b` keeps `downup_ac_pop`,
   `downup_dummy`, `downup_pop_13km`, `downup_interaction`,
   `downup_diff_percent`, etc. untouched. Confirmed by diffing each
   transformed file against the original.

2. **`_main_3` interaction.** Only the politician side becomes
   `downup_ac_pop`; the bureaucrat treatment `downup_dummy` stays. The
   interaction is regenerated as
   `gen downup_interaction = downup_ac_pop * downup_dummy`.

3. **Output suffix at the very end.** `..._rural.ster` →
   `..._rural_acpop.ster` (likewise `.csv`, `.tex`, `.dta`). This keeps
   the original and new files side by side in the same Dropbox folder,
   sortable, and is the convention the comparison generator relies on.

4. **Merge keys per dataset.** `(unique_small_grid_id, monthyear)` for the
   protest dataset (it stores `monthyear` only); `(unique_small_grid_id,
   year, month)` for the politicians dataset. Merge uses
   `keep(master match) nogen` so unmatched master rows survive — the
   downstream regressions then drop missings automatically.

5. **Side-by-side document, not table-internal columns.** The user wanted
   the new and old results in one place; embedding both treatments into
   one esttab would have required regenerating original sters from a
   joint dofile and risked collisions in `keep()`/`varlabels()`.
   Instead, the comparison doc `\input`s the two already-rendered tex
   files in stacked red/green boxes per section — simpler, no
   cross-coupling between the original and acpop pipelines.

6. **Cluster sbatch parity.** Same core allocation, queue, preamble, and
   logging conventions as the original sbatch files. Job names use the
   `_acp` suffix to disambiguate from the original jobs in `qstat`.

---

## 7. Caveats

- The analysis assumes `downup_ac_pop` already exists as a column in
  `0_master_merge_data_gen${sample}.csv`. This is consistent with how
  `_app_6_main_did_treat_definition.do` already uses the variable.
- Politician-dataset merge assumes `year` and `month` are present. This is
  consistent with `_main_5` line 59 (`gen date_ym = ym(year, month)`).
- For the four skipped dofiles, the **original** `_rural.tex` outputs are
  still produced by the original pipeline. The comparison document only
  covers the 11 re-run sections.
