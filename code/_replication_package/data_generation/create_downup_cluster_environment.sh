#!/bin/bash

set -euo pipefail

ROOT="/users/aquisper/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_package/data_generation"
ENV_FILE="${CODE_DIR}/downup_cluster_environment.yml"
CONDA_SH="/afs/crc.nd.edu/x86_64_linux/c/conda/24.7.1/etc/profile.d/conda.sh"
ENV_PREFIX="${DOWNUP_ENV_PREFIX:-/groups/sgulzar/india_forest_land/downup_geo}"

if [[ ! -f "${CONDA_SH}" ]]; then
    echo "ERROR: conda initialization script was not found at ${CONDA_SH}." >&2
    exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: environment specification was not found at ${ENV_FILE}." >&2
    exit 1
fi

source "${CONDA_SH}"

if [[ -d "${ENV_PREFIX}/conda-meta" ]]; then
    echo "Updating existing environment: ${ENV_PREFIX}"
    conda env update \
        --prefix "${ENV_PREFIX}" \
        --file "${ENV_FILE}" \
        --prune
else
    echo "Creating environment: ${ENV_PREFIX}"
    conda env create \
        --prefix "${ENV_PREFIX}" \
        --file "${ENV_FILE}"
fi

conda activate "${ENV_PREFIX}"

python - <<'PY'
from pathlib import Path

import duckdb
import geopandas
import netCDF4
import numpy
import pandas
import pyarrow
import pyogrio
import pyproj
import shapely

proj_data = Path(pyproj.datadir.get_data_dir())
assert (proj_data / "proj.db").is_file()
pyproj.CRS.from_epsg(4326)
pyproj.CRS.from_epsg(7755)
transformer = pyproj.Transformer.from_crs(4326, 7755, always_xy=True)
x, y = transformer.transform(75.0, 30.0)
assert numpy.isfinite([x, y]).all()
projected = geopandas.GeoSeries(
    [shapely.Point(75.0, 30.0)], crs="EPSG:4326"
).to_crs("EPSG:7755")
assert numpy.isfinite([projected.x.iloc[0], projected.y.iloc[0]]).all()
connection = duckdb.connect()
try:
    connection.execute("LOAD spatial")
except Exception:
    connection.execute("INSTALL spatial")
    connection.execute("LOAD spatial")
assert connection.execute(
    "SELECT ST_AsText(ST_Point(75.0, 30.0))"
).fetchone()[0] == "POINT (75 30)"
connection.close()

print("Environment validation: PASS")
print("Python environment:", Path(__import__("sys").prefix))
print("DuckDB:", duckdb.__version__)
print("GeoPandas:", geopandas.__version__)
print("netCDF4:", netCDF4.__version__)
print("GDAL:", pyogrio.__gdal_version__)
print("pyproj:", pyproj.__version__)
print("PROJ:", pyproj.proj_version_str)
print("PROJ data:", proj_data)
print("Shapely:", shapely.__version__)
print("pandas:", pandas.__version__)
print("PyArrow:", pyarrow.__version__)
PY

echo "Environment is ready: ${ENV_PREFIX}"
