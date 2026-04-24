#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app13_pr_rural
#$ -pe smp 10
#$ -cwd
module load stata
stata-mp -b do _app_13_protest_5km_fe12_did_ricemods.do
