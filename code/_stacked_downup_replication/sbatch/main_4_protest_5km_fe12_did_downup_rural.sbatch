#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -pe smp 10
#$ -N main_4_prt_rural
#$ -cwd
module load stata gcc
stata-mp -b do _main_4_protest_5km_fe12_did_downup.do
