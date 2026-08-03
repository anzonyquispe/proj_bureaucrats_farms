#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_20_did_acp_stck
#$ -pe smp 2
#$ -cwd

module load stata gcc
stata-mp -b do _app_20_did_downwind_hm.do
