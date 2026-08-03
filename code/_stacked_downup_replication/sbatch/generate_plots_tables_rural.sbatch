##!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N generating_plots
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _generate_all_tables.do

