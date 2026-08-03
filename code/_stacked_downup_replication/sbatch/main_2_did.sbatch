#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_2_did
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _main_2_event_study.do
