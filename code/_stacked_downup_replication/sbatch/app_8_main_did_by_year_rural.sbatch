#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_8_did_acp_stck
#$ -cwd

module load stata gcc
stata-mp -b do _app_8_main_did_by_year.do
