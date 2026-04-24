#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app17_ev_rural
#$ -pe smp 10
#$ -cwd
module load stata
stata-mp -b do _app_17_5km_fe12_evst_all.do
