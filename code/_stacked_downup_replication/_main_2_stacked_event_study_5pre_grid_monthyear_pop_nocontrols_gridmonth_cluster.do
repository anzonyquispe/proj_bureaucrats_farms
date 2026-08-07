********************************************************************************
* Population event study robustness 1:
*   - grid x cohort and month-year x cohort fixed effects
*   - no wind controls
*   - two-way clustering by grid and month-year (no cohort interactions)
********************************************************************************

version 17
do "_main_2_stacked_event_study_5pre_grid_monthyear_pop.do" ///
    nocontrols grid_monthyear ///
    stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols_gridmonth_cluster

