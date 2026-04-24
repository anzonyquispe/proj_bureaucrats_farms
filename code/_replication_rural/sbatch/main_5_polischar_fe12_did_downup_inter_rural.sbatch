#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_5_pol_rural
#$ -pe smp 5
#$ -cwd
module load stata
stata-mp -b do _main_5_polischar_fe12_did_downup_inter.do
