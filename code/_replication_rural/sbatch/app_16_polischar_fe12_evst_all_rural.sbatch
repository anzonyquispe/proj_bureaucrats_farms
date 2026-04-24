#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app16_ev_rural
#$ -pe smp 5
#$ -cwd
module load stata
stata-mp -b do _app_16_polischar_fe12_evst_all.do
