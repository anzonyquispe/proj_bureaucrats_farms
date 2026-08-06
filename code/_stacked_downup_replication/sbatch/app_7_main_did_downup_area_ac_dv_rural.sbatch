#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_7_did_acp_stck
#$ -cwd

module load stata gcc
stata-mp -b do _app_7_main_did_downup_area_ac_dv.do
