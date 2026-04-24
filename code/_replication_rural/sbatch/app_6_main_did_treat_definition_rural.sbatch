#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app6_trt_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_6_main_did_treat_definition.do
