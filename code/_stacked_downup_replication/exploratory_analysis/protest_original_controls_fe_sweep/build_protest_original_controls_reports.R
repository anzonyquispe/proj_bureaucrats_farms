#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
find_repo <- function(x) { x <- normalizePath(x, winslash="/", mustWork=FALSE); repeat { if (dir.exists(file.path(x,"code","_stacked_downup_replication"))) return(x); y<-dirname(x); if(identical(x,y)) return(""); x<-y } }
root <- find_repo(getwd()); args <- commandArgs(TRUE)
if (length(args)) { if (length(args)!=2L || args[[1]]!="--root") stop("Usage: [--root REPO]"); root <- args[[2]] }
rel <- file.path("exploratory_analysis", "protest_original_controls_fe_sweep")
tabdir <- file.path(root,"tables",rel); figdir <- file.path(root,"figures",rel)
reportdir <- file.path(root,"code","_report"); dir.create(reportdir,recursive=TRUE,showWarnings=FALSE)
coefs <- fread(file.path(tabdir,"protest_original_controls_coefficients.csv"))
avgs <- fread(file.path(tabdir,"protest_original_controls_pre_post_averages.csv"))
lp <- function(x) paste0("\\detokenize{", normalizePath(x,winslash="/",mustWork=TRUE), "}")
fmt <- function(x) sprintf("%.4f",x); ci <- function(a,b) sprintf("[%.4f, %.4f]",a,b)
labels <- c(never="Never-treated controls", both="Never-treated and not-yet-treated controls", notyet="Legacy not-yet/partial-zero-spell controls")

for (controls in names(labels)) {
  lines <- c("\\documentclass[10pt]{article}","\\usepackage[letterpaper,landscape,margin=.55in]{geometry}","\\usepackage{graphicx}","\\usepackage{booktabs}","\\usepackage[hidelinks]{hyperref}","\\setlength{\\parindent}{0pt}",
    "\\title{Stacked Protest Analysis: Exploratory Fixed-Effect Results}",paste0("\\author{",labels[[controls]],"}"),"\\date{August 2026}","\\begin{document}","\\maketitle",
    "\\begin{abstract}Thirty-two fixed-effect specifications are compared. Each section reports the protest event study for relative years -8 through 1, omitting -1, its pretrend-rotated version, and the non-rotated DiD interaction post $\\times$ treat $\\times$ downup\\_ac\\_pop.\\end{abstract}","\\tableofcontents","\\clearpage")
  for (fe in 1:32) {
    stem <- sprintf("protest_original_fe%02d_controls_%s",fe,controls)
    ori <- file.path(figdir,paste0(stem,"_event_ori.png")); rot <- file.path(figdir,paste0(stem,"_event_rotated.png")); did <- file.path(figdir,paste0(stem,"_did_interaction_rural_acpop_all_1.png"))
    if (any(!file.exists(c(ori,rot,did)))) stop("Missing figures for ",stem)
    lines <- c(lines,paste0("\\section{Fixed-effect specification ",fe,"}"),"\\begin{center}","\\begin{minipage}[t]{.48\\textwidth}\\centering\\textbf{Event study: original}\\par\\smallskip",paste0("\\includegraphics[width=\\textwidth]{",lp(ori),"}"),"\\end{minipage}\\hfill","\\begin{minipage}[t]{.48\\textwidth}\\centering\\textbf{Event study: pretrend rotated}\\par\\smallskip",paste0("\\includegraphics[width=\\textwidth]{",lp(rot),"}"),"\\end{minipage}\\par\\medskip","\\textbf{DiD interaction: post $\\times$ treat $\\times$ downup\\_ac\\_pop}\\par\\smallskip",paste0("\\includegraphics[width=.54\\textwidth]{",lp(did),"}"),"\\end{center}","\\clearpage")
    a <- coefs[control_sample==controls & fe_id==fe & version=="original"][order(time)]
    b <- coefs[control_sample==controls & fe_id==fe & version=="rotated"][order(time)]
    z <- avgs[control_sample==controls & fe_id==fe]
    if(nrow(a)!=10L || nrow(b)!=10L) stop("Expected ten event times for ",stem)
    lines <- c(lines,paste0("\\subsection*{Event-study estimates: specification ",fe,"}"),"\\begin{center}\\scriptsize","\\begin{tabular}{r rr rr}","\\toprule","Event time & Original $\\hat\\beta$ & Original 95\\% CI & Rotated $\\hat\\beta$ & Rotated 95\\% CI \\\\","\\midrule")
    for(j in 1:10) lines <- c(lines,paste0(a$time[j]," & ",fmt(a$beta[j])," & ",ci(a$lower[j],a$upper[j])," & ",fmt(b$beta[j])," & ",ci(b$lower[j],b$upper[j])," \\\\"))
    for(p in c("pre","post")) { ao<-z[version=="original" & period==p]; ar<-z[version=="rotated" & period==p]; lines<-c(lines,if(p=="pre")"\\midrule" else character(),paste0(if(p=="pre")"Pre average" else "Post average"," & ",fmt(ao$estimate)," & ",ci(ao$lower,ao$upper)," & ",fmt(ar$estimate)," & ",ci(ar$lower,ar$upper)," \\\\")) }
    lines <- c(lines,"\\bottomrule","\\end{tabular}","\\end{center}","\\clearpage")
  }
  lines <- c(lines,"\\end{document}")
  writeLines(lines,file.path(reportdir,paste0("protest_original_controls_",controls,"_report.tex")),useBytes=TRUE)
}
