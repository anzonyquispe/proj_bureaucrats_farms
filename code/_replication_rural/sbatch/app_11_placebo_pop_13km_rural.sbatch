#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app11_pl_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_11_placebo_pop_13km.do
