#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_reset12
#$ -pe smp 20
#$ -cwd

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_reset12.py > dCDH_downup_ac_reset12.out 2>&1
