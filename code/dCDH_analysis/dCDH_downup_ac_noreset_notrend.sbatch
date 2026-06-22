#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_noreset_notrend
#$ -pe smp 60
#$ -cwd

export VARIANT=notrend

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_noreset.py > dCDH_downup_ac_noreset_notrend.out 2>&1
