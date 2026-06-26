#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_downup_ac_pop_reset6_actrend_out
#$ -pe smp 60
#$ -cwd

export VARIANT=actrend
export SWITCHERS=out

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_downup_ac_pop_reset6.py > dCDH_downup_ac_pop_reset6_actrend_out.out 2>&1
