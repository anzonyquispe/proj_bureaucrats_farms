#!/bin/bash
# qsub launcher -- mamoor
# Submit every sbatch file in this launcher to the cluster.
# All jobs write output to Anzonys personal folder on the shared group space;
# Ramiro and Mamoor must have read+write on that folder (ACL/umask configured).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
mkdir -p logs

FILES=(
    app17_set4_area.sbatch
    app17_set4_farzad.sbatch
    app16_set2_area.sbatch
    app16_set2_farzad.sbatch
    app19_farzad.sbatch
)

for sb in "${FILES[@]}"; do
    if [[ ! -f "$sb" ]]; then
        echo "MISSING: $sb" >&2; exit 1
    fi
    echo "qsub $sb"
    qsub "$sb"
done

echo "mamoor: submitted ${#FILES[@]} jobs."
