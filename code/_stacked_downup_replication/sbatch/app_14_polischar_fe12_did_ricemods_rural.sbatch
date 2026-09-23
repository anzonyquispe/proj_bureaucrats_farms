#!/bin/bash
#$ -M rj.barrera.fuentes@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app14_pc_rural
#$ -cwd
module load stata gcc
stata-mp -b do _app_14_polischar_fe12_did_ricemods.do
