#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app7_dv_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_7_main_did_downup_area_ac_dv.do
