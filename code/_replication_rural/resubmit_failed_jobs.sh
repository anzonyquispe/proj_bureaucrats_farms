#!/bin/bash
################################################################################
# resubmit_failed_jobs.sh
# Re-submits only the jobs that failed to produce expected outputs
# Location: /groups/sgulzar/sa_fires/proj_bureaucrats_farms/code/_replication
################################################################################

echo "=============================================="
echo "RE-SUBMITTING FAILED JOBS"
echo "Date: $(date)"
echo "=============================================="

cd /groups/sgulzar/sa_fires/proj_bureaucrats_farms/code/_replication_rural

echo ""
echo ">>> Submitting failed jobs..."
echo "----------------------------------------------"

# Jobs with missing outputs (excluding _main_4 and _app_12 which completed)
qsub sbatch/main_4_protest_5km_fe12_did_downup_rural.sbatch
echo "  Submitted: main_4_protest_5km_fe12_did_downup_rural"

qsub sbatch/main_5_polischar_fe12_did_downup_inter_rural.sbatch
echo "  Submitted: main_5_polischar_fe12_did_downup_inter_rural"

qsub sbatch/app_12_protest_5km_fe_did_rural.sbatch
echo "  Submitted: app_12_protest_5km_fe_did_rural"

qsub sbatch/app_13_protest_5km_fe12_did_ricemods_rural.sbatch
echo "  Submitted: app_13_protest_5km_fe12_did_ricemods_rural"

qsub sbatch/app_14_polischar_fe12_did_ricemods_rural.sbatch
echo "  Submitted: app_14_polischar_fe12_did_ricemods_rural"

qsub sbatch/app_15_polischar_fe12_did_rural.sbatch
echo "  Submitted: app_15_polischar_fe12_did_rural"

qsub sbatch/app_18_protest_5km_fe12_did_downup_plot.sbatch
echo "  Submitted: app_18_protest_5km_fe12_did_downup_plot"

qsub sbatch/app_19_polischar_fe12_did_downup_inter_plot.sbatch
echo "  Submitted: app_19_polischar_fe12_did_downup_inter_plot"



echo ""
echo "=============================================="
echo "6 JOBS SUBMITTED"
echo "Use 'qstat' to check job status"
echo "=============================================="
