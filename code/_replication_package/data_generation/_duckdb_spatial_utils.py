#!/usr/bin/env python3
"""Shared DuckDB Spatial helpers for data-generation entry points."""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Sequence

import duckdb


CLUSTER_SA_ROOT = Path("/groups/sgulzar/sa_fires")
LOCAL_SA_ROOT = Path(r"C:\Users\eunic\Dropbox\sa_fires")


def default_sa_root() -> Path:
    configured = os.environ.get("SA_FIRES_ROOT")
    if configured:
        return Path(configured)
    if LOCAL_SA_ROOT.exists():
        return LOCAL_SA_ROOT
    return CLUSTER_SA_ROOT


def sql_string(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def qid(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def configure_duckdb(
    connection: duckdb.DuckDBPyConnection,
    *,
    threads: int,
    memory_limit: str,
    temp_directory: Path,
) -> None:
    temp_directory.mkdir(parents=True, exist_ok=True)
    connection.execute(f"SET threads = {max(1, int(threads))}")
    connection.execute(f"SET memory_limit = {sql_string(memory_limit)}")
    connection.execute(
        f"SET temp_directory = {sql_string(temp_directory.resolve())}"
    )
    connection.execute("SET preserve_insertion_order = false")


def load_spatial(connection: duckdb.DuckDBPyConnection) -> None:
    """Load DuckDB Spatial, installing it once when absent."""
    try:
        connection.execute("LOAD spatial")
        return
    except Exception as load_error:
        try:
            connection.execute("INSTALL spatial")
            connection.execute("LOAD spatial")
            return
        except Exception as install_error:
            raise RuntimeError(
                "DuckDB Spatial is required. Run `INSTALL spatial;` once in "
                "the same Python/DuckDB environment, then rerun this script."
            ) from install_error


def relation_columns(
    connection: duckdb.DuckDBPyConnection,
    relation: str,
) -> list[tuple[str, str]]:
    return [
        (str(row[0]), str(row[1]))
        for row in connection.execute(
            f"DESCRIBE SELECT * FROM {relation}"
        ).fetchall()
    ]


def require_columns(
    actual: Sequence[str],
    required: Sequence[str],
    label: str,
) -> None:
    actual_lookup = {column.lower() for column in actual}
    missing = [column for column in required if column.lower() not in actual_lookup]
    if missing:
        raise KeyError(f"{label} is missing columns: {', '.join(missing)}")


def find_column(columns: Sequence[str], candidates: Sequence[str]) -> str:
    lookup = {column.lower(): column for column in columns}
    for candidate in candidates:
        if candidate.lower() in lookup:
            return lookup[candidate.lower()]
    raise KeyError(
        "None of the expected columns exists: " + ", ".join(candidates)
    )


def create_grid_table(
    connection: duckdb.DuckDBPyConnection,
    grid_path: Path,
    *,
    table_name: str = "grids",
) -> list[str]:
    """Read a vector grid through ST_Read and normalize its grid ID."""
    relation = f"ST_Read({sql_string(grid_path.resolve())})"
    description = relation_columns(connection, relation)
    columns = [name for name, _ in description]
    geometry_candidates = [
        name for name, data_type in description if data_type.upper() == "GEOMETRY"
    ]
    if not geometry_candidates:
        geometry_candidates = [
            name for name in columns if name.lower() in {"geom", "geometry"}
        ]
    if len(geometry_candidates) != 1:
        raise ValueError(
            f"Expected one geometry column in {grid_path}; "
            f"found {geometry_candidates}."
        )
    geometry_column = geometry_candidates[0]
    grid_id_column = find_column(
        columns,
        ("unique_small_grid_id", "unq_s__", "unique_grid_id"),
    )
    attribute_columns = [
        column
        for column in columns
        if column not in {geometry_column, grid_id_column}
    ]
    attributes_sql = ""
    if attribute_columns:
        attributes_sql = ",\n            ".join(qid(c) for c in attribute_columns)
        attributes_sql += ",\n            "

    connection.execute(f"DROP TABLE IF EXISTS {qid(table_name)}")
    connection.execute(
        f"""
        CREATE TABLE {qid(table_name)} AS
        SELECT
            {attributes_sql}
            TRY_CAST({qid(grid_id_column)} AS BIGINT)
                AS unique_small_grid_id,
            {qid(geometry_column)} AS geometry
        FROM {relation}
        """
    )

    null_ids, duplicate_ids, null_geometries = connection.execute(
        f"""
        SELECT
            count_if(unique_small_grid_id IS NULL),
            (
                SELECT count(*)
                FROM (
                    SELECT unique_small_grid_id
                    FROM {qid(table_name)}
                    GROUP BY unique_small_grid_id
                    HAVING count(*) > 1
                )
            ),
            count_if(geometry IS NULL)
        FROM {qid(table_name)}
        """
    ).fetchone()
    if null_ids or duplicate_ids or null_geometries:
        raise ValueError(
            f"Invalid grid layer {grid_path}: null IDs={null_ids:,}, "
            f"duplicate IDs={duplicate_ids:,}, null geometries={null_geometries:,}."
        )
    connection.execute(f"ANALYZE {qid(table_name)}")
    return attribute_columns


def remove_exact_path(path: Path, allowed_parent: Path) -> None:
    resolved = path.resolve()
    parent = allowed_parent.resolve()
    if resolved == parent or parent not in resolved.parents:
        raise ValueError(f"Refusing to remove unsafe path: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    elif resolved.exists():
        resolved.unlink()


def prepare_outputs(
    *,
    output: Path,
    database: Path,
    temp_directory: Path,
    overwrite: bool,
) -> Path:
    output.parent.mkdir(parents=True, exist_ok=True)
    output_temp = output.with_name(output.name + ".tmp")
    candidates = [
        output,
        output_temp,
        database,
        Path(str(database) + ".wal"),
        temp_directory,
    ]
    existing = [path for path in candidates if path.exists()]
    if existing and not overwrite:
        raise FileExistsError(
            "Output/work paths exist; pass --overwrite:\n"
            + "\n".join(f"  {path}" for path in existing)
        )
    if overwrite:
        for path in existing:
            remove_exact_path(path, output.parent)
    temp_directory.mkdir(parents=True, exist_ok=True)
    return output_temp


def cleanup_work_files(
    *,
    database: Path,
    temp_directory: Path,
) -> None:
    for path in (database, Path(str(database) + ".wal"), temp_directory):
        if path.exists():
            remove_exact_path(path, database.parent)

