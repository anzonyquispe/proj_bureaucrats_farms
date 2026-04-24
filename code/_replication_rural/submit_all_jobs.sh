#!/bin/bash
################################################################################
# submit_all_jobs.sh
# Submits all RURAL replication do-file jobs to the cluster
# Core allocation: master_data=2, protest=10, politicians=5
################################################################################

echo "=============================================="
echo "SUBMITTING ALL RURAL REPLICATION JOBS"
echo "Date: $(date)"
echo "=============================================="

# Change to code directory
cd /users/aquisper/_replication_rural

echo ""
echo ">>> Master data jobs (2 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_1_did_rural.sbatch
qsub sbatch/main_2_event_study_rural.sbatch
qsub sbatch/main_3_bureau_polisc_did_rural.sbatch
qsub sbatch/app_6_main_did_treat_definition_rural.sbatch
qsub sbatch/app_7_main_did_downup_area_ac_dv_rural.sbatch
qsub sbatch/app_8_main_did_by_year_rural.sbatch
qsub sbatch/app_9_main_did_by_state_rural.sbatch
qsub sbatch/app_10_did_rice_moderators_rural.sbatch
qsub sbatch/app_11_placebo_pop_13km_rural.sbatch

echo ""
echo ">>> Protest data jobs (10 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_4_protest_5km_fe12_did_downup_rural.sbatch
qsub sbatch/app_12_protest_5km_fe_did_rural.sbatch
qsub sbatch/app_13_protest_5km_fe12_did_ricemods_rural.sbatch
qsub sbatch/app_17_5km_fe12_evst_all_rural.sbatch

echo ""
echo ">>> Politicians data jobs (5 cores each)..."
echo "----------------------------------------------"
qsub sbatch/main_5_polischar_fe12_did_downup_inter_rural.sbatch
qsub sbatch/app_14_polischar_fe12_did_ricemods_rural.sbatch
qsub sbatch/app_15_polischar_fe12_did_rural.sbatch
qsub sbatch/app_16_polischar_fe12_evst_all_rural.sbatch

echo ""
echo "=============================================="
echo "ALL RURAL JOBS SUBMITTED"
echo "Use 'qstat' to check job status"
echo "=============================================="
