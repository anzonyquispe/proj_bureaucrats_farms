*! version 1.4  2026-08-21
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

    if "`yrange'" == "" {
        if "`type'" == "politician" {
            local ymin = -26
            local ymax = 40
        }
        else {
            local ymin = -26
            local ymax = 66
        }
    }
    else {
        tokenize `yrange'
        local ymin = `1'
        local ymax = `2'
    }

    foreach numero of numlist `estimates' {
        estimates restore `estname'`numero'
        tempname lincoms_treat
        matrix `lincoms_treat' = J(4, 5, .)

        quietly lincom 1.`modvar'
        local control_pre_b = r(estimate)
        local control_pre_lb95 = r(lb)
        local control_pre_ub95 = r(ub)
        matrix `lincoms_treat'[1,1] = r(estimate)
        matrix `lincoms_treat'[1,2] = r(ub)
        matrix `lincoms_treat'[1,3] = r(lb)

        quietly lincom 1.`modvar' + 1.post_#1.`modvar'
        local control_post_b = r(estimate)
        local control_post_lb95 = r(lb)
        local control_post_ub95 = r(ub)
        matrix `lincoms_treat'[2,1] = r(estimate)
        matrix `lincoms_treat'[2,2] = r(ub)
        matrix `lincoms_treat'[2,3] = r(lb)

        local treated_expr "1.post_#1.treat + 1.`modvar' + 1.post_#1.`modvar' + 1.treat#1.`modvar' + 1.post_#1.treat#1.`modvar'"
        local control_expr "1.`modvar' + 1.post_#1.`modvar'"

        quietly lincom (`treated_expr')
        local treated_post_b = r(estimate)
        local treated_post_lb95 = r(lb)
        local treated_post_ub95 = r(ub)
        matrix `lincoms_treat'[3,1] = r(estimate)
        matrix `lincoms_treat'[3,2] = r(ub)
        matrix `lincoms_treat'[3,3] = r(lb)

        quietly lincom (`treated_expr') - (`control_expr')
        local difference_b = r(estimate)
        local difference_se = r(se)
        local difference_lb95 = r(lb)
        local difference_ub95 = r(ub)
        local difference_p = r(p)
        matrix `lincoms_treat'[4,1] = r(estimate)
        matrix `lincoms_treat'[4,2] = r(ub)
        matrix `lincoms_treat'[4,3] = r(lb)

        quietly lincom 1.`modvar', level(90)
        local control_pre_lb90 = r(lb)
        local control_pre_ub90 = r(ub)
        matrix `lincoms_treat'[1,4] = r(ub)
        matrix `lincoms_treat'[1,5] = r(lb)
        quietly lincom `control_expr', level(90)
        local control_post_lb90 = r(lb)
        local control_post_ub90 = r(ub)
        matrix `lincoms_treat'[2,4] = r(ub)
        matrix `lincoms_treat'[2,5] = r(lb)
        quietly lincom (`treated_expr'), level(90)
        local treated_post_lb90 = r(lb)
        local treated_post_ub90 = r(ub)
        matrix `lincoms_treat'[3,4] = r(ub)
        matrix `lincoms_treat'[3,5] = r(lb)
        quietly lincom (`treated_expr') - (`control_expr'), level(90)
        local difference_lb90 = r(lb)
        local difference_ub90 = r(ub)
        matrix `lincoms_treat'[4,4] = r(ub)
        matrix `lincoms_treat'[4,5] = r(lb)

        local pval : display %6.4f `difference_p'
        local pval = strtrim("`pval'")

        display as text ""
        display as result "INTERACTION AUDIT: `type', estimate `estname'`numero', moderator `modvar'"
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

        clear
        svmat double `lincoms_treat', names(lincoms_treat)
        gen sec = .

        local pos1 = lincoms_treat1[1]
        local pos2 = lincoms_treat1[2]
        local pos3 = lincoms_treat1[3]
        local pos4 = (`pos2' + `pos3') / 2

        if "`type'" == "politician" {
            replace sec = 0.9 in 1
            * Separate the two post estimates horizontally so overlapping
            * confidence intervals remain visible. This changes presentation
            * only; estimates and intervals are unchanged.
            replace sec = 3.08 in 2
            replace sec = 3.42 in 3
            replace sec = 3.2 in 4
            set obs 5
            replace lincoms_treat2 = lincoms_treat1[2] in 5
            replace lincoms_treat3 = lincoms_treat1[3] in 5
            replace sec = 4.2 in 5
            local text_ypos = `ymin' + 4

            twoway ///
                (pcarrowi `pos1' .95 `pos2' 3.00, color(black)) ///
                (pcarrowi `pos1' .95 `pos3' 3.34, color(black)) ///
                (rbar lincoms_treat2 lincoms_treat3 sec in 1, color(black) barwidth(.02)) ///
                (rbar lincoms_treat2 lincoms_treat3 sec in 2/3, color(black) barwidth(.02)) ///
                (rbar lincoms_treat4 lincoms_treat5 sec in 1, color(black) barwidth(.04)) ///
                (rbar lincoms_treat4 lincoms_treat5 sec in 2/3, color(black) barwidth(.04)) ///
                (scatter lincoms_treat1 sec in 1, msymbol(O) color(black) msize(3)) ///
                (scatter lincoms_treat1 sec in 2/3, msymbol(O) color(black) msize(3)) ///
                (pci `pos2' 4.55 `pos2' 4.68, color(black)) ///
                (pci `pos2' 4.68 `pos3' 4.68, color(black)) ///
                (pci `pos3' 4.55 `pos3' 4.68, color(black)) ///
                (pci `pos4' 4.68 `pos4' 4.72, color(black)), ///
                legend(off) ///
                text(`pos1' .77 "Non-Agricultural" "Politician", place(w) size(3.5) justification(left)) ///
                text(`pos2' 3.58 "Non-Agricultural" "Politician", place(e) size(3.5) justification(left)) ///
                text(`pos3' 3.58 "Agricultural" "Politician", place(e) size(3.5) justification(left)) ///
                text(`text_ypos' .9 "Pre", place(c) size(3.5)) ///
                text(`text_ypos' 3.25 "Post", place(c) size(3.5)) ///
                text(`pos4' 4.75 "p-value" "`pval'", place(e) size(3)) ///
                xlabel(, nogrid nolabels) xtitle(" ") ///
                ytitle("Effect of Down>Up on Number of Fires (x 1,000)") ///
                xscale(range(-.35 5.5) off) yscale(range(`ymin' `ymax')) ///
                yline(0, lcolor(black%75))
        }
        else {
            replace sec = .9 in 1
            replace sec = 3.30 in 2
            replace sec = 3.70 in 3
            replace sec = 4.7 in 4
            local text_ypos = `ymin' + .5

            twoway ///
                (pcarrowi `pos1' .95 `pos2' 3.22, color(black)) ///
                (pcarrowi `pos1' .95 `pos3' 3.62, color(black)) ///
                (rbar lincoms_treat2 lincoms_treat3 sec in 2/3, color(black) barwidth(.02)) ///
                (rbar lincoms_treat2 lincoms_treat3 sec in 1, color(black) barwidth(.02)) ///
                (rbar lincoms_treat4 lincoms_treat5 sec in 2/3, color(black) barwidth(.04)) ///
                (rbar lincoms_treat4 lincoms_treat5 sec in 1, color(black) barwidth(.04)) ///
                (scatter lincoms_treat1 sec in 2/3, msymbol(O) color(black) msize(3)) ///
                (scatter lincoms_treat1 sec in 1, msymbol(O) color(black) msize(3)) ///
                (pci `pos2' 4.40 `pos2' 4.50, color(black)) ///
                (pci `pos2' 4.50 `pos3' 4.50, color(black)) ///
                (pci `pos3' 4.40 `pos3' 4.50, color(black)) ///
                (pci `pos4' 4.50 `pos4' 4.58, color(black)), ///
                text(`pos1' .75 "Before protest", place(w) size(3.5)) ///
                text(`text_ypos' .9 "Pre", place(c) size(3.5)) ///
                text(`pos2' 4.15 "No Protest", place(w) size(3.5)) ///
                text(`pos3' 4.15 "Protest", place(w) size(3.5)) ///
                text(`text_ypos' 3.5 "Post", place(c) size(3.5)) ///
                text(`pos4' 4.6 "p = `pval'", place(e) size(3)) ///
                legend(off) xlabel(, nogrid nolabels) ylabel(#6) xtitle(" ") ///
                ytitle("Effect of Down>Up on Number of Fires (x 1,000)") ///
                xscale(range(-.4 5.4) off) yscale(range(`ymin' `ymax')) ///
                yline(0, lcolor(black%75))
        }

        graph export "`output'_`numero'.png", as(png) replace
        display as result "Exported: `output'_`numero'.png"
    }
end
