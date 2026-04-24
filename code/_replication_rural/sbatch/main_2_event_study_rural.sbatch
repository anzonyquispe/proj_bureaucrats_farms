#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_2_evst_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _main_2_event_study.do
