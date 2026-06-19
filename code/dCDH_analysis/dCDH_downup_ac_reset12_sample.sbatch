#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_reset12_sample
#$ -pe smp 5
#$ -cwd

export SAMPLE=_sample

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_reset12.py > dCDH_downup_ac_reset12_sample.out 2>&1
