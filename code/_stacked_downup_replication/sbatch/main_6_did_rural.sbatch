#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_6_did_acp_stkd
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _app_6_main_did_treat_definition.do
