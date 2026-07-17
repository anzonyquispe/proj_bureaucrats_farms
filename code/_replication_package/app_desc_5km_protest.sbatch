#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app_desc_5km_protest
#$ -pe smp 10
#$ -cwd
module load gcc/15.2.0
module load R
R CMD BATCH --no-save --no-restore \
   _app_desc_5km_protest.R \
   _app_desc_5km_protest.Rout