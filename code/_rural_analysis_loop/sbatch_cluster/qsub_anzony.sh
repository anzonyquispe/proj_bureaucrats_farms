#!/bin/bash
# qsub launcher -- anzony
# Submit every sbatch file in this launcher to the cluster.
# All jobs write output to Anzonys personal folder on the shared group space;
# Ramiro and Mamoor must have read+write on that folder (ACL/umask configured).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
mkdir -p logs

FILES=(
    app17_set1_area.sbatch
    app17_set1_farzad.sbatch
    app17_set2_area.sbatch
    app17_set2_farzad.sbatch
    app18_area.sbatch
    app18_farzad.sbatch
)

for sb in "${FILES[@]}"; do
    if [[ ! -f "$sb" ]]; then
        echo "MISSING: $sb" >&2; exit 1
    fi
    echo "qsub $sb"
    qsub "$sb"
done

echo "anzony: submitted ${#FILES[@]} jobs."
