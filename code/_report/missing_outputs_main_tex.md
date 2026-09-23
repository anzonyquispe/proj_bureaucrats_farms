# Missing outputs referenced by `main.tex`

Audit date: 2026-08-07

## Scope

This checklist covers active `\includegraphics{figures/...}` and
`\input{tables/...}` statements before `\end{document}` at line 2079. It
checks only the repository-level `figures/` and `tables/` folders used by the
local render.

- Missing active figures: **15**
- Missing active tables: **5**
- Total missing active assets: **20**

Commented LaTeX blocks are excluded. There are also 77 missing references
after `\end{document}` (66 figures and 11 tables). Those references are
dormant and do not affect the current report; review that legacy material only
if it will be moved back before `\end{document}`.

## Missing figures

| # | Expected path | `main.tex` | Intended content |
|---:|---|---:|---|
| 1 | `figures/cnn.png` | [line 130](main.tex#L130) | Gate of India during and after the smog season (`fig:delhi`) |
| 2 | `figures/map_grids.png` | [line 393](main.tex#L393) | Gridded dataset panel (`fig:gridsize`) |
| 3 | `figures/panel_A_downwind.png` | [line 400](main.tex#L400) | Treatment-definition panel A |
| 4 | `figures/panel_C_upwind.png` | [line 401](main.tex#L401) | Treatment-definition panel C |
| 5 | `figures/panel_B_downwind.png` | [line 402](main.tex#L402) | Treatment-definition panel B |
| 6 | `figures/march2013_plot.png` | [line 406](main.tex#L406) | Treatment variation in March 2013 |
| 7 | `figures/october2013_plot.png` | [line 407](main.tex#L407) | Treatment variation in October 2013 |
| 8 | `figures/neighbor_output.pdf` | [line 537](main.tex#L537) | Distance to upwind/downwind constituency border (`fig:neighbor_analysis`) |
| 9 | `figures/5km_plot.png` | [line 748](main.tex#L748) | Protest occurrence by location (`fig:map_protest`) |
| 10 | `figures/2020_Indian_farmers_protest.jpg` | [line 752](main.tex#L752) | Farmers' protest photograph (`fig:protest_photo`) |
| 11 | `figures/myneta_example2.png` | [line 882](main.tex#L882) | MyNeta profession example (`fig:self_profession_report`) |
| 12 | `figures/rices_grids_150dpi_q75.pdf` | [line 1113](main.tex#L1113) | Rice production map (`fig:map_crops`) |
| 13 | `figures/acs_grids_radius12km.png` | [line 1136](main.tex#L1136) | Placebo circle versus constituency border (`fig:prosociality_ex`) |
| 14 | `figures/protests_monthly_bars.png` | [line 1406](main.tex#L1406) | Number of protests over time (`fig:protest_by_time`) |
| 15 | `figures/ac_protest_plot.png` | [line 1426](main.tex#L1426) | Protest buffer versus constituency border (`fig:protest_construction`) |

## Missing tables

The expected files below should normally have the `.tex` extension in the
repository-level `tables/` folder.

| # | Expected path | `main.tex` | Intended content |
|---:|---|---:|---|
| 1 | `tables/action_final5.tex` | [line 623](main.tex#L623) | Political actions: fire count × downwind population |
| 2 | `tables/action_final6.tex` | [line 639](main.tex#L639) | Political actions: any fire × downwind population |
| 3 | `tables/action_final7.tex` | [line 655](main.tex#L655) | Rural political actions: fire count × downwind population |
| 4 | `tables/action_final8.tex` | [line 671](main.tex#L671) | Rural political actions: any fire × downwind population |
| 5 | `tables/action_final_additional_disha.tex` | [line 2067](main.tex#L2067) | Pollution exposure and politicians' actions, all categories (`tab:court_disha_app`) |

## Additional replication-package issue

The current approved asset folders do not contain a bibliography source. The
PDF can render, but citation keys remain unresolved. This is separate from the
20 missing figure/table outputs above.

