#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N politicians_stacked_descriptive
#$ -pe smp 5
#$ -cwd
module load gcc/15.2.0
module load R
R CMD BATCH --no-save --no-restore \
   _politicians_stacked_descriptive.R \
    politicians_stacked_descriptive.Rout