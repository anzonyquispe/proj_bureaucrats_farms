#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_5_pol_rural
#$ -cwd
module load stata gcc
stata-mp -b do _main_5_polischar_fe12_did_downup_inter.do
