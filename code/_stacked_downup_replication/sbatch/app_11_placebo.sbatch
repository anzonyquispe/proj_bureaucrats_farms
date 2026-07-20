#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_1_did_acp_stkd
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _main_1_did.do
