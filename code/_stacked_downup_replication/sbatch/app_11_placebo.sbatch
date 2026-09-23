#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app_11_placebo
#$ -cwd

module load stata gcc
stata-mp -b do _app_11_placebo_pop_13km.do
