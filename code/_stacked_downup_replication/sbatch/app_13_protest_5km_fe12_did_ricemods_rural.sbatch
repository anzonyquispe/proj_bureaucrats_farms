#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -pe smp 10
#$ -N app13_pr_rural
#$ -cwd
module load stata gcc
stata-mp -b do _app_13_protest_5km_fe12_did_ricemods.do
