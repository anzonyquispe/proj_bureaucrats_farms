#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_pop_noreset_actrend_in
#$ -pe smp 60
#$ -cwd

export VARIANT=actrend
export SWITCHERS=in

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_pop_noreset.py > dCDH_downup_ac_pop_noreset_actrend_in.out 2>&1
