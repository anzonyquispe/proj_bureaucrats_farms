# Executed `main.tex` replication-output audit

Audit target: `code/_report/main.tex`.

Only LaTeX that is actually executable is included. The audit excludes:

- text after an unescaped `%` comment marker;
- `comment` environments;
- disabled `\iffalse ... \fi` blocks; and
- everything after the first active `\end{document}` command, currently at
  line 2043.

This last rule matters here: the appendix-like material after line 2043 is not
compiled by LaTeX even though it contains uncommented-looking `\input` and
`\includegraphics` commands. Those references are therefore not replication
outputs and are not counted below.

## Audit totals

- Unique active references: 53
- References with located generating code: 43
- Static/external assets: 5
- Active outputs with no located generator: 5

## Active outputs with no located generating code

| `main.tex` line | Active output |
|---:|---|
| 587 | `tables/action_final5` |
| 603 | `tables/action_final6` |
| 619 | `tables/action_final7` |
| 635 | `tables/action_final8` |
| 2031 | `tables/action_final_additional_disha` |

No active figure output before the first `\end{document}` lacks a generator.

## Static or externally supplied assets

These active references are document assets rather than analysis outputs, so a
generating dofile is not expected:

- `figures/cnn.png`
- `figures/2020_Indian_farmers_protest.jpg`
- `figures/myneta_example2.png`
- `figures/rices_grids_150dpi_q75.pdf`
- `auxiliaries/preamble`

## New event-study control samples

Both `_app_16_polischar_fe12_evst_all.do` and
`_app_17_5km_fe12_evst_all.do` emit three estimate/CSV families for every
moderator and for both area and population-weighted treatment definitions:

| Filename suffix | Included observations |
|---|---|
| no control suffix | treated plus never treated (`control_type == 1`) |
| `_controls_both` | treated plus never treated plus not yet treated |
| `_controls_notyet` | treated plus not yet treated (`control_type == 2`) |

`plotting_event_studies.R` renders the original, detrended/rotated, HonestDiD,
and rotated-HonestDiD versions. Baseline filenames remain unchanged so current
active `main.tex` references continue to resolve.
