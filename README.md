# proj_bureaucrats_farms
This project has the code for the analysis of the effect of politicians on fires.

## Layout

| Path | Contents |
| --- | --- |
| `code/_replication_package/data_generation/` | Builds the master and stacked datasets (Python/DuckDB); entry point `build_master_and_stacked_datasets.sh` |
| `code/_stacked_downup_replication/` | Main analysis: estimations, tables, event-study and interaction plots, and figures for the paper and talks; entry point `_master_replication.do` (`sbatch/submit_all.sh` on the cluster) |
| `code/_replication_rural/` | Legacy area-based tables used only in the EGAP deck |
| `figures/`, `tables/` | Outputs used in the paper or talks, plus the saved estimates the table and plot scripts read |
| `docs/archive_manifest.csv` | Keep/archive decision and reason for every file in the cleanup |
| `docs/external_outputs.md` | Paper and talk outputs that no script in this repo generates |

## Archive
Code and outputs that the paper (`main.tex`) and the talks (APSA_short,
20260902_PECE_APSA, 20260515_EGAP) do not use were moved to `_archived/`. They
keep their original relative paths. Git ignores that folder, so the files exist
only locally and in git history.
