#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app17_ev_rural
#$ -pe smp 10
#$ -cwd
module load stata gcc
stata-mp -b do _app_17_5km_fe12_evst_all.do
