#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_3_bur_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _main_3_bureau_polisc_did.do
