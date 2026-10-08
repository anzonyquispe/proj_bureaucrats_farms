#!/usr/bin/env python3
"""Build a balanced AC-month panel of protest exposure and politician profession.

Every dataset in this project lives at grid x cohort x month: the stacks repeat
each AC-month once per cohort it is eligible for, and carry ``treat``, ``post``
and ``control_type`` that only mean something inside their own cohort. Nothing
in the repo collapses to the constituency, and no ``post_protest`` or
``ever_protest`` variable exists anywhere. This builds that missing panel: one
row per ``ac_uq_id`` and calendar month, with three indicators.

    agricola      the sitting MLA of this electoral term is agricultural
    switch        this term replaced a non-agricultural MLA with an agricultural one
    post_protest  this AC is at or after a protest

Source
------
``0_master_dataset.parquet``, not the stacked files. The two stacks a caller
might reach for first are both derived from the master, so they add nothing;
both would have to be deduplicated over ``cohort_id``; and
``stacked_data_protest5km_election_sameterm.csv`` has no builder in the repo at
all. The master is balanced at AC-month, which is what makes the output panel
balanced by construction rather than by repair.

Electoral terms
---------------
``build_ac_terms`` is imported from the two-cycle builder rather than
reimplemented, so "electoral term", "agricultural" and the ordering of terms
within an AC mean here exactly what they mean in the stacked datasets. It keys
terms on ``term_start = year_take * 12 + month_take`` and already refuses to run
if the profession or the election year varies inside a term.

Terms are built from the FULL master and only the finished panel is cut to the
window. Building them from the cut master would renumber ``term_seq`` and shift
every lag.

``switch`` is missing, not zero, in an AC's first observed term
---------------------------------------------------------------
The master opens in 2012-09, so the term in force at that moment is
left-truncated and its predecessor is simply not in the data. Reporting ``0``
there would merge "no switch happened" with "cannot be known", and because the
2012-04 term covers roughly 55 of the 120 window months that would be close to
half the panel. ``switch_observable`` flags the distinction so it can be
filtered without guessing.

Note the SQL this forces. Writing the condition directly as
``prev_term_agricultural = 0 AND agricola = 1`` does NOT yield NULL for a first
term: three-valued logic turns ``NULL AND FALSE`` into FALSE, so every
first-term non-agricultural AC would silently come back as ``switch = 0``. The
``CASE WHEN term_seq = 1 THEN NULL`` below is what actually implements the rule.

Missing professions
-------------------
``self_profession_nomiss`` folds a missing profession into 0, non-agricultural
(build_0_master_dataset.py:241), so an AC can look like it switched merely
because the previous MLA's profession text was blank. The panel carries
``term_profession_missing`` and ``prev_term_profession_missing`` so those cases
stay identifiable, and ``--prior-term-missing-policy drop`` nulls the affected
switches outright.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
from typing import Sequence

import duckdb

from _stacked_duckdb_core import configure_connection, qid, qstr, source_expression
from build_all_stacked_datasets_duckdb import CLUSTER_INTERMEDIATE, LOCAL_INTERMEDIATE

# The electoral calendar is imported, not copied: this panel must describe the
# same terms the stacked datasets describe, and two near-identical copies would
# drift silently.
from build_politicians_characteristics_2cycles import (
    build_ac_terms,
    relation_columns,
    require_columns,
    scalar,
)

OUTPUT_STEM = "ac_month_panel"
PANEL_TABLE = "ac_month_panel"
SUMMARY_TABLE = "ac_month_panel_terms"

TREATMENT_COLUMN = "self_profession_nomiss"
PROTEST_COLUMN = "protest5km"

DEFAULT_END_YEAR = 2022
DEFAULT_END_MONTH = 8
DEFAULT_EXPECTED_ACS = 853
DEFAULT_EXPECTED_MONTHS = 120

REQUIRED_MASTER_COLUMNS = (
    "ac_uq_id",
    "province",
    "distr_id",
    "unique_small_grid_id",
    "year",
    "month",
    "monthyear",
    "year_take",
    "month_take",
    "election_year",
    "yeargov",
    TREATMENT_COLUMN,
    PROTEST_COLUMN,
)

OUTPUT_COLUMNS = (
    "ac_uq_id",
    "province",
    "distr_id_mode",
    "n_distr",
    "year",
    "month",
    "monthyear",
    "election_year",
    "year_take",
    "month_take",
    "term_start",
    "term_seq",
    "yeargov",
    "agricola",
    "switch",
    "switch_observable",
    "post_switch",
    "ever_switch",
    "post_protest",
    "share_grids_protest",
    "first_protest_monthyear",
    "prev_term_agricultural",
    "term_profession_missing",
    "prev_term_profession_missing",
    "n_grids",
)

# Stata truncates a variable name past 32 characters and pandas only warns, so
# the CSV and the .dta would disagree about what a column is called. Caught
# once by prev_term_self_profession_missing, which is 33.
_too_long = [name for name in OUTPUT_COLUMNS if len(name) > 32]
if _too_long:
    raise ValueError(f"Output columns too long for Stata: {', '.join(_too_long)}")

# Columns that are allowed to be NULL, and nothing else.
NULLABLE_COLUMNS = frozenset(
    {"switch", "prev_term_agricultural", "first_protest_monthyear"}
)

# pandas refuses nullable extension dtypes in to_stata; float64 NaN is what
# Stata reads back as a missing value.
STATA_FLOAT_COLUMNS = tuple(sorted(NULLABLE_COLUMNS))

STATA_VARIABLE_LABELS = {
    "ac_uq_id": "Assembly constituency identifier",
    "province": "Province",
    "distr_id_mode": "District holding most of the AC's grids",
    "n_distr": "Districts the AC spans (94 ACs straddle more than one)",
    "year": "Calendar year",
    "month": "Calendar month (1-12)",
    "monthyear": "year * 12 + month",
    "election_year": "Election year of the term in force",
    "year_take": "Year the assembly took office",
    "month_take": "Month the assembly took office",
    "term_start": "year_take * 12 + month_take",
    "term_seq": "Term order within the AC (1 = first observed)",
    "yeargov": "Year within the government term (1-5)",
    "agricola": "Agricultural MLA in this electoral term",
    "switch": "Term replaced a non-agricultural MLA with an agricultural one",
    "switch_observable": "Previous term is observable, so switch is defined",
    "post_switch": "At or after the AC's first observed switch",
    "ever_switch": "AC switches at some point, window or later",
    "post_protest": "At or after a protest within 5 km of any grid in the AC",
    "share_grids_protest": "Share of the AC's grids at or after a protest",
    "first_protest_monthyear": "First month with any protest in the AC",
    "prev_term_agricultural": "Previous term had an agricultural MLA",
    "term_profession_missing": "Profession text missing in this term",
    "prev_term_profession_missing": "Profession text missing in the previous term",
    "n_grids": "Grids in the AC that month",
}


def default_intermediate() -> Path:
    """Resolve the intermediate directory.

    ``LOCAL_INTERMEDIATE`` is one collaborator's Dropbox path, so it misses on
    every other machine and falls through to the cluster. ``PIPELINE_INTERMEDIATE``
    is honoured first so a local run needs one environment variable rather than
    an edit to the shared constant, which would change every builder's default.
    """

    override = os.environ.get("PIPELINE_INTERMEDIATE")
    if override:
        return Path(override)
    return LOCAL_INTERMEDIATE if LOCAL_INTERMEDIATE.exists() else CLUSTER_INTERMEDIATE


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--intermediate", type=Path, default=default_intermediate())
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Master Parquet/CSV; defaults to INTERMEDIATE/0_master_dataset.parquet.",
    )
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument(
        "--threads",
        type=int,
        default=max(1, int(os.environ.get("NSLOTS", os.cpu_count() or 1))),
    )
    parser.add_argument("--memory-limit", default="90GB")
    parser.add_argument("--csv-sample-size", type=int, default=100_000)
    parser.add_argument("--end-year", type=int, default=DEFAULT_END_YEAR)
    parser.add_argument("--end-month", type=int, default=DEFAULT_END_MONTH)
    parser.add_argument(
        "--prior-term-missing-policy",
        choices=["nonagricultural", "drop"],
        default="nonagricultural",
        help=(
            "How a missing profession in the previous term is treated. "
            "'nonagricultural' keeps the master's fold to 0; 'drop' nulls the "
            "switch so a blank profession cannot manufacture one."
        ),
    )
    parser.add_argument(
        "--expected-acs",
        type=int,
        default=DEFAULT_EXPECTED_ACS,
        help="Fail unless the panel has this many ACs. 0 disables the check.",
    )
    parser.add_argument(
        "--expected-months",
        type=int,
        default=DEFAULT_EXPECTED_MONTHS,
        help="Fail unless the panel has this many months. 0 disables the check.",
    )
    parser.add_argument(
        "--expected-rows",
        type=int,
        default=None,
        help="Defaults to expected-acs * expected-months. 0 disables the check.",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--log-level", choices=["DEBUG", "INFO", "WARNING"], default="INFO"
    )
    args = parser.parse_args(argv)
    if not 1 <= args.end_month <= 12:
        parser.error("--end-month must be between 1 and 12")
    if args.threads < 1:
        parser.error("--threads must be at least 1")
    for name in ("expected_acs", "expected_months"):
        if getattr(args, name) < 0:
            parser.error(f"--{name.replace('_', '-')} must not be negative")
    if args.expected_rows is None:
        args.expected_rows = args.expected_acs * args.expected_months
    elif args.expected_rows < 0:
        parser.error("--expected-rows must not be negative")
    return args


def fail_if(connection: duckdb.DuckDBPyConnection, query: str, message: str) -> None:
    """Raise with the offending row count when a validation query returns one."""

    count = scalar(connection, query)
    if count:
        raise ValueError(message.format(count=f"{count:,}"))


def build_ac_month_skeleton(connection: duckdb.DuckDBPyConnection, master_sql: str) -> None:
    """Collapse the grid-month master to AC-month over the FULL time range.

    ``post_protest`` is the maximum of ``protest5km`` over the AC's grids: the AC
    has experienced a protest once any of its grids is within 5 km of one. Each
    grid's series is already absorbing, so the maximum is too; the validation
    checks that rather than assuming it.

    The ``n_*`` counts exist to be asserted on. Collapsing silently would hide a
    grid whose AC-month disagrees with its neighbours about which term is in
    force, which is exactly the failure that would corrupt ``agricola``.
    """

    connection.execute(
        f"""
        CREATE TEMP TABLE ac_month AS
        SELECT
            CAST(ac_uq_id AS BIGINT)                          AS ac_uq_id,
            CAST(monthyear AS BIGINT)                         AS monthyear,
            min(CAST(year AS INTEGER))                        AS year,
            min(CAST(month AS TINYINT))                       AS month,
            max(CAST({qid(PROTEST_COLUMN)} AS TINYINT))       AS post_protest,
            avg(CAST({qid(PROTEST_COLUMN)} AS DOUBLE))        AS share_grids_protest,
            count_if({qid(PROTEST_COLUMN)} IS NULL)           AS protest_nulls,
            min(CAST(year_take AS BIGINT) * 12
                + CAST(month_take AS BIGINT))                 AS term_start,
            count(DISTINCT CAST(year_take AS BIGINT) * 12
                + CAST(month_take AS BIGINT))                 AS n_term_starts,
            min(CAST(year_take AS INTEGER))                   AS year_take,
            min(CAST(month_take AS TINYINT))                  AS month_take,
            max(TRY_CAST(election_year AS INTEGER))           AS election_year,
            count(DISTINCT election_year)                     AS n_election_years,
            max(TRY_CAST(yeargov AS INTEGER))                 AS yeargov,
            count(DISTINCT yeargov)                           AS n_yeargov,
            max(CAST({qid(TREATMENT_COLUMN)} AS TINYINT))     AS agricola_direct,
            count(DISTINCT {qid(TREATMENT_COLUMN)})           AS n_profession_values,
            count(DISTINCT unique_small_grid_id)              AS n_grids,
            any_value(province)                               AS province,
            count(DISTINCT province)                          AS n_provinces,
            count(DISTINCT distr_id)                          AS n_distr_month
        FROM {master_sql}
        WHERE year_take IS NOT NULL AND month_take IS NOT NULL
        GROUP BY ac_uq_id, monthyear
        """
    )

    connection.execute(
        f"""
        CREATE TEMP TABLE ac_month_districts AS
        SELECT ac_uq_id, monthyear,
               list_sort(list(DISTINCT CAST(distr_id AS BIGINT))) AS districts
        FROM {master_sql}
        WHERE year_take IS NOT NULL AND month_take IS NOT NULL
        GROUP BY ac_uq_id, monthyear
        """
    )

    fail_if(
        connection,
        "SELECT coalesce(sum(protest_nulls), 0) FROM ac_month",
        f"{PROTEST_COLUMN} is NULL on {{count}} master rows.",
    )
    for column, label in (
        ("n_provinces", "province"),
        ("n_term_starts", "term start"),
        ("n_election_years", "election year"),
        ("n_yeargov", "yeargov"),
        ("n_profession_values", "profession"),
    ):
        fail_if(
            connection,
            f"SELECT count(*) FROM ac_month WHERE {column} <> 1",
            f"{{count}} AC-months carry more than one {label}.",
        )
    # Not fatal: 1,962 grids are reassigned to a different district at some
    # point in the master, which moves the district set of 16 ACs. That is a
    # property of the upstream data, not of this panel, and it is the reason
    # distr_id_mode is resolved once over the whole master rather than per
    # AC-month. Reported so it stays visible.
    drifting = scalar(
        connection,
        """
        SELECT count(*) FROM (
            SELECT ac_uq_id FROM ac_month_districts
            GROUP BY ac_uq_id
            HAVING count(DISTINCT districts) <> 1
        )
        """,
    )
    if drifting:
        logging.warning(
            "%s ACs change WHICH districts they span between months; "
            "distr_id_mode is resolved once over the whole master so the label "
            "does not move with them.",
            f"{drifting:,}",
        )
    fail_if(
        connection,
        "SELECT count(*) FROM ac_month WHERE monthyear < term_start",
        "{count} AC-months fall before the term they are assigned to.",
    )
    fail_if(
        connection,
        """
        SELECT count(*) FROM (
            SELECT ac_uq_id, monthyear, post_protest,
                   lag(post_protest) OVER (
                       PARTITION BY ac_uq_id ORDER BY monthyear
                   ) AS previous
            FROM ac_month
        )
        WHERE previous = 1 AND post_protest = 0
        """,
        "post_protest reverses from 1 to 0 on {count} AC-months.",
    )
    # One term per election. A by-election would create a second term_start
    # inside an election year, and switch would then fire on a turnover that is
    # not electoral at all.
    fail_if(
        connection,
        """
        SELECT count(*) FROM (
            SELECT ac_uq_id, election_year
            FROM ac_month
            GROUP BY ac_uq_id, election_year
            HAVING count(DISTINCT term_start) <> 1
        )
        """,
        "{count} AC election years span more than one term start.",
    )

    acs = scalar(connection, "SELECT count(DISTINCT ac_uq_id) FROM ac_month")
    months = scalar(connection, "SELECT count(DISTINCT monthyear) FROM ac_month")
    rows = scalar(connection, "SELECT count(*) FROM ac_month")
    logging.info(
        "AC-month skeleton: %s rows, %s ACs, %s months",
        f"{rows:,}",
        f"{acs:,}",
        f"{months:,}",
    )


def build_ac_district(connection: duckdb.DuckDBPyConnection, master_sql: str) -> None:
    """Pick one district per AC, once, over the whole master.

    94 of the 853 ACs straddle a district boundary, so ``distr_id`` is a
    property of the grid and not of the constituency. The AC is labelled with
    the district holding most of its grids, and ``n_distr`` keeps the rest
    visible rather than hidden.

    The tie-break on ``distr_id`` is not cosmetic. 13 ACs split evenly between
    two districts, and DuckDB's ``mode()`` resolves a tie arbitrarily, so the
    label flipped from month to month when this was computed per AC-month.
    Computing it once, with a deterministic order, is both stable and closer to
    what the column means.
    """

    connection.execute(
        f"""
        CREATE TEMP TABLE ac_district AS
        SELECT ac_uq_id, distr_id_mode, n_distr
        FROM (
            SELECT
                CAST(ac_uq_id AS BIGINT)        AS ac_uq_id,
                CAST(distr_id AS BIGINT)        AS distr_id_mode,
                count(*) OVER (PARTITION BY ac_uq_id) AS n_distr,
                row_number() OVER (
                    PARTITION BY ac_uq_id
                    ORDER BY count(DISTINCT unique_small_grid_id) DESC,
                             CAST(distr_id AS BIGINT)
                )                                AS rank_in_ac
            FROM {master_sql}
            GROUP BY ac_uq_id, distr_id
        )
        WHERE rank_in_ac = 1
        """
    )
    spanning = scalar(
        connection, "SELECT count(*) FROM ac_district WHERE n_distr > 1"
    )
    logging.info("ACs spanning more than one district: %s", f"{spanning:,}")


def attach_terms(connection: duckdb.DuckDBPyConnection) -> None:
    """Join ``ac_terms_ranked`` onto the skeleton on the exact term key.

    The term in force is already on every master row through ``year_take`` and
    ``month_take``, so this is an equi-join rather than the ASOF join the stack
    builders need. That is the stronger choice: a term that failed to match
    shows up as a NULL instead of being silently rolled back to the previous one.
    """

    connection.execute(
        """
        CREATE TEMP TABLE ac_month_terms AS
        SELECT
            m.*,
            CAST(t.term_seq AS INTEGER)                 AS term_seq,
            CAST(t.agricultural AS TINYINT)             AS agricola,
            t.election_year                             AS term_election_year,
            t.self_profession_missing,
            t.prev_term_start,
            CAST(t.prev_term_agricultural AS TINYINT)   AS prev_term_agricultural,
            t.prev_term_self_profession_missing
        FROM ac_month AS m
        LEFT JOIN ac_terms_ranked AS t USING (ac_uq_id, term_start)
        """
    )
    connection.execute(
        """
        CREATE TEMP TABLE ac_month_terms_district AS
        SELECT a.*, d.distr_id_mode, CAST(d.n_distr AS INTEGER) AS n_distr
        FROM ac_month_terms AS a
        JOIN ac_district AS d USING (ac_uq_id)
        """
    )
    connection.execute("DROP TABLE ac_month_terms")
    connection.execute(
        "ALTER TABLE ac_month_terms_district RENAME TO ac_month_terms"
    )

    fail_if(
        connection,
        "SELECT count(*) FROM ac_month_terms WHERE term_seq IS NULL",
        "{count} AC-months matched no electoral term.",
    )
    fail_if(
        connection,
        """
        SELECT count(*) FROM ac_month_terms
        WHERE agricola IS DISTINCT FROM agricola_direct
        """,
        "{count} AC-months disagree with their term about the MLA's profession.",
    )
    fail_if(
        connection,
        """
        SELECT count(*) FROM ac_month_terms
        WHERE term_election_year IS DISTINCT FROM election_year
        """,
        "{count} AC-months disagree with their term about the election year.",
    )


def build_panel(
    connection: duckdb.DuckDBPyConnection,
    table: str,
    end_monthyear: int,
    missing_policy: str,
) -> None:
    """Derive switch, add the protest onset, and cut to the window.

    The window is applied here and nowhere earlier, so the protest history and
    the term sequence are both complete before anything is dropped.
    """

    # Under 'drop' a switch out of a term whose profession text was blank is
    # unknowable rather than false, so it is nulled alongside the first term.
    unobservable = "a.term_seq = 1"
    if missing_policy == "drop":
        unobservable += " OR a.prev_term_self_profession_missing"

    connection.execute(
        f"""
        CREATE TABLE {qid(table)} AS
        WITH first_protest AS (
            SELECT ac_uq_id, min(monthyear) AS first_protest_monthyear
            FROM ac_month
            WHERE post_protest = 1
            GROUP BY ac_uq_id
        ),
        -- Drawn from the full term table, so an AC whose only switch falls
        -- after the window still reads ever_switch = 1 while every one of its
        -- in-window rows has switch = 0. Three ACs are in that position.
        switch_terms AS (
            SELECT ac_uq_id, min(term_start) AS first_switch_term_start
            FROM ac_terms_ranked
            WHERE term_seq > 1
              AND prev_term_agricultural = 0
              AND agricultural = 1
            GROUP BY ac_uq_id
        )
        SELECT
            a.ac_uq_id,
            a.province,
            a.distr_id_mode,
            a.n_distr,
            a.year,
            a.month,
            a.monthyear,
            a.election_year,
            a.year_take,
            a.month_take,
            a.term_start,
            a.term_seq,
            a.yeargov,
            a.agricola,
            -- NOT written as (prev_term_agricultural = 0 AND agricola = 1):
            -- NULL AND FALSE is FALSE, which would report switch = 0 for a
            -- first term instead of leaving it unknown.
            CASE
                WHEN {unobservable} THEN NULL
                ELSE CAST(
                    (a.prev_term_agricultural = 0 AND a.agricola = 1) AS TINYINT
                )
            END                                                 AS switch,
            CASE WHEN {unobservable} THEN 0 ELSE 1 END::TINYINT AS switch_observable,
            CAST(
                s.first_switch_term_start IS NOT NULL
                AND a.term_start >= s.first_switch_term_start AS TINYINT
            )                                                   AS post_switch,
            CAST(s.first_switch_term_start IS NOT NULL AS TINYINT) AS ever_switch,
            a.post_protest,
            a.share_grids_protest,
            f.first_protest_monthyear,
            a.prev_term_agricultural,
            CAST(coalesce(a.self_profession_missing, FALSE) AS TINYINT)
                                                                AS term_profession_missing,
            CAST(coalesce(a.prev_term_self_profession_missing, FALSE) AS TINYINT)
                                                                AS prev_term_profession_missing,
            CAST(a.n_grids AS INTEGER)                          AS n_grids
        FROM ac_month_terms AS a
        LEFT JOIN first_protest AS f USING (ac_uq_id)
        LEFT JOIN switch_terms AS s USING (ac_uq_id)
        WHERE a.monthyear <= {int(end_monthyear)}
        """
    )


def validate_panel(
    connection: duckdb.DuckDBPyConnection,
    table: str,
    end_monthyear: int,
    missing_policy: str,
    expected_acs: int,
    expected_months: int,
    expected_rows: int,
) -> None:
    quoted = qid(table)

    fail_if(
        connection,
        f"""
        SELECT count(*) FROM (
            SELECT ac_uq_id, year, month FROM {quoted}
            GROUP BY ALL HAVING count(*) <> 1
        )
        """,
        "{count} AC-year-month keys are duplicated.",
    )
    # Balance as a set difference, not only as a row count: a panel can hit the
    # right total while being short a month in one AC and long in another.
    fail_if(
        connection,
        f"""
        SELECT count(*) FROM (
            SELECT ac_uq_id, monthyear
            FROM (SELECT DISTINCT ac_uq_id FROM {quoted})
            CROSS JOIN (SELECT DISTINCT monthyear FROM {quoted})
            EXCEPT
            SELECT ac_uq_id, monthyear FROM {quoted}
        )
        """,
        "{count} AC-month cells are missing; the panel is not balanced.",
    )

    for column in OUTPUT_COLUMNS:
        if column in NULLABLE_COLUMNS:
            continue
        fail_if(
            connection,
            f"SELECT count_if({qid(column)} IS NULL) FROM {quoted}",
            f"{{count}} rows have a NULL {column}.",
        )

    unobservable = "term_seq = 1"
    if missing_policy == "drop":
        unobservable += " OR prev_term_profession_missing = 1"
    fail_if(
        connection,
        f"""
        SELECT count_if((switch IS NULL) <> ({unobservable})) FROM {quoted}
        """,
        "{count} rows disagree about whether switch is knowable.",
    )
    fail_if(
        connection,
        f"SELECT count_if((switch_observable = 0) <> ({unobservable})) FROM {quoted}",
        "{count} rows have switch_observable out of step with switch.",
    )

    # Both indicators are term attributes; variation inside a term would mean
    # the join to ac_terms_ranked fanned out.
    fail_if(
        connection,
        f"""
        SELECT count(*) FROM (
            SELECT ac_uq_id, term_start FROM {quoted}
            GROUP BY ac_uq_id, term_start
            HAVING count(DISTINCT agricola) <> 1
                OR count(DISTINCT switch) > 1
                OR (count(switch) <> 0 AND count(switch) <> count(*))
        )
        """,
        "{count} terms vary in agricola or switch across their own months.",
    )

    fail_if(
        connection,
        f"""
        SELECT count(*) FROM (
            SELECT ac_uq_id, monthyear, post_protest,
                   lag(post_protest) OVER (
                       PARTITION BY ac_uq_id ORDER BY monthyear
                   ) AS previous
            FROM {quoted}
        )
        WHERE previous = 1 AND post_protest = 0
        """,
        "post_protest reverses from 1 to 0 on {count} rows of the panel.",
    )

    fail_if(
        connection,
        f"""
        SELECT count(*) FROM {quoted}
        WHERE agricola NOT IN (0, 1)
           OR post_protest NOT IN (0, 1)
           OR (switch IS NOT NULL AND switch NOT IN (0, 1))
           OR month NOT BETWEEN 1 AND 12
           OR share_grids_protest NOT BETWEEN 0 AND 1
        """,
        "{count} rows fall outside the declared domains.",
    )

    maximum = scalar(connection, f"SELECT max(monthyear) FROM {quoted}")
    if maximum != end_monthyear:
        raise ValueError(
            f"The panel ends at monthyear {maximum}, expected {end_monthyear}."
        )

    acs = scalar(connection, f"SELECT count(DISTINCT ac_uq_id) FROM {quoted}")
    months = scalar(connection, f"SELECT count(DISTINCT monthyear) FROM {quoted}")
    rows = scalar(connection, f"SELECT count(*) FROM {quoted}")
    for observed, expected, label in (
        (acs, expected_acs, "ACs"),
        (months, expected_months, "months"),
        (rows, expected_rows, "rows"),
    ):
        if expected and observed != expected:
            raise ValueError(
                f"The panel has {observed:,} {label}, expected {expected:,}."
            )


def log_composition(connection: duckdb.DuckDBPyConnection, table: str) -> None:
    """Report the numbers worth seeing before anyone regresses on this panel."""

    quoted = qid(table)
    rows = scalar(connection, f"SELECT count(*) FROM {quoted}")
    acs = scalar(connection, f"SELECT count(DISTINCT ac_uq_id) FROM {quoted}")
    months = scalar(connection, f"SELECT count(DISTINCT monthyear) FROM {quoted}")
    logging.info("Panel: %s rows, %s ACs, %s months", f"{rows:,}", f"{acs:,}", f"{months:,}")

    unknown = scalar(connection, f"SELECT count_if(switch IS NULL) FROM {quoted}")
    logging.info(
        "switch unknown on %s rows (%.1f%%), all in an AC's first observed term",
        f"{unknown:,}",
        100.0 * unknown / rows if rows else 0.0,
    )
    for value, label in ((1, "switch = 1"), (0, "switch = 0")):
        count = scalar(connection, f"SELECT count_if(switch = {value}) FROM {quoted}")
        logging.info("%s on %s rows", label, f"{count:,}")

    ever = scalar(connection, f"SELECT count(DISTINCT ac_uq_id) FROM {quoted} WHERE ever_switch = 1")
    logging.info("ACs that switch at some point: %s", f"{ever:,}")

    protest_rows = scalar(connection, f"SELECT count_if(post_protest = 1) FROM {quoted}")
    protest_acs = scalar(
        connection, f"SELECT count(DISTINCT ac_uq_id) FROM {quoted} WHERE post_protest = 1"
    )
    first = scalar(connection, f"SELECT min(first_protest_monthyear) FROM {quoted}")
    logging.info(
        "post_protest = 1 on %s rows across %s ACs; first protest month %s",
        f"{protest_rows:,}",
        f"{protest_acs:,}",
        first,
    )

    spurious = scalar(
        connection,
        f"""
        SELECT count(DISTINCT ac_uq_id) FROM {quoted}
        WHERE switch = 1 AND prev_term_profession_missing = 1
        """,
    )
    if spurious:
        logging.warning(
            "%s ACs switch out of a term whose profession text was blank; "
            "rerun with --prior-term-missing-policy drop to null those.",
            f"{spurious:,}",
        )

    for row in connection.execute(
        f"""
        SELECT term_seq, count(DISTINCT ac_uq_id) AS acs, count(*) AS rows
        FROM {quoted} GROUP BY term_seq ORDER BY term_seq
        """
    ).fetchall():
        logging.info("term_seq %s: %s ACs, %s rows", row[0], f"{row[1]:,}", f"{row[2]:,}")


def write_summary(connection: duckdb.DuckDBPyConnection, table: str, summary: str) -> None:
    """One row per AC term: the panel's content without the monthly repetition."""

    connection.execute(
        f"""
        CREATE TABLE {qid(summary)} AS
        SELECT
            ac_uq_id,
            term_start,
            any_value(term_seq)                       AS term_seq,
            any_value(election_year)                  AS election_year,
            any_value(agricola)                       AS agricola,
            any_value(switch)                         AS switch,
            any_value(switch_observable)              AS switch_observable,
            count(*)                                  AS months_in_window,
            any_value(term_profession_missing)        AS term_profession_missing,
            any_value(prev_term_profession_missing)   AS prev_term_profession_missing,
            any_value(first_protest_monthyear)        AS first_protest_monthyear,
            count_if(post_protest = 1)                AS post_protest_months
        FROM {qid(table)}
        GROUP BY ac_uq_id, term_start
        """
    )


def write_outputs(
    connection: duckdb.DuckDBPyConnection,
    table: str,
    summary: str,
    output_csv: Path,
    output_dta: Path,
    summary_csv: Path,
) -> None:
    columns = ", ".join(qid(name) for name in OUTPUT_COLUMNS)
    # configure_connection disables preserve_insertion_order, so without an
    # explicit ORDER BY consecutive runs produce diff-noisy CSVs.
    order = "ORDER BY ac_uq_id, monthyear"

    csv_temp = output_csv.with_name(output_csv.name + ".tmp")
    connection.execute(
        f"""
        COPY (SELECT {columns} FROM {qid(table)} {order})
        TO {qstr(csv_temp)} (FORMAT CSV, HEADER TRUE)
        """
    )
    os.replace(csv_temp, output_csv)

    summary_temp = summary_csv.with_name(summary_csv.name + ".tmp")
    connection.execute(
        f"""
        COPY (SELECT * FROM {qid(summary)} ORDER BY ac_uq_id, term_start)
        TO {qstr(summary_temp)} (FORMAT CSV, HEADER TRUE)
        """
    )
    os.replace(summary_temp, summary_csv)

    frame = connection.execute(
        f"SELECT {columns} FROM {qid(table)} {order}"
    ).df()
    for column in STATA_FLOAT_COLUMNS:
        frame[column] = frame[column].astype("float64")
    dta_temp = output_dta.with_name(output_dta.name + ".tmp")
    frame.to_stata(
        dta_temp,
        write_index=False,
        version=118,
        data_label="AC-month panel: protest exposure and MLA profession",
        variable_labels=STATA_VARIABLE_LABELS,
    )
    os.replace(dta_temp, output_dta)


def build(
    master_path: Path,
    output_csv: Path,
    output_dta: Path,
    summary_csv: Path,
    database_path: Path,
    args: argparse.Namespace,
) -> None:
    if database_path.exists() and not args.overwrite:
        raise FileExistsError(f"{database_path} exists; pass --overwrite to replace it.")

    end_monthyear = args.end_year * 12 + args.end_month
    database_temp = database_path.with_name(database_path.name + ".tmp")
    if database_temp.exists():
        database_temp.unlink()

    connection = duckdb.connect(str(database_temp))
    succeeded = False
    try:
        configure_connection(
            connection, args.memory_limit, args.threads, database_path.parent / "tmp"
        )
        master_sql = source_expression(master_path, args.csv_sample_size)
        require_columns(
            relation_columns(connection, master_sql),
            REQUIRED_MASTER_COLUMNS,
            "master input",
        )
        fail_if(
            connection,
            f"""
            SELECT count(*) FROM {master_sql}
            WHERE CAST(monthyear AS BIGINT)
                  IS DISTINCT FROM CAST(year AS BIGINT) * 12 + CAST(month AS BIGINT)
            """,
            "{count} master rows have monthyear out of step with year and month.",
        )

        build_ac_month_skeleton(connection, master_sql)
        build_ac_district(connection, master_sql)
        # Pass the raw master, not the collapsed skeleton: build_ac_terms runs
        # its own ym_take cross-check against the grid-level rows.
        build_ac_terms(connection, master_sql, args.prior_term_missing_policy)
        attach_terms(connection)
        build_panel(connection, PANEL_TABLE, end_monthyear, args.prior_term_missing_policy)
        validate_panel(
            connection,
            PANEL_TABLE,
            end_monthyear,
            args.prior_term_missing_policy,
            args.expected_acs,
            args.expected_months,
            args.expected_rows,
        )
        log_composition(connection, PANEL_TABLE)
        write_summary(connection, PANEL_TABLE, SUMMARY_TABLE)
        write_outputs(
            connection, PANEL_TABLE, SUMMARY_TABLE, output_csv, output_dta, summary_csv
        )
        connection.execute("CHECKPOINT")
        succeeded = True
    except BaseException:
        succeeded = False
        raise
    finally:
        connection.close()
        if not succeeded and database_temp.exists():
            database_temp.unlink()

    os.replace(database_temp, database_path)
    logging.info("CSV: %s", output_csv)
    logging.info("Summary: %s", summary_csv)
    logging.info("Stata: %s", output_dta)
    logging.info("DuckDB: %s", database_path)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    intermediate = args.intermediate.resolve()
    master_path = (
        args.input.resolve() if args.input else intermediate / "0_master_dataset.parquet"
    )
    output_csv = (
        args.output.resolve() if args.output else intermediate / f"{OUTPUT_STEM}.csv"
    )
    output_dta = output_csv.with_suffix(".dta")
    summary_csv = output_csv.with_name(f"{SUMMARY_TABLE}.csv")
    database_path = (
        args.database.resolve() if args.database else intermediate / f"{OUTPUT_STEM}.db"
    )

    logging.info(
        "Building the AC-month panel through %s-%02d", args.end_year, args.end_month
    )
    build(master_path, output_csv, output_dta, summary_csv, database_path, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
