#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_reset12_actrend
#$ -pe smp 60
#$ -cwd

export VARIANT=actrend

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_reset12.py > dCDH_downup_ac_reset12_actrend.out 2>&1
