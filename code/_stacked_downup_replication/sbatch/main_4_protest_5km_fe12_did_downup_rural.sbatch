#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_4_prt_rural
#$ -pe smp 10
#$ -cwd
module load stata gcc
stata-mp -b do _main_4_protest_5km_fe12_did_downup.do
