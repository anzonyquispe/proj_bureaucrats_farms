#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app15_pc_rural
#$ -pe smp 5
#$ -cwd
module load stata
stata-mp -b do _app_15_polischar_fe12_did.do
