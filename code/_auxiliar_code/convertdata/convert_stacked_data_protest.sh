#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N convert_stacked_data_protest
#$ -pe smp 10
#$ -cwd
module load stata
stata-mp -b do convert_stacked_data_protest.do
