#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app_18_protest_5km_fe12_did_downup_plot
#$ -pe smp 10
#$ -cwd
module load stata gcc
stata-mp -b do _app_18_protest_5km_fe12_did_downup_plot.do
