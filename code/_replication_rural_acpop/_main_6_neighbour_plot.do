cd "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms"

estread "tex/paper/tables/main_figure4_neighbour.ster"
est restore reg1
 clear
 set obs 20
*******************************************************************************

* 1. Grids closer to the downwind border in periods in which the wind is blown towards neighbor experience more fires

*******************************************************************************

	forval i = 1/4 {
		global control`i' `i'.dist_q
		global treat`i' `i'.dist_q#1.downwind_neighbours
	}
 		
			gen point1 = _b["$treat1"] 
			gen lo1 = _b["$treat1"]-1.96*_se["$treat1"]
			gen hi1 = _b["$treat1"]+1.96*_se["$treat1"]
	
			gen point2 = _b["$treat2"] 
			gen lo2 = _b["$treat2"]-1.96*_se["$treat2"]
			gen hi2 = _b["$treat2"]+1.96*_se["$treat2"]
		
			gen point3 = _b["$treat3"]
			gen lo3 = _b["$treat3"]-1.96*_se["$treat3"]
			gen hi3 = _b["$treat3"]+1.96*_se["$treat3"]
		
			gen point4 = _b["$treat4"]
			gen lo4 = _b["$treat4"]-1.96*_se["$treat4"]
			gen hi4 = _b["$treat4"]+1.96*_se["$treat4"]
			
			gen cpoint1 = _b["$control1"]
			gen clo1 = _b["$control1"]-1.96*_se["$control1"]
			gen chi1 = _b["$control1"]+1.96*_se["$control1"]
	
			gen cpoint2 = _b["$control2"]
			gen clo2 = _b["$control2"]-1.96*_se["$control2"]
			gen chi2 = _b["$control2"]+1.96*_se["$control2"]
		
			gen cpoint3 = _b["$control3"]
			gen clo3 = _b["$control3"]-1.96*_se["$control3"]
			gen chi3 = _b["$control3"]+1.96*_se["$control3"]
		
			gen cpoint4 = _b["$control4"]
			gen clo4 = _b["$control4"]-1.96*_se["$control4"]
			gen chi4 = _b["$control4"]+1.96*_se["$control4"]
 

			keep point1 lo1 hi1 point2 lo2 hi2 point3 lo3 hi3 point4 lo4 hi4 cpoint1 clo1 chi1 cpoint2 clo2 chi2 cpoint3 clo3 chi3 cpoint4 clo4 chi4
			duplicates drop
			
			save "tex/paper/figures/neighbor_output_main.dta", replace

*******************************************************************************
		use "tex/paper/figures/neighbor_output_main", clear

**# MAIN

set scheme plotplainblind, perm
		preserve
				keep cpoint1 clo1 chi1 cpoint2 clo2 chi2 cpoint3 clo3 chi3 cpoint4 clo4 chi4 
				rename (cpoint1 clo1 chi1 cpoint2 clo2 chi2 cpoint3 clo3 chi3 cpoint4 clo4 chi4 )(point1 lo1 hi1 point2 lo2 hi2 point3 lo3 hi3 point4 lo4 hi4 )
				tempfile c
				save `c'
		restore
			
			drop cpoint1 clo1 chi1 cpoint2 clo2 chi2 cpoint3 clo3 chi3 cpoint4 clo4 chi4 
			append using `c'
		
		gen point5=0
		gen lo5=0
		gen hi5=0
			
			
		gen x=_n
		
		preserve 
			replace x=x+2
			tempfile main
			save `main'
		restore
		
		reshape long point lo hi, i(x) j(order)
		
		sum point if order==4 & point>0
		local yd =`r(max)' +0.01
		
		twoway (scatter point order if x==1, m(S) mcolor(red))(connect point order if x==1, lp(solid) color(red)) (rarea lo hi order if x==1, color(red%10)) ///
			  (scatter point order if x==2, m(T) mcolor(blue))(connect point order if x==2, lp(solid) color(blue))(rarea lo hi order if x==2, color(blue%10)), ///
				xtitle("Distance from Assembly border segment g (quintiles)",size(medlarge)) ytitle("Effect on number of fires (x 1,000 units)",size(medlarge)) yline(0, lpattern(dash))  ///
				xlabel(1 "Closest" 5 "Farthest") legend(off) text(`yd' 3.8 "Differential effect" "at downwind border", placement(ne) color(red) justification(left) size(medlarge)) text(-0.005 1 "Effect" "at upwind border", placement(ne) color(blue) justification(left) size(medlarge)) name("a", replace)
				
		graph export "tex/paper/figures/neighbor_output.pdf", replace as(pdf)
				
				
				
		sum point if order==4 & point>0
		local yd =`r(max)' +0.01
		
		twoway (scatter point order if x==1, m(S) mcolor(black%0))(connect point order if x==1, lp(solid) color(black%0)) (rarea lo hi order if x==1, color(black%0)) ///
			  (scatter point order if x==2, m(T) mcolor(blue))(connect point order if x==2, lp(solid) color(blue))(rarea lo hi order if x==2, color(blue%10)), ///
				xtitle("Distance from Assembly border segment g (quintiles)",size(medlarge)) ytitle("Effect on number of fires (x 1,000 units)",size(medlarge)) yline(0, lpattern(dash))  ///
				xlabel(1 "Closest" 5 "Farthest") legend(off) text(`yd' 3.8 "Differential effect" "at downwind border", placement(ne) color(white) justification(left) size(medlarge)) text(-0.005 1 "Effect" "at upwind border", placement(ne) color(blue) justification(left) size(medlarge)) name("a", replace)
				
		graph export "tex/paper/figures/neighbor_upwind_output.pdf", replace as(pdf)
		
		