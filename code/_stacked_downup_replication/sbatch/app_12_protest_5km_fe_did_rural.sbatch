#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -pe smp 10
#$ -N app12_prt_rural
#$ -cwd
module load stata gcc
stata-mp -b do _app_12_protest_5km_fe_did.do
