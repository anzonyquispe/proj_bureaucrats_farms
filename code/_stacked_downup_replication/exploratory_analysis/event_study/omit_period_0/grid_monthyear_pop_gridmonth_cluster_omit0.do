********************************************************************************
* Grid/month-year FE population event study, normalized to relative month 0.
* Controls retained; cluster by grid and month-year.
********************************************************************************

version 17
do "exploratory_analysis/event_study/omit_period_0/_event_study_pop_omit0_core.do" ///
    grid_monthyear controls grid_monthyear ///
    stacked_event_study_pop_5pre_grid_monthyear_fe_gridmonth_cluster_omit0
