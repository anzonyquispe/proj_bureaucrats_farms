#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_1_did_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _main_1_did.do
