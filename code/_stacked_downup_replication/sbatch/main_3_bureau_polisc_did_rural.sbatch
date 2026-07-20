#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_3_did_acp_stck
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _main_3_bureau_polisc_did.do
