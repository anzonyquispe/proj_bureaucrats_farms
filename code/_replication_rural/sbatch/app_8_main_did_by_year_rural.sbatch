#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app8_yr_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_8_main_did_by_year.do
