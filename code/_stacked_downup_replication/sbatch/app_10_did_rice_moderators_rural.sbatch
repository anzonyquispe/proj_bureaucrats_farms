#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N main_10_did_acp_stck
#$ -cwd

module load stata gcc
stata-mp -b do _app_10_did_rice_moderators.do
