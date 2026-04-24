#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app9_st_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_9_main_did_by_state.do
