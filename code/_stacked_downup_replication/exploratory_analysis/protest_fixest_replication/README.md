# Protest interaction: R/fixest replication

This independently reproduces the production Stata interaction model using
`fixest`. It enforces the same government term, `relative_year` definition,
`[-4, 1]` event window, complete pre/post grid-cohort histories, fixed effects,
and AC-election-cohort clustering.

The R formula deliberately excludes the standalone `post` and `treat` terms:
they are exactly absorbed by relative-year-by-cohort and grid-by-cohort fixed
effects, respectively. Stata omits them automatically. Explicit exclusion is
required in `fixest` here to avoid numerical near-collinearity in this very
large panel; all identified two- and three-way interaction terms remain.

Run a lightweight deterministic 1% unit sample first:

```powershell
& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" `
  "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms\code\_stacked_downup_replication\exploratory_analysis\protest_fixest_replication\replicate_protest_interaction_fixest.R" `
  --sample_share 0.01 --threads 6
```

Run the full replication by changing `--sample_share 0.01` to
`--sample_share 1`. The full file is large and may approach the memory limit of
a 32 GB computer; the streamed cache prevents the 29-column raw CSV from being
held in memory.

Outputs are written under
`tables/exploratory_analysis/protest_fixest_replication/`:

- interaction estimands with cluster-robust intervals and p-values;
- the complete `fixest` coefficient table;
- the model summary;
- a replication interaction plot.

The companion `compare_sample_stata.do` runs the exact compact validation
sample in Stata. It is intended as a cross-software audit: compare its three
`lincom` results with `control_post`, `treated_post`, and
`treated_minus_control_post` in the R audit CSV. A full-sample comparison must
use the same current stack and restrictions in both programs; older `.ster`
files are not a valid benchmark after the same-term/event-window changes.
