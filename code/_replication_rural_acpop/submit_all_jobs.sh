#!/bin/bash
################################################################################
# submit_all_jobs.sh  (acpop variant)
# Submits all RURAL × downup_ac_pop replication do-file jobs to the cluster.
# Core allocation mirrors the original: master_data=2, protest=10, politicians=5.
#
# Excluded (per project notes; nothing changes for them under downup_ac_pop):
#   - app_6_main_did_treat_definition  (already includes a downup_ac_pop col)
#   - app_11_placebo_pop_13km          (placebo, uses downup_pop_13km)
#   - app_12_protest_5km_fe_did        (does not use downup_ac)
#   - app_13_protest_5km_fe12_did_ricemods (does not use downup_ac)
################################################################################

echo "=============================================="
echo "SUBMITTING ALL RURAL × downup_ac_pop JOBS"
echo "Date: $(date)"
echo "=============================================="

# Change to code directory
cd /users/aquisper/proj_bureaucrats_farms/code/_replication_rural_acpop

echo ""
echo ">>> Master data jobs (2 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_1_did_rural.sbatch
qsub sbatch/main_2_event_study_rural.sbatch
qsub sbatch/main_3_bureau_polisc_did_rural.sbatch
qsub sbatch/app_7_main_did_downup_area_ac_dv_rural.sbatch
qsub sbatch/app_8_main_did_by_year_rural.sbatch
qsub sbatch/app_9_main_did_by_state_rural.sbatch
qsub sbatch/app_10_did_rice_moderators_rural.sbatch
qsub sbatch/app_20_did_downwind_hm_rural.sbatch

echo ""
echo ">>> Protest data jobs (10 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_4_protest_5km_fe12_did_downup_rural.sbatch
qsub sbatch/app_17_5km_fe12_evst_all_rural.sbatch
qsub sbatch/app_18_protest_5km_fe12_did_downup_plot.sbatch

echo ""
echo ">>> Politicians data jobs (5 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_5_polischar_fe12_did_downup_inter_rural.sbatch
qsub sbatch/app_14_polischar_fe12_did_ricemods_rural.sbatch
qsub sbatch/app_15_polischar_fe12_did_rural.sbatch
qsub sbatch/app_16_polischar_fe12_evst_all_rural.sbatch
qsub sbatch/app_19_polischar_fe12_did_downup_inter_plot.sbatch

echo ""
echo "=============================================="
echo "ALL RURAL × downup_ac_pop JOBS SUBMITTED"
echo "Use 'qstat' to check job status."
echo "After all jobs finish, locally run:"
echo "  stata -b do _generate_all_tables.do"
echo "to produce the per-section tex files AND the side-by-side"
echo "comparison document _comparison_downup_ac_vs_acpop.tex."
echo "=============================================="
