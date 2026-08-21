********************************************************************************
* Joint test for the two original post-period interaction expressions.
*
* Run this after the FE01 reghdfejl regression. The treated/control expressions
* are unchanged. The program compares the correct same-regression joint test
* with a diagnostic calculation that incorrectly assumes independent estimates.
********************************************************************************
version 17

capture program drop compare_interaction_lincoms
program define compare_interaction_lincoms, rclass
    version 17
    syntax [, MODvar(name)]
    if "`modvar'" == "" local modvar "downup_ac_pop"

    local treated_expr "1.post_#1.treat + 1.`modvar' + 1.post_#1.`modvar' + 1.treat#1.`modvar' + 1.post_#1.treat#1.`modvar'"
    local control_expr "1.`modvar' + 1.post_#1.`modvar'"

    * Save the individual lincom results exactly as used by the graph.
    quietly lincom (`treated_expr'), level(95)
    scalar b_treated  = r(estimate)
    scalar se_treated = r(se)
    scalar lb_treated = r(lb)
    scalar ub_treated = r(ub)

    quietly lincom (`control_expr'), level(95)
    scalar b_control  = r(estimate)
    scalar se_control = r(se)
    scalar lb_control = r(lb)
    scalar ub_control = r(ub)

    * Estimate both expressions jointly. nlcom, post retains their covariance.
    tempname original bjoint vjoint
    estimates store `original'
    quietly nlcom ///
        (treated_post: (`treated_expr')) ///
        (control_post: (`control_expr')), post
    matrix `bjoint' = e(b)
    matrix `vjoint' = e(V)

    scalar covariance_tc = `vjoint'[1,2]
    scalar correlation_tc = covariance_tc / ///
        sqrt(`vjoint'[1,1] * `vjoint'[2,2])

    * This is the valid test because both estimates come from one regression.
    quietly lincom treated_post - control_post, level(90)
    scalar b_difference  = r(estimate)
    scalar se_difference = r(se)
    scalar p_difference  = r(p)
    scalar lb90_difference = r(lb)
    scalar ub90_difference = r(ub)

    * Diagnostic only: what the test would report if covariance were zero.
    scalar se_independent = sqrt(se_treated^2 + se_control^2)
    scalar t_independent = b_difference / se_independent
    scalar p_independent = 2 * ttail(e(df_r), abs(t_independent))

    display as text  _newline "Original post-period expressions"
    display as result "Treated post: " %10.4f b_treated ///
        "  SE=" %9.4f se_treated ///
        "  95% CI=[" %9.4f lb_treated ", " %9.4f ub_treated "]"
    display as result "Control post: " %10.4f b_control ///
        "  SE=" %9.4f se_control ///
        "  95% CI=[" %9.4f lb_control ", " %9.4f ub_control "]"

    display as text _newline "Dependence between the two lincom estimates"
    display as result "Covariance = " %10.4f covariance_tc
    display as result "Correlation = " %10.4f correlation_tc

    display as text _newline "Difference test"
    display as result "Proper joint test: difference=" %10.4f b_difference ///
        "  SE=" %9.4f se_difference ///
        "  p=" %8.4f p_difference ///
        "  90% CI=[" %9.4f lb90_difference ", " ///
        %9.4f ub90_difference "]"
    display as result "Covariance=0 diagnostic: SE=" %9.4f se_independent ///
        "  p=" %8.4f p_independent

    estimates restore `original'
    estimates drop `original'

    return scalar b_treated = b_treated
    return scalar b_control = b_control
    return scalar difference = b_difference
    return scalar se_difference = se_difference
    return scalar p_difference = p_difference
    return scalar covariance = covariance_tc
    return scalar correlation = correlation_tc
    return scalar se_independent = se_independent
    return scalar p_independent = p_independent
end

* Usage immediately after the FE01 regression:
*
* reghdfejl countk ib0.post_##ib0.treat##ib0.downup_ac_pop ///
*     wind_direction av_wind_speed, ///
*     absorb(unique_small_grid_id_cohort ///
*            relative_year_bin_aux#cohort_id) ///
*     vce(cluster ac_elec_yr)
*
* do "compare_interaction_lincoms.do"
* compare_interaction_lincoms, modvar(downup_ac_pop)
