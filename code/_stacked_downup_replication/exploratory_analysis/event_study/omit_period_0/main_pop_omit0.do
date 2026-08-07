********************************************************************************
* Main population event study, normalized to relative month 0.
* FE: grid x cohort and AC x month-year x cohort.
* Controls and original cohort-interacted clustering retained.
********************************************************************************

version 17
do "exploratory_analysis/event_study/omit_period_0/_event_study_pop_omit0_core.do" ///
    main controls cohort ///
    stacked_event_study_pop_5pre_omit0
