* Grid/month-year FE and clustering: relative months -6 through +6; omit 0.
version 17
do "exploratory_analysis/event_study/omit_period_0/_event_study_pop_omit0_core.do" ///
    grid_monthyear controls grid_monthyear ///
    stacked_event_study_pop_grid_monthyear_fe_gridmonth_cluster_m6_p6_omit0 -6 6
