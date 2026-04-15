# proj_bureaucrats_farms

## Project overview

Empirical research project estimating the causal effect of **politicians / elected
representatives on agricultural fires** (primarily post-harvest crop burning) in
rural South Asia. The focus geography is North India — Punjab and Haryana — where
stubble burning drives seasonal air-pollution episodes.

## Research design

The analysis is a **stacked difference-in-differences / event-study** around
electoral cohorts, run at a fine spatial grid (≈5 km cells) crossed with assembly
constituencies (`unique_small_grid_id × ac_uq_id`). Treatment is defined at the
politician/constituency level; the outcome is fire counts (e.g. `countk`) derived
from remote-sensing detections, with weather controls (`wind_direction`,
`av_wind_speed`).

Key design features:
- Event time is measured in `relative_year_bin` around the election, with `-1` as
  the omitted base period.
- Heterogeneity is probed by interacting treatment with **moderators** such as
  rice area / rice production (`rice_moderators.dta`) and politician
  characteristics (`politicians_characteristics.csv`).
- Robustness is explored across a large grid of **fixed-effects specifications**
  (`fe1`…`fe30+`) combining grid-cohort, month-year-cohort, province-cohort time
  trends, government-year, and province × election-year FEs. The loop scripts run
  every spec so results can be compared in a single sweep.

## Repository layout

```
proj_bureaucrats_farms/
├── README.md
├── CLAUDE.md                     ← this file
└── code/
    ├── _auxiliar_code/
    │   └── convertdata/          # data-prep / format-conversion helpers
    └── _rural_analysis_loop/     # main Stata analysis scripts (.do)
        ├── 8_polischar_allagain.do            # politician-characteristics analysis
        ├── 10_pr_cluster_2022_5km_fe13_allspecs_evst.do  # 5km event-study sweep
        └── _app_*.do                           # appendix / robustness figures
```

Data lives **outside** the repo on a shared cluster path
(`/groups/sgulzar/sa_fires/proj_bureaucrats_farms/data_output/...`) or a local
Dropbox mirror; the `.do` files reference it via `${shell}` / `${dbox}` globals.
Intermediate datasets include `stacked_data_protest.csv`,
`rice_moderators.dta`, and `politicians_characteristics.csv`.

## Conventions

- Language: **Stata** (`.do` files). No Python/R pipeline in the repo itself.
- Script prefixes encode order (`8_`, `10_`) and appendix scripts use `_app_`.
- Fixed-effect specifications are enumerated as local macros `fe1…feN` and
  looped over, rather than hard-coded per script — preserve this pattern when
  adding new specs.
- The base event-time category is constructed dynamically from
  `relative_year_bin` so the omitted period is always `-1`.

## Standard requirements for event-study / DiD analysis dofiles

These requirements apply to **every** analysis dofile (event study or DiD) and
should be preserved when writing new scripts or editing existing ones.

1. **`ymean` is always the dep-var mean for the treated group pre-treatment.**
   Compute it as
   ```stata
   quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1
   local ymean = r(mean)
   ```
   Add any filter conditions (`& \`fcond'`) as needed, but the
   `treat == 1 & relative_year_bin <= -1` core must not change.

2. **Moderator structure is always present, even when unused.** Event-study
   dofiles (protest and polischar, rural or otherwise) must keep a
   `moderators_list` and wrap the regression in
   `foreach mod of local moderators_list`. The RHS must always use the
   triple-interaction form
   `ib\`base'.relative_year_bin_aux##ib0.treat##ib0.\`mod' wind_direction av_wind_speed`.
   When the analysis is intentionally run without heterogeneity (e.g. during FE
   selection), set `local moderators_list moderator` and `gen moderator = 0` so
   the triple interaction collapses to a plain event study while preserving the
   structure. Keep the original full list in a comment for easy reactivation:
   `* local moderators_list moderator downup_ac rice_area_aclvl_ahigh rice_harvarea_aclvl_ahigh rice_prod_aclvl_ahigh`.

3. **Always also save `ymean2` = treated-group pre-treatment mean when
   `moderator == 1`.** Compute it alongside `ymean`:
   ```stata
   quietly summarize `dep_var' if treat == 1 & relative_year_bin <= -1 & moderator == 1
   local ymean2 = r(mean)
   ```
   It may be missing in runs where `moderator` is a stub — that is fine, the
   wiring must still be in place.

4. **Numeric post-estimation quantities are saved as scalars, not locals.**
   Use `estadd scalar ymean = \`ymean'`, `estadd scalar ymean2 = \`ymean2'`,
   `estadd scalar acq = \`numacs'`. Keep `estadd local` only for string labels
   (`smpl`, `fespec`, `mod`, …). **Never use `sample` as an `estadd local`
   name** — it collides with Stata's reserved `e(sample)` and breaks
   `estwrite` with a `st_global 3300 out of range` error. Use `smpl` instead.

5. **`est store evreg\`i'` goes last in the loop body**, after all `estadd`
   scalars and locals, so the stored estimate carries every accumulated tag.

6. **Five parameters must be exposed for sbatch-array overrides.** Every
   analysis dofile is expected to be launched from an sbatch array that sets
   the following globals before calling Stata; the `if "$root" == ""` block
   only provides fallback defaults for standalone runs:

   | Global           | Values                                  | Used for                                           |
   | ---------------- | --------------------------------------- | -------------------------------------------------- |
   | `$location`      | `"shell"` \| `"dbox"`                   | selects the data root (`$shell` or `$dbox`)        |
   | `$sample`        | `""` \| `"_sample"`                     | suffix on input CSVs and output ster filenames     |
   | `$is_rural_var`  | `"is_rural_area"` \| `"is_rural_farzad"`| which rural classifier is used to filter the data  |
   | `$fe_list`       | any Stata numlist (e.g. `"1/32"`, `"12 13 19"`) | FE specs the regression loop iterates over |
   | `$ster_suffix`   | free-form string, default `""`          | appended to the output ster filename               |

   Implementation conventions:
   - Load **both** rural classifiers in the merge
     (`keepusing(is_rural_area is_rural_farzad)`) so either choice of
     `$is_rural_var` works without re-merging.
   - Filter with `keep if ${is_rural_var} == 1`.
   - The FE loop is `foreach fe of numlist $fe_list { ... }`.
   - The output path is
     `${root}/tex/paper/tables/<name>${sample}_rural${ster_suffix}.ster`.
   - Keep the `if "$root" == ""` standalone block as the single place where
     defaults for all five globals live, documented in one comment header.
