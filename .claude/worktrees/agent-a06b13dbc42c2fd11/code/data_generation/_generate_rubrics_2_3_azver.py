#!/usr/bin/env python3
"""
_generate_rubrics_2_3_azver.py

One-shot generator that builds both `tweets_by_rubric2_azver.dta` and
`tweets_by_rubric3_azver.dta`, sharing the heavy upstream pipeline (3.7 GB
scraped tweets, translations, tweet-id resolution, politician handle merge,
winner disambiguation, panel grid, elected flag, time-invariant politician
chars).

Equivalent to running both _tweets_acreg_rubric2.ipynb and
_tweets_acreg_rubric3.ipynb back-to-back, but loads the scraped tweets only
once. Use the notebooks for interactive iteration; use this script for a
one-shot batch run.

Usage:
    python3 _generate_rubrics_2_3_azver.py
"""

from __future__ import annotations

import csv
import os
import re

import geopandas as gpd
import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
MAIN     = '/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires'
MAIN_DIR = MAIN                                                # for shapefile / panel_data
INPUT_TW = f'{MAIN}/data/input/politician_opinions/twitter'
INTERIM  = f'{MAIN}/data/interim/politician_opinions/twitter'
NETA     = f'{MAIN}/data/input/my_neta'
SHAPE_DIR  = f'{MAIN_DIR}/proj_bureaucrats_farms/data_output/intermediate'
OUTPUT_DIR = f'{MAIN_DIR}/proj_bureaucrats_farms/data_output/intermediate'


# ===========================================================================
# 1. Shared pipeline: build twinfo + politician_id + cycle_info + panel grid
# ===========================================================================
def build_shared_pipeline():
    print('[1/8] Loading scraped_tweets_complete2.csv (3.7 GB) ...', flush=True)
    df = pd.read_csv(
        f'{INPUT_TW}/scraped_tweets_complete2.csv',
        low_memory=False,
    )[['url','text','lang','handle_searched','createdAt','isRetweet']] \
        .rename(columns={'createdAt':'date'})
    df = df.loc[(df['isRetweet']=='False') | (df['isRetweet']=='0.0')]
    print(f'       tweets after isRetweet filter: {len(df):,}', flush=True)

    print('[2/8] Translations ...', flush=True)
    translated = pd.concat([
        pd.read_csv(f'{INTERIM}/translated_tweets_hindi_partial2.csv'),
        pd.read_csv(f'{INTERIM}/translated_tweets_hindi_partial.csv'),
        pd.read_csv(f'{INTERIM}/translated_tweets_hindi_partial_aux.csv'),
    ]).drop_duplicates(['original','translated'])[['original','translated']]
    translated = translated.loc[translated['translated'].notna()].rename(columns={'original':'text'})

    df = df.merge(translated, how='left', on='text')
    df['text'] = np.where(((df['translated'].notna()) & (df['lang']!='en')),
                          df['translated'], df['text'])
    del translated

    print('[3/8] tweet_id merge via analyse_tweets ...', flush=True)
    analyse = pd.read_csv(f'{INTERIM}/analyse_tweets.csv', low_memory=False) \
        .rename(columns={'Unnamed: 0':'tweet_id'})
    df1 = df.merge(analyse, how='left', on=['text','date'])
    df2 = df1.loc[df1['tweet_id'].isna()].drop(columns=['tweet_id'])
    analyse_no_date = (pd.read_csv(f'{INTERIM}/analyse_tweets.csv')
                       .drop(columns=['date'])
                       .rename(columns={'Unnamed: 0':'tweet_id'})
                       .drop_duplicates(['text']))
    df2 = df2.merge(analyse_no_date, how='left', on='text') \
              [['url','lang','text','handle_searched','date','tweet_id','date']]
    df1 = df1.loc[df1['tweet_id'].notna()] \
              [['url','lang','text','handle_searched','date','tweet_id','date']]
    df_analysis = pd.concat([df1, df2])
    del df, df1, df2, analyse, analyse_no_date

    print('[4/8] date_real, handle cleaning, dedup ...', flush=True)
    df_analysis['date_real'] = pd.to_datetime(df_analysis['date'].iloc[:, 0], errors='coerce')
    df_analysis['date']      = df_analysis['date'].iloc[:, 0]
    df_analysis['handle_searched'] = (df_analysis['handle_searched'].str.replace('@','')
                                       .str.lower().str.split('?').str[0].str.replace(' ',''))
    df_analysis = df_analysis.drop_duplicates(['text','date_real','handle_searched'])
    df_analysis = df_analysis.loc[df_analysis['text'].notna()]

    print('[5/8] official twitter merge ...', flush=True)
    official = pd.read_excel(f'{MAIN}/data/input/politician_opinions/official_twitter.xlsx')
    official_2 = pd.read_excel(f'{MAIN}/data/input/politician_opinions/official_social_profiles.xlsx')
    official_2 = official_2.loc[official_2['platform']=='X (Twitter)']
    official_2['username'] = official_2['url'].str.split('/').str[-1]
    official = official.merge(official_2, how='outer',
                              left_on='Politician Name', right_on='name')
    official['Twitter Handle'] = (official['Twitter Handle']
                                  .fillna(official['username'])
                                  .str.replace('@','').str.lower())
    official = official.loc[official['Twitter Handle'].notna()]
    official['Twitter Handle'] = (official['Twitter Handle'].str.replace('@','')
                                   .str.lower().str.split('?').str[0].str.replace(' ',''))
    official['handle_searched'] = official['Twitter Handle']

    twinfo = df_analysis.merge(official, how='left', on='handle_searched', indicator=True)
    twinfo['Politician Name'] = (twinfo.groupby('handle_searched')['Politician Name']
                                  .transform(lambda s: s.ffill().bfill()))
    twinfo['month'] = pd.to_datetime(twinfo['date_real']).dt.month
    twinfo['year']  = pd.to_datetime(twinfo['date_real']).dt.year

    print('[6/8] winners disambiguation by state ...', flush=True)
    winners = pd.read_csv(f'{NETA}/2008_onwards_winners_table.csv')
    winners['ASSEMBLY']      = winners['unique_id'].str.split('_', expand=True).iloc[:, 1].astype(float)
    winners['election_year'] = winners['unique_id'].str.split('_', expand=True).iloc[:, 0].str[-4:].astype(float)
    winners['STATE_UT']      = winners['unique_id'].str.split('_', expand=True).iloc[:, 0].str[:-4].str.upper()
    winners['STATE_UT'] = winners['STATE_UT'].replace({
        'UTTARPRADESH':'UTTAR PRADESH','UP':'UTTAR PRADESH',
        'HA':'HARYANA','BIH':'BIHAR','PB':'PUNJAB'
    })
    winners['politician_id'] = winners['name'].str.lower().str.replace(' ', '')
    state_count   = winners.groupby('politician_id')['STATE_UT'].nunique()
    ambiguous_ids = set(state_count[state_count > 1].index)
    winners_clean = winners[~winners['politician_id'].isin(ambiguous_ids)].copy()

    twinfo['politician_id'] = twinfo['Politician Name'].str.lower().str.replace(' ', '')
    twinfo = twinfo[twinfo['politician_id'].notna()
                    & ~twinfo['politician_id'].isin(ambiguous_ids)].copy()

    print('[7/8] panel_data + cycle_info ...', flush=True)
    panel_data = pd.read_stata(f'{SHAPE_DIR}/panel_data_election_year.dta')
    cycle_info = (winners_clean[['politician_id','name','STATE_UT','unique_id','ac_name']]
                  .merge(panel_data[['unique_id','ac_uq_id','election_year',
                                     'month_take','year_take','month_end','year_end']]
                         .drop_duplicates('unique_id'),
                         on='unique_id', how='left')
                  .dropna(subset=['month_take','year_take','month_end','year_end'])
                  .copy())

    print('[8/8] panel grid (universe x months) + elected + chars ...', flush=True)
    universe = winners_clean[['politician_id','name']].drop_duplicates('politician_id').copy()
    first_tw = (twinfo.dropna(subset=['date_real'])
                .assign(ym=lambda d: d['year'].astype(int)*100 + d['month'].astype(int))
                .groupby('politician_id')['ym'].min()
                .reset_index().rename(columns={'ym':'first_tw_ym'}))
    first_take = (cycle_info.assign(ym=lambda d: d['year_take'].astype(int)*100 + d['month_take'].astype(int))
                  .groupby('politician_id')['ym'].min()
                  .reset_index().rename(columns={'ym':'first_take_ym'}))
    universe = (universe.merge(first_tw, on='politician_id', how='left')
                        .merge(first_take, on='politician_id', how='left'))
    universe['start_ym'] = universe['first_tw_ym'].fillna(universe['first_take_ym']).astype('Int64')
    universe['end_ym']   = 202512
    universe = universe.dropna(subset=['start_ym']).copy()
    universe['start_ym'] = universe['start_ym'].astype(int)

    def _months_between(start_ym, end_ym):
        s = pd.Timestamp(year=start_ym // 100, month=start_ym % 100, day=1)
        e = pd.Timestamp(year=end_ym   // 100, month=end_ym   % 100, day=1)
        rng = pd.date_range(s, e, freq='MS')
        return pd.DataFrame({'year': rng.year.astype(int), 'month': rng.month.astype(int)})

    frames = []
    for r in universe.itertuples(index=False):
        m = _months_between(r.start_ym, r.end_ym)
        m['politician_id'] = r.politician_id
        frames.append(m)
    panel_grid = pd.concat(frames, ignore_index=True)

    # elected
    panel_grid['ym'] = panel_grid['year']*100 + panel_grid['month']
    ci = cycle_info.copy()
    ci['take_ym'] = ci['year_take'].astype(int)*100 + ci['month_take'].astype(int)
    ci['end_ym']  = ci['year_end'].astype(int) *100 + ci['month_end'].astype(int)
    active = panel_grid.merge(ci, on='politician_id', how='left')
    active = active[(active['ym'] >= active['take_ym']) & (active['ym'] <= active['end_ym'])].copy()
    active = (active.sort_values(['politician_id','year','month','take_ym'])
                    .drop_duplicates(['politician_id','year','month'], keep='last'))
    active = active[['politician_id','year','month','ac_uq_id','unique_id','election_year',
                     'month_take','year_take','month_end','year_end','ac_name']]
    active['elected'] = 1
    panel_grid = (panel_grid.drop(columns=['ym'])
                            .merge(active, on=['politician_id','year','month'], how='left'))
    panel_grid['elected'] = panel_grid['elected'].fillna(0).astype(int)

    # pol_info
    char_rename = {
        'dependent_1_owns_agricultural_assets':'dep1_owns_agri',
        'dependent_2_owns_agricultural_assets':'dep2_owns_agri',
        'dependent_3_owns_agricultural_assets':'dep3_owns_agri',
        'self_owns_agricultural_assets':       'self_owns_agri',
        'spouse_owns_agricultural_assets':     'spouse_owns_agri',
    }
    char_cols = ['education','self_profession','spouse_profession'] + list(char_rename.values())
    pol_info = (winners_clean.sort_values(['politician_id','election_year'])
                .drop_duplicates('politician_id', keep='last')
                .rename(columns=char_rename)
                [['politician_id','name','STATE_UT'] + char_cols])
    panel_grid = panel_grid.merge(pol_info, on='politician_id', how='left')

    print(f'       twinfo: {len(twinfo):,} rows | panel: {len(panel_grid):,} rows '
          f'| {panel_grid["elected"].sum():,} elected', flush=True)
    return twinfo, panel_grid


# ===========================================================================
# 2. Rubric_2 aggregation + save
# ===========================================================================
def build_rubric2(twinfo, panel_grid):
    print('\n=== Building rubric_2 panel ===', flush=True)

    FRAMING_VALID         = {'provider_hero','victim','protester_activist','beneficiary',
                             'problem_causer','neutral_reference','rhetorical'}
    STANCE_FARMERS_VALID  = {'pro_farmer','anti_farmer','neutral','not_applicable'}
    STANCE_LAWS_VALID     = {'pro_laws','anti_laws','neutral','not_applicable'}
    WELFARE_POLICY_MAP    = {'msp':'msp_procurement','loan_waiver':'debt_relief'}
    WELFARE_POLICY_VALID  = {'pm_kisan','crop_insurance','machinery_distribution',
                             'msp_procurement','debt_relief','irrigation_scheme',
                             'soil_health','organic_farming','other_farm_policy','none'}
    BLAME_VALID           = {'central_govt','state_govt','opposition','middlemen',
                             'bureaucracy','other','none'}

    def _coerce_int(v):
        if pd.isna(v): return np.nan
        try:
            n = int(float(v));  return n if 0 <= n <= 3 else np.nan
        except (TypeError, ValueError):
            return np.nan

    def _norm_cat(v, valid):
        if pd.isna(v): return np.nan
        s = str(v).strip().lower()
        return s if s in valid else np.nan

    def _norm_welfare(v):
        if pd.isna(v): return np.nan
        s = str(v).strip().lower();  s = WELFARE_POLICY_MAP.get(s, s)
        return s if s in WELFARE_POLICY_VALID else np.nan

    def _norm_credit(v):
        if pd.isna(v): return np.nan
        s = str(v).strip().lower()
        if s in ('true','1','1.0'):  return 'true'
        if s in ('false','0','0.0'): return 'false'
        return np.nan

    print('  loading rubric_2_output.csv ...', flush=True)
    r2 = pd.read_csv(f'{INTERIM}/rubric_2_output.csv',
                     engine='python', quoting=csv.QUOTE_ALL, on_bad_lines='warn')

    r2['agriculture_relevance']    = r2['agriculture_relevance'].apply(_coerce_int)
    r2['farmer_framing']           = r2['farmer_framing'].apply(lambda v: _norm_cat(v, FRAMING_VALID))
    r2['stance_farmers']           = r2['stance_farmers'].apply(lambda v: _norm_cat(v, STANCE_FARMERS_VALID))
    r2['farmer_protest_relevance'] = r2['farmer_protest_relevance'].apply(_coerce_int)
    r2['stance_farm_laws']         = r2['stance_farm_laws'].apply(lambda v: _norm_cat(v, STANCE_LAWS_VALID))
    r2['farmer_welfare_policy']    = r2['farmer_welfare_policy'].apply(_norm_welfare)
    r2['credit_claiming']          = r2['credit_claiming'].apply(_norm_credit)
    r2['blame_attribution']        = r2['blame_attribution'].apply(lambda v: _norm_cat(v, BLAME_VALID))

    tw = twinfo.merge(
        r2.drop_duplicates('tweet_id')[
            ['tweet_id','agriculture_relevance','farmer_framing','stance_farmers',
             'farmer_protest_relevance','stance_farm_laws','farmer_welfare_policy',
             'credit_claiming','blame_attribution']],
        how='left', on='tweet_id')

    r1_iq = pd.read_csv(f'{INTERIM}/rubric_1_output.csv',
                        engine='python', quoting=csv.QUOTE_ALL,
                        on_bad_lines='warn', usecols=['tweet_id','is_quoted'])
    tw = tw.merge(r1_iq.drop_duplicates('tweet_id'), how='left', on='tweet_id')

    def aggregate(twf, suffix):
        keys = ['politician_id','year','month']

        def pivot_numeric(col, prefix):
            sub = twf.dropna(subset=[col])
            if sub.empty: return pd.DataFrame(columns=keys)
            out = (sub.groupby(keys + [col])['text'].nunique()
                   .reset_index().rename(columns={'text':'n'})
                   .pivot_table(index=keys, columns=col, values='n', fill_value=0)
                   .reset_index())
            out.columns = [c if c in keys else f'{prefix}{int(c)}' for c in out.columns]
            return out

        def pivot_string(col, prefix):
            sub = twf.dropna(subset=[col])
            if sub.empty: return pd.DataFrame(columns=keys)
            return (sub.groupby(keys + [col])['text'].nunique()
                    .reset_index().rename(columns={'text':'n'})
                    .pivot_table(index=keys, columns=col, values='n', fill_value=0)
                    .add_prefix(prefix).reset_index())

        parts = [
            pivot_numeric('agriculture_relevance',    'ar'),
            pivot_string ('farmer_framing',           'ff_'),
            pivot_string ('stance_farmers',           'sf_'),
            pivot_numeric('farmer_protest_relevance', 'pr'),
            pivot_string ('stance_farm_laws',         'sl_'),
            pivot_string ('farmer_welfare_policy',    'wp_'),
            pivot_string ('credit_claiming',          'cc_'),
            pivot_string ('blame_attribution',        'ba_'),
        ]
        out = parts[0]
        for p in parts[1:]:
            out = out.merge(p, on=keys, how='outer')
        out = out.fillna(0)
        return out.rename(columns={c: f'{c}_{suffix}' for c in out.columns if c not in keys})

    fields = ['agriculture_relevance','farmer_framing','stance_farmers',
              'farmer_protest_relevance','stance_farm_laws','farmer_welfare_policy',
              'credit_claiming','blame_attribution']
    cls = tw.loc[tw[fields].notna().any(axis=1) & (tw['year'] <= 2025)].copy()
    print(f'  classified tweets in panel period: {len(cls):,}', flush=True)

    agg_all = aggregate(cls, 'all')
    agg_own = aggregate(cls[cls['is_quoted'] == False], 'own')

    panel = (panel_grid
             .merge(agg_all, on=['politician_id','year','month'], how='left')
             .merge(agg_own, on=['politician_id','year','month'], how='left'))
    agg_cols = sorted(set(c for c in list(agg_all.columns) + list(agg_own.columns)
                          if c not in ('politician_id','year','month')))
    agg_cols = [c for c in agg_cols if c in panel.columns]
    panel[agg_cols] = panel[agg_cols].fillna(0)
    panel = panel.rename(columns={'politician_id':'Politician_Name'})

    out_path = f'{OUTPUT_DIR}/tweets_by_rubric2_azver.dta'
    panel.to_stata(out_path, write_index=False)
    print(f'  Saved: {out_path}  shape={panel.shape}', flush=True)


# ===========================================================================
# 3. Rubric_3 aggregation + save
# ===========================================================================
def build_rubric3(twinfo, panel_grid):
    print('\n=== Building rubric_3 panel ===', flush=True)

    POLLUTION_TYPE_MAP   = {'air_pollution_general':'general_air_pollution',
                            'waste_burning':'other_environmental'}
    POLLUTION_TYPE_VALID = {'crop_burning_smoke','general_air_pollution',
                            'industrial_pollution','water_pollution','other_environmental'}
    STANCE_VALID         = {'pro_enforcement','anti_enforcement','permissive',
                            'neutral','not_applicable'}
    PI_VALID             = {'happy_seeder','super_sms','baler','chc','bio_decomposer',
                            'biomass_plant','straw_market','satellite_monitoring',
                            'fines_penalties','caqm','compensation_payment',
                            'awareness_campaign','machinery_subsidy','other_instrument'}
    ACTION_MAP           = {'implement':'other_policy','discuss':'other_policy',
                            'demand':'other_policy','alternative_use_promotion':'other_policy',
                            'financial_incentive':'subsidy_scheme'}
    ACTION_VALID         = {'subsidy_scheme','enforcement_penalty','infrastructure',
                            'regulation','awareness_campaign','compensation','other_policy'}
    STAGE_VALID          = {'announcement','implementation','evaluation','criticism','demand'}
    BLAME_MAP            = {'government':'other','bjp_government':'other','vehicles':'other'}
    BLAME_VALID          = {'central_govt','state_govt','opposition','farmers',
                            'bureaucracy','delhi_govt','other'}

    def _coerce_int(v):
        if pd.isna(v): return np.nan
        try:
            n = int(float(v));  return n if 0 <= n <= 3 else np.nan
        except (TypeError, ValueError):
            return np.nan

    def _norm_cat(v, valid, alias=None):
        if pd.isna(v): return np.nan
        s = str(v).strip().lower()
        if alias: s = alias.get(s, s)
        return s if s in valid else np.nan

    def _norm_bool(v):
        if pd.isna(v): return np.nan
        s = str(v).strip().lower()
        if s in ('true','1','1.0'):  return 'true'
        if s in ('false','0','0.0'): return 'false'
        return np.nan

    def _parse_instruments(v):
        if pd.isna(v): return None
        s = str(v).strip()
        if not s or s.lower() in ('none','nan','null'): return None
        if s.startswith('[') and s.endswith(']'):
            tokens = re.findall(r"['\"]([^'\"]+)['\"]", s)
            if not tokens:
                tokens = [t.strip().strip("'\"") for t in s[1:-1].split(',') if t.strip()]
            return [t for t in tokens if t] or None
        if '|' in s:
            return [t.strip() for t in s.split('|') if t.strip()]
        return [s]

    print('  loading rubric_3_output.csv ...', flush=True)
    r3 = pd.read_csv(f'{INTERIM}/rubric_3_output.csv',
                     engine='python', quoting=csv.QUOTE_ALL, on_bad_lines='warn')

    r3['crop_burning_relevance']      = r3['crop_burning_relevance'].apply(_coerce_int)
    r3['pollution_type']              = r3['pollution_type'].apply(
        lambda v: _norm_cat(v, POLLUTION_TYPE_VALID, POLLUTION_TYPE_MAP))
    r3['burning_season_context']      = r3['burning_season_context'].apply(_norm_bool)
    r3['stance_crop_burning']         = r3['stance_crop_burning'].apply(lambda v: _norm_cat(v, STANCE_VALID))
    r3['policy_instrument_mentioned'] = r3['policy_instrument_mentioned'].apply(_parse_instruments)
    r3['policy_action_type']          = r3['policy_action_type'].apply(
        lambda v: _norm_cat(v, ACTION_VALID, ACTION_MAP))
    r3['policy_stage']                = r3['policy_stage'].apply(lambda v: _norm_cat(v, STAGE_VALID))
    r3['credit_claiming']             = r3['credit_claiming'].apply(_norm_bool)
    r3['blame_attribution']           = r3['blame_attribution'].apply(
        lambda v: _norm_cat(v, BLAME_VALID, BLAME_MAP))

    tw = twinfo.merge(
        r3.drop_duplicates('tweet_id')[
            ['tweet_id','crop_burning_relevance','pollution_type','burning_season_context',
             'stance_crop_burning','policy_instrument_mentioned','policy_action_type',
             'policy_stage','credit_claiming','blame_attribution']],
        how='left', on='tweet_id')

    r1_iq = pd.read_csv(f'{INTERIM}/rubric_1_output.csv',
                        engine='python', quoting=csv.QUOTE_ALL,
                        on_bad_lines='warn', usecols=['tweet_id','is_quoted'])
    tw = tw.merge(r1_iq.drop_duplicates('tweet_id'), how='left', on='tweet_id')

    def aggregate(twf, suffix):
        keys = ['politician_id','year','month']

        def pivot_numeric(col, prefix):
            sub = twf.dropna(subset=[col])
            if sub.empty: return pd.DataFrame(columns=keys)
            out = (sub.groupby(keys + [col])['text'].nunique()
                   .reset_index().rename(columns={'text':'n'})
                   .pivot_table(index=keys, columns=col, values='n', fill_value=0)
                   .reset_index())
            out.columns = [c if c in keys else f'{prefix}{int(c)}' for c in out.columns]
            return out

        def pivot_string(col, prefix):
            sub = twf.dropna(subset=[col])
            if sub.empty: return pd.DataFrame(columns=keys)
            return (sub.groupby(keys + [col])['text'].nunique()
                    .reset_index().rename(columns={'text':'n'})
                    .pivot_table(index=keys, columns=col, values='n', fill_value=0)
                    .add_prefix(prefix).reset_index())

        def pivot_list(col, prefix, valid_set):
            sub = twf[keys + ['text', col]].copy()
            sub = sub[sub[col].notna()]
            if sub.empty: return pd.DataFrame(columns=keys)
            sub = sub.explode(col).dropna(subset=[col])
            sub[col] = sub[col].apply(lambda v: v if v in valid_set else 'other_instrument')
            return (sub.groupby(keys + [col])['text'].nunique()
                    .reset_index().rename(columns={'text':'n'})
                    .pivot_table(index=keys, columns=col, values='n', fill_value=0)
                    .add_prefix(prefix).reset_index())

        parts = [
            pivot_numeric('crop_burning_relevance',      'cr'),
            pivot_string ('pollution_type',              'pt_'),
            pivot_string ('burning_season_context',      'bs_'),
            pivot_string ('stance_crop_burning',         'sb_'),
            pivot_list   ('policy_instrument_mentioned', 'pi_', PI_VALID),
            pivot_string ('policy_action_type',          'pa_'),
            pivot_string ('policy_stage',                'ps_'),
            pivot_string ('credit_claiming',             'cc_'),
            pivot_string ('blame_attribution',           'ba_'),
        ]
        out = parts[0]
        for p in parts[1:]:
            out = out.merge(p, on=keys, how='outer')
        out = out.fillna(0)
        return out.rename(columns={c: f'{c}_{suffix}' for c in out.columns if c not in keys})

    fields = ['crop_burning_relevance','pollution_type','burning_season_context',
              'stance_crop_burning','policy_instrument_mentioned','policy_action_type',
              'policy_stage','credit_claiming','blame_attribution']
    cls = tw.loc[tw[fields].notna().any(axis=1) & (tw['year'] <= 2025)].copy()
    print(f'  classified tweets in panel period: {len(cls):,}', flush=True)

    agg_all = aggregate(cls, 'all')
    agg_own = aggregate(cls[cls['is_quoted'] == False], 'own')

    panel = (panel_grid
             .merge(agg_all, on=['politician_id','year','month'], how='left')
             .merge(agg_own, on=['politician_id','year','month'], how='left'))
    agg_cols = sorted(set(c for c in list(agg_all.columns) + list(agg_own.columns)
                          if c not in ('politician_id','year','month')))
    agg_cols = [c for c in agg_cols if c in panel.columns]
    panel[agg_cols] = panel[agg_cols].fillna(0)
    panel = panel.rename(columns={'politician_id':'Politician_Name'})

    out_path = f'{OUTPUT_DIR}/tweets_by_rubric3_azver.dta'
    panel.to_stata(out_path, write_index=False)
    print(f'  Saved: {out_path}  shape={panel.shape}', flush=True)


# ===========================================================================
def main():
    twinfo, panel_grid = build_shared_pipeline()
    # Each builder works off a copy so it can merge in rubric-specific cols
    # without polluting twinfo for the next builder.
    build_rubric2(twinfo.copy(), panel_grid.copy())
    build_rubric3(twinfo.copy(), panel_grid.copy())
    print('\nDONE.')


if __name__ == '__main__':
    main()
