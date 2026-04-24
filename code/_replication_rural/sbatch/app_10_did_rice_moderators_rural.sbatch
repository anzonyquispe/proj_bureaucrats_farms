#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app10_rc_rural
#$ -pe smp 2
#$ -cwd
module load stata
stata-mp -b do _app_10_did_rice_moderators.do
