*! version 2.1  2026-08-26
*! Interaction effect graph for triple-interaction DiD models.

capture program drop interaction_graph
program define interaction_graph
    version 14
    syntax using/, Estimates(numlist) Output(string) Type(string) ///
        [YRange(numlist min=2 max=2) ESTname(string) MODvar(string)]

    if "`estname'" == "" local estname "evreg"
    if "`modvar'" == "" local modvar "downup_ac"
    if !inlist("`type'", "politician", "protest") {
        display as error "type() must be politician or protest"
        exit 198
    }

    local filetype = substr(`"`using'"', -4, 4)
    if "`filetype'" == ".csv" {
        estload_csv using `"`using'"'
    }
    else if "`filetype'" == "ster" {
        estread using `"`using'"'
    }
    else {
        display as error "Input must be .ster or .csv"
        exit 198
    }

    foreach numero of numlist `estimates' {
        estimates restore `estname'`numero'
        tempname lincoms_treat
        matrix `lincoms_treat' = J(4, 5, .)

        local baseline_expr "1.`modvar'"
        local control_expr "1.`modvar' + 1.post_#1.`modvar'"
        local treated_expr "1.post_#1.treat + 1.`modvar' + 1.post_#1.`modvar' + 1.treat#1.`modvar' + 1.post_#1.treat#1.`modvar'"
        local difference_expr "1.post_#1.treat + 1.treat#1.`modvar' + 1.post_#1.treat#1.`modvar'"

        * Standardize every displayed result by the control-pre estimate.
        quietly lincom (`baseline_expr') - (`baseline_expr')
        local control_pre_b = r(estimate)
        local control_pre_lb95 = 0
        local control_pre_ub95 = 0
        matrix `lincoms_treat'[1,1] = 0
        matrix `lincoms_treat'[1,2] = 0
        matrix `lincoms_treat'[1,3] = 0

        quietly lincom (`control_expr') - (`baseline_expr')
        local control_post_b = r(estimate)
        local control_post_lb95 = r(lb)
        local control_post_ub95 = r(ub)
        matrix `lincoms_treat'[2,1] = r(estimate)
        matrix `lincoms_treat'[2,2] = r(ub)
        matrix `lincoms_treat'[2,3] = r(lb)

        quietly lincom (`treated_expr') - (`baseline_expr')
        local treated_post_b = r(estimate)
        local treated_post_lb95 = r(lb)
        local treated_post_ub95 = r(ub)
        matrix `lincoms_treat'[3,1] = r(estimate)
        matrix `lincoms_treat'[3,2] = r(ub)
        matrix `lincoms_treat'[3,3] = r(lb)

        * The post treated-control contrast is invariant to subtracting the
        * same control-pre baseline from both post estimates.
        quietly lincom (`difference_expr')
        local difference_b = r(estimate)
        local difference_se = r(se)
        local difference_lb95 = r(lb)
        local difference_ub95 = r(ub)
        local difference_p = r(p)
        matrix `lincoms_treat'[4,1] = r(estimate)
        matrix `lincoms_treat'[4,2] = r(ub)
        matrix `lincoms_treat'[4,3] = r(lb)

        quietly lincom (`baseline_expr') - (`baseline_expr'), level(90)
        local control_pre_lb90 = 0
        local control_pre_ub90 = 0
        matrix `lincoms_treat'[1,4] = 0
        matrix `lincoms_treat'[1,5] = 0
        quietly lincom (`control_expr') - (`baseline_expr'), level(90)
        local control_post_lb90 = r(lb)
        local control_post_ub90 = r(ub)
        matrix `lincoms_treat'[2,4] = r(ub)
        matrix `lincoms_treat'[2,5] = r(lb)
        quietly lincom (`treated_expr') - (`baseline_expr'), level(90)
        local treated_post_lb90 = r(lb)
        local treated_post_ub90 = r(ub)
        matrix `lincoms_treat'[3,4] = r(ub)
        matrix `lincoms_treat'[3,5] = r(lb)
        quietly lincom (`difference_expr'), level(90)
        local difference_lb90 = r(lb)
        local difference_ub90 = r(ub)
        matrix `lincoms_treat'[4,4] = r(ub)
        matrix `lincoms_treat'[4,5] = r(lb)

        local pval : display %5.3f `difference_p'
        local pval = strtrim("`pval'")

        display as text ""
        display as result "INTERACTION AUDIT (CONTROL-PRE STANDARDIZED): `type', estimate `estname'`numero', moderator `modvar'"
        display as text "Control pre  : b = " %12.6f `control_pre_b' ///
            "   95% CI [" %12.6f `control_pre_lb95' ", " %12.6f `control_pre_ub95' "]" ///
            "   90% CI [" %12.6f `control_pre_lb90' ", " %12.6f `control_pre_ub90' "]"
        display as text "Control post : b = " %12.6f `control_post_b' ///
            "   95% CI [" %12.6f `control_post_lb95' ", " %12.6f `control_post_ub95' "]" ///
            "   90% CI [" %12.6f `control_post_lb90' ", " %12.6f `control_post_ub90' "]"
        display as text "Treated post : b = " %12.6f `treated_post_b' ///
            "   95% CI [" %12.6f `treated_post_lb95' ", " %12.6f `treated_post_ub95' "]" ///
            "   90% CI [" %12.6f `treated_post_lb90' ", " %12.6f `treated_post_ub90' "]"
        display as text "Difference   : b = " %12.6f `difference_b' ///
            "   SE = " %12.6f `difference_se' ///
            "   95% CI [" %12.6f `difference_lb95' ", " %12.6f `difference_ub95' "]" ///
            "   90% CI [" %12.6f `difference_lb90' ", " %12.6f `difference_ub90' "]" ///
            "   p = " %9.6f `difference_p'

        quietly clear
        quietly svmat double `lincoms_treat', names(lincoms_treat)
        quietly gen sec = .

        local pos1 = lincoms_treat1[1]
        local pos2 = lincoms_treat1[2]
        local pos3 = lincoms_treat1[3]
        local pos4 = (`pos2' + `pos3') / 2

        * Confidence intervals are not plotted. Production ranges are fixed by
        * analysis type; yrange() remains an override for other callers.
        if "`yrange'" == "" {
            if "`type'" == "politician" {
                local ymin = -3
                local ymax = 18
            }
            else {
                local ymin = -20
                local ymax = 140
            }
        }
        else {
            tokenize `yrange'
            local ymin = `1'
            local ymax = `2'
        }
        if "`type'" == "politician" {
            * Shift the complete politician diagram 0.5 x-units right so its
            * left labels do not touch the vertical plot boundary.
            quietly replace sec = 1.40 in 1
            * Both estimates refer to the same post period and therefore share
            * exactly the same horizontal coordinate.
            quietly replace sec = 3.75 in 2
            quietly replace sec = 3.75 in 3
            quietly replace sec = 5.68 in 4
            twoway ///
                (pcarrowi `pos1' 1.45 `pos2' 3.75, color(black)) ///
                (pcarrowi `pos1' 1.45 `pos3' 3.75, color(black)) ///
                (scatter lincoms_treat1 sec in 1, msymbol(O) color(black) msize(3)) ///
                (scatter lincoms_treat1 sec in 2/3, msymbol(O) color(black) msize(3)) ///
                (pci `pos2' 5.55 `pos2' 5.68, color(black)) ///
                (pci `pos2' 5.68 `pos3' 5.68, color(black)) ///
                (pci `pos3' 5.55 `pos3' 5.68, color(black)) ///
                (pci `pos4' 5.68 `pos4' 5.72, color(black)), ///
                text(1 1.22 "Non-Agricultural" "Politician", place(w) size(3.5) justification(right)) ///
                text(1 3.98 "Non-Agricultural" "Politician", place(e) size(3.5) justification(left)) ///
                text(`pos3' 3.98 "Agricultural" "Politician", place(e) size(3.5) justification(left)) ///
                legend(off) ///
                text(`pos4' 5.92 "p-value = `pval'", place(e) size(3)) ///
                xlabel(, nogrid nolabels) xtitle(" ") ///
                ytitle("Effect of Down>Up on Number of Fires (x 1,000)") ///
                xscale(range(-.35 7.35) off) yscale(range(`ymin' `ymax')) ///
                ylabel(-3(3)18) ///
                graphregion(margin(small)) plotregion(margin(small)) ///
                yline(0, lcolor(black%75))
        }
        else {
            quietly replace sec = .9 in 1
            quietly replace sec = 3.50 in 2
            quietly replace sec = 3.50 in 3
            quietly replace sec = 5.10 in 4
            twoway ///
                (pcarrowi `pos1' .95 `pos2' 3.50, color(black)) ///
                (pcarrowi `pos1' .95 `pos3' 3.50, color(black)) ///
                (scatter lincoms_treat1 sec in 2/3, msymbol(O) color(black) msize(3)) ///
                (scatter lincoms_treat1 sec in 1, msymbol(O) color(black) msize(3)) ///
                (pci `pos2' 5.00 `pos2' 5.10, color(black)) ///
                (pci `pos2' 5.10 `pos3' 5.10, color(black)) ///
                (pci `pos3' 5.00 `pos3' 5.10, color(black)) ///
                (pci `pos4' 5.10 `pos4' 5.18, color(black)), ///
                text(4 .70 "Before protest", place(w) size(3.5) justification(right)) ///
                text(4 3.74 "No Protest", place(e) size(3.5) justification(left)) ///
                text(`pos3' 3.74 "Protest", place(e) size(3.5) justification(left)) ///
                text(`pos4' 5.38 "p = `pval'", place(e) size(3)) ///
                legend(off) xlabel(, nogrid nolabels) xtitle(" ") ///
                ytitle("Effect of Down>Up on Number of Fires (x 1,000)") ///
                xscale(range(-.4 6.0) off) yscale(range(`ymin' `ymax')) ///
                ylabel(-20(20)140) ///
                graphregion(margin(small)) plotregion(margin(small)) ///
                yline(0, lcolor(black%75))
        }

        graph export "`output'_`numero'.png", as(png) replace
        display as result "Exported: `output'_`numero'.png"
        quietly graph drop _all
        quietly clear
    }
end
