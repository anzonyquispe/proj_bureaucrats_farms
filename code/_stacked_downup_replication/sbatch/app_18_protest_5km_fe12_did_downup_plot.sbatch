#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -pe smp 10
#$ -N app_18_protest_5km_fe12_did_downup_plot
#$ -cwd
module load stata gcc
stata-mp -b do _app_18_protest_5km_fe12_did_downup_plot.do
