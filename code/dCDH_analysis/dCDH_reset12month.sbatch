#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N dCDH_reset12month
#$ -pe smp 15
#$ -cwd

/groups/sgulzar/india_forest_land/did_stat/bin/python dCDH_reset12month_year.py > dCDH_reset12month_year.out 2>&1
