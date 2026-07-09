#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_reset6_notrend_in
#$ -pe smp 60
#$ -cwd

export VARIANT=notrend
export SWITCHERS=in

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_reset6.py > dCDH_downup_ac_reset6_notrend_in.out 2>&1
