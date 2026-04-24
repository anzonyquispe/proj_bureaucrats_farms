#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app_19_polischar_fe12_did_downup_inter_plot
#$ -pe smp 10
#$ -cwd
module load stata
stata-mp -b do _app_19_polischar_fe12_did_downup_inter_plot.do
