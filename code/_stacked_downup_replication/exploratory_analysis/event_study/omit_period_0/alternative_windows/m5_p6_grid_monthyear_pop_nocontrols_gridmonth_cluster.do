* Grid/month-year FE, no controls and modified clustering: -5 through +6; omit 0.
version 17
do "exploratory_analysis/event_study/omit_period_0/_event_study_pop_omit0_core.do" ///
    grid_monthyear nocontrols grid_monthyear ///
    stacked_event_study_pop_grid_monthyear_fe_nocontrols_gridmonth_cluster_m5_p6_omit0 -5 6
