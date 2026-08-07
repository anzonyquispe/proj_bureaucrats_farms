********************************************************************************
* Population event study robustness 3:
*   - grid x cohort and month-year x cohort fixed effects
*   - wind direction and average wind-speed controls retained
*   - two-way clustering by grid and month-year (no cohort interactions)
********************************************************************************

version 17
do "_main_2_stacked_event_study_5pre_grid_monthyear_pop.do" ///
    controls grid_monthyear ///
    stacked_event_study_pop_5pre_grid_monthyear_fe_gridmonth_cluster

