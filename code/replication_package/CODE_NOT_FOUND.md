# Active outputs without located generating code

This audit includes only uncommented `\input`, `\includegraphics`, and bibliography references in `code/_report/main.tex`. References inside `%` comments or `comment` environments are excluded.

- Unique active references: 143
- Covered by this replication package: 63
- Static/external assets: 5
- Generating code not found: 75

## Missing input code

- `tables/10_pr_cluster_2022_5kmtable` (main.tex lines 1931)
- `tables/_edit_pols_char_didtable` (main.tex lines 1841)
- `tables/ac_agriwork` (main.tex lines 2005)
- `tables/ac_myneta` (main.tex lines 2047)
- `tables/ac_rice` (main.tex lines 1963)
- `tables/action_final` (main.tex lines 481)
- `tables/action_final_additional_disha` (main.tex lines 1551)
- `tables/protest_10km` (main.tex lines 1618)
- `tables/protest_2km` (main.tex lines 1604)

## Missing figure code

- `figures/10_pr_cluster_2022_10km.png` (main.tex lines 1720)
- `figures/10_pr_cluster_2022_10km_pjhy.png` (main.tex lines 1756)
- `figures/10_pr_cluster_2022_10km_pjhy_spec2.png` (main.tex lines 1762)
- `figures/10_pr_cluster_2022_10km_pjhy_spec3.png` (main.tex lines 1768)
- `figures/10_pr_cluster_2022_10km_riceareas.png` (main.tex lines 1738)
- `figures/10_pr_cluster_2022_10km_riceareas_pjhy.png` (main.tex lines 1774)
- `figures/10_pr_cluster_2022_10km_riceareas_pjhy_spec2.png` (main.tex lines 1780)
- `figures/10_pr_cluster_2022_10km_riceareas_pjhy_spec3.png` (main.tex lines 1786)
- `figures/10_pr_cluster_2022_10km_riceareas_spec2.png` (main.tex lines 1744)
- `figures/10_pr_cluster_2022_10km_riceareas_spec3.png` (main.tex lines 1750)
- `figures/10_pr_cluster_2022_10km_spec2.png` (main.tex lines 1726)
- `figures/10_pr_cluster_2022_10km_spec3.png` (main.tex lines 1732)
- `figures/10_pr_cluster_2022_2km.png` (main.tex lines 1637)
- `figures/10_pr_cluster_2022_2km_pjhy.png` (main.tex lines 1673)
- `figures/10_pr_cluster_2022_2km_pjhy_spec2.png` (main.tex lines 1679)
- `figures/10_pr_cluster_2022_2km_pjhy_spec3.png` (main.tex lines 1685)
- `figures/10_pr_cluster_2022_2km_riceareas.png` (main.tex lines 1655)
- `figures/10_pr_cluster_2022_2km_riceareas_pjhy.png` (main.tex lines 1691)
- `figures/10_pr_cluster_2022_2km_riceareas_pjhy_spec2.png` (main.tex lines 1697)
- `figures/10_pr_cluster_2022_2km_riceareas_pjhy_spec3.png` (main.tex lines 1703)
- `figures/10_pr_cluster_2022_2km_riceareas_spec2.png` (main.tex lines 1661)
- `figures/10_pr_cluster_2022_2km_riceareas_spec3.png` (main.tex lines 1667)
- `figures/10_pr_cluster_2022_2km_spec2.png` (main.tex lines 1643)
- `figures/10_pr_cluster_2022_2km_spec3.png` (main.tex lines 1649)
- `figures/10_pr_cluster_2022_5km.png` (main.tex lines 1852)
- `figures/10_pr_cluster_2022_5km_pjhy.png` (main.tex lines 1888)
- `figures/10_pr_cluster_2022_5km_pjhy_spec2.png` (main.tex lines 1894)
- `figures/10_pr_cluster_2022_5km_pjhy_spec3.png` (main.tex lines 1900)
- `figures/10_pr_cluster_2022_5km_riceareas.png` (main.tex lines 1870)
- `figures/10_pr_cluster_2022_5km_riceareas_pjhy.png` (main.tex lines 1906)
- `figures/10_pr_cluster_2022_5km_riceareas_pjhy_spec2.png` (main.tex lines 1912)
- `figures/10_pr_cluster_2022_5km_riceareas_pjhy_spec3.png` (main.tex lines 1918)
- `figures/10_pr_cluster_2022_5km_riceareas_spec2.png` (main.tex lines 1876)
- `figures/10_pr_cluster_2022_5km_riceareas_spec3.png` (main.tex lines 1882)
- `figures/10_pr_cluster_2022_5km_spec2.png` (main.tex lines 1858)
- `figures/10_pr_cluster_2022_5km_spec3.png` (main.tex lines 1864)
- `figures/10km_plot.png` (main.tex lines 1591)
- `figures/2km_plot.png` (main.tex lines 1585)
- `figures/9_ac_treatment_level.png` (main.tex lines 2126)
- `figures/9_ac_treatment_level_pjhy.png` (main.tex lines 2162)
- `figures/9_ac_treatment_level_pjhy_spec2.png` (main.tex lines 2168)
- `figures/9_ac_treatment_level_pjhy_spec3.png` (main.tex lines 2174)
- `figures/9_ac_treatment_level_riceareas.png` (main.tex lines 2144)
- `figures/9_ac_treatment_level_riceareas_pjhy.png` (main.tex lines 2180)
- `figures/9_ac_treatment_level_riceareas_pjhy_spec2.png` (main.tex lines 2186)
- `figures/9_ac_treatment_level_riceareas_pjhy_spec3.png` (main.tex lines 2192)
- `figures/9_ac_treatment_level_riceareas_spec2.png` (main.tex lines 2150)
- `figures/9_ac_treatment_level_riceareas_spec3.png` (main.tex lines 2156)
- `figures/9_ac_treatment_level_spec2.png` (main.tex lines 2132)
- `figures/9_ac_treatment_level_spec3.png` (main.tex lines 2138)
- `figures/HONEST_eventStudy_estimates_acxminagri5.png` (main.tex lines 2032)
- `figures/HONEST_eventStudy_estimates_acxrice5.png` (main.tex lines 1990)
- `figures/NOT_ROTATED_eventStudy_acxminagri5.png` (main.tex lines 2019)
- `figures/NOT_ROTATED_eventStudy_acxrice5.png` (main.tex lines 1977)
- `figures/ROTATED_eventStudy_acxminagri5.png` (main.tex lines 2025)
- `figures/ROTATED_eventStudy_acxrice5.png` (main.tex lines 1983)
- `figures/ac_level_plot.png` (main.tex lines 1942)
- `figures/demonstrations_choropleth.png` (main.tex lines 2056)
- `figures/pr_on_polchar_spec19_rotated.png` (main.tex lines 1572)
- `figures/pr_on_polchar_spec1_rotated.png` (main.tex lines 1571)
- `figures/self_prof.png` (main.tex lines 1801)
- `figures/self_prof_assets.png` (main.tex lines 1817)
- `figures/self_prof_assets_spec2.png` (main.tex lines 1822)
- `figures/self_prof_assets_spec3.jpeg` (main.tex lines 1827)
- `figures/self_prof_spec2.png` (main.tex lines 1806)
- `figures/self_prof_spec3.jpeg` (main.tex lines 1811)

## Static or externally supplied assets

- `all_references` — bibliography source asset; not present in this repository snapshot
- `figures/2020_Indian_farmers_protest.jpg` — externally supplied photograph; not present in this repository snapshot
- `figures/cnn.png` — externally supplied illustration; not present in this repository snapshot
- `figures/rices_grids_150dpi_q75.pdf` — externally supplied/compressed map; not present in this repository snapshot
- `auxiliaries/preamble` — LaTeX source asset; not present in this repository snapshot

The machine-readable version, including every covered output and its package source, is `output_manifest.csv`.
