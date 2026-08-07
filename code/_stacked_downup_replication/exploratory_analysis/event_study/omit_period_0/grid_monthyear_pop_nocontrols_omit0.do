********************************************************************************
* Grid/month-year FE population event study, normalized to relative month 0.
* Weather controls omitted; original cohort-interacted clustering retained.
********************************************************************************

version 17
do "exploratory_analysis/event_study/omit_period_0/_event_study_pop_omit0_core.do" ///
    grid_monthyear nocontrols cohort ///
    stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols_omit0
