#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_4_prt_rural
#$ -pe smp 10
#$ -cwd
module load stata
stata-mp -b do _main_4_protest_5km_fe12_did_downup.do
