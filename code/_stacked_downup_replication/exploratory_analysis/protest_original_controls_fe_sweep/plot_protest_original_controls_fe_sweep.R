#!/usr/bin/env Rscript

# Protest FE-sweep renderer. The visual grammar and pretrend rotation reproduce
# plotting_event_studies.R; averages are recomputed from the rotated estimates.

suppressPackageStartupMessages({library(data.table); library(ggplot2)})
setDTthreads(1L)

find_repo <- function(start) {
  x <- normalizePath(start, winslash = "/", mustWork = FALSE)
  if (file.exists(x)) x <- dirname(x)
  repeat {
    if (dir.exists(file.path(x, "code", "_stacked_downup_replication"))) return(x)
    y <- dirname(x); if (identical(x, y)) return(""); x <- y
  }
}
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
start <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else getwd()
cfg <- list(
  root = find_repo(start), output_root = find_repo(start), sample = FALSE,
  controls = c("never", "both", "notyet")
)
args <- commandArgs(TRUE); i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--root" && i < length(args)) {
    cfg$root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--output-root" && i < length(args)) {
    cfg$output_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--sample") {
    cfg$sample <- TRUE; i <- i + 1L
  } else if (args[[i]] == "--controls" && i < length(args)) {
    cfg$controls <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
    i <- i + 2L
  } else stop("Unknown or incomplete argument: ", args[[i]])
}
if (!nzchar(cfg$root) || !nzchar(cfg$output_root)) stop("Repository root not found.")
if (length(setdiff(cfg$controls, c("never", "both", "notyet")))) {
  stop("Unknown control group requested.")
}

rel <- file.path("exploratory_analysis", "protest_original_controls_fe_sweep")
if (isTRUE(cfg$sample)) rel <- file.path(rel, "sample")
tabdir <- file.path(cfg$root, "tables", rel)
figdir <- file.path(cfg$output_root, "figures", rel)
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)

mean_test <- function(b, v, idx) {
  w <- rep(1 / length(idx), length(idx))
  c(estimate = mean(b[idx]), se = sqrt(drop(t(w) %*% v[idx, idx] %*% w)))
}
read_event <- function(path) {
  x <- fread(path)[reg == "evreg1"]
  if (nrow(x) < 21L || ncol(x) < 25L) stop(basename(path), ": unexpected CSV layout")
  x <- x[13:21, c(3, 4, 17:25), with = FALSE]
  x[, c(2L, 1L, 3:ncol(x)), with = FALSE]
}

render <- function(x, stem, fe, controls) {
  setnames(x, names(x)[1:2], c("ymean", "beta"))
  x[, beta := as.numeric(beta)]
  v <- as.matrix(x[, -(1:2)]); storage.mode(v) <- "double"
  times <- c(-8:-2, 0:1); pre <- 1:7; post <- 8:9
  if (!identical(dim(v), c(9L, 9L))) stop(stem, ": expected 9x9 covariance")
  x[, `:=`(time = times, se = sqrt(diag(v)))]
  full <- rbind(x[, .(time, beta, se)], data.table(time = -1L, beta = 0, se = 0))
  setorder(full, time)
  depmean <- mean(as.numeric(x$ymean), na.rm = TRUE)
  original_pre <- mean_test(x$beta, v, pre); original_post <- mean_test(x$beta, v, post)

  shifted <- times + 1
  slope_w <- numeric(9); slope_w[pre] <- shifted[pre] / sum(shifted[pre]^2)
  rotation <- diag(9) - outer(shifted, slope_w)
  rb <- drop(rotation %*% x$beta); rv <- rotation %*% v %*% t(rotation)
  rotated_pre <- mean_test(rb, rv, pre); rotated_post <- mean_test(rb, rv, post)
  full[time != -1, rotated := rb]; full[time == -1, rotated := 0]
  full[, `:=`(lower = beta - 1.96 * se, upper = beta + 1.96 * se,
              lower_rot = rotated - 1.96 * se, upper_rot = rotated + 1.96 * se)]

  theme_es <- theme_classic(base_size = 12) + theme(
    panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
    panel.grid.minor = element_blank(), legend.position = "none")
  make_plot <- function(y, lo, hi, labels, ylabel, suffix) {
    span <- diff(range(c(full[[lo]], full[[hi]]), na.rm = TRUE)); if (!is.finite(span) || span == 0) span <- 1
    ann <- data.table(time = -8, value = max(full[[hi]], na.rm = TRUE) - (0:2) * span * .07, label = labels)
    p <- ggplot(full, aes(x = time, y = .data[[y]])) +
      geom_ribbon(aes(ymin = .data[[lo]], ymax = .data[[hi]]), fill = "#279FF5", alpha = .2) +
      geom_line(colour = "#279FF5", linewidth = .8) + geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
      geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
      geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
      scale_x_continuous(breaks = -8:1) + labs(x = "Years from Protest", y = ylabel) +
      geom_text(data = ann, aes(time, value, label = label), inherit.aes = FALSE, hjust = 0, vjust = 1, size = 4) + theme_es
    ggsave(file.path(figdir, paste0(stem, suffix)), p, width = 8, height = 4, dpi = 300)
  }
  make_plot("beta", "lower", "upper", c(sprintf("Mean DV = %.3f", depmean),
    sprintf("Pre Avg = %.3f (%.3f)", original_pre[1], original_pre[2]),
    sprintf("Post Avg = %.3f (%.3f)", original_post[1], original_post[2])),
    "Effect on Number of Fires (in 1,000 units)", "_ori.png")
  make_plot("rotated", "lower_rot", "upper_rot", c(sprintf("Mean DV = %.3f", depmean),
    sprintf("Pre Avg = %.3f (%.3f)", rotated_pre[1], rotated_pre[2]),
    sprintf("Post Avg = %.3f (%.3f)", rotated_post[1], rotated_post[2])),
    "Detrended Effect on Fires (in 1,000 units)", "_rotated.png")

  coef <- rbind(
    data.table(fe_id=fe, control_sample=controls, version="original", time=full$time, beta=full$beta, se=full$se, lower=full$lower, upper=full$upper),
    data.table(fe_id=fe, control_sample=controls, version="rotated", time=full$time, beta=full$rotated, se=full$se, lower=full$lower_rot, upper=full$upper_rot))
  avg <- rbind(
    data.table(fe_id=fe, control_sample=controls, version="original", period=c("pre","post"), estimate=c(original_pre[1],original_post[1]), se=c(original_pre[2],original_post[2])),
    data.table(fe_id=fe, control_sample=controls, version="rotated", period=c("pre","post"), estimate=c(rotated_pre[1],rotated_post[1]), se=c(rotated_pre[2],rotated_post[2])))
  avg[, `:=`(lower=estimate-1.96*se, upper=estimate+1.96*se)]
  list(coef=coef, avg=avg)
}

coefs <- list(); avgs <- list(); k <- 1L; missing <- character()
for (controls in cfg$controls) for (fe in 1:32) {
  stem <- sprintf("protest_original_fe%02d_controls_%s", fe, controls)
  path <- file.path(tabdir, paste0(stem, "_event_rural_acpop_all.csv"))
  if (!file.exists(path)) { missing <- c(missing, path); next }
  ans <- render(read_event(path), paste0(stem, "_event"), fe, controls)
  coefs[[k]] <- ans$coef; avgs[[k]] <- ans$avg; k <- k + 1L
}
if (length(missing)) stop("Missing event-study CSV files:\n", paste(missing, collapse="\n"))
fwrite(rbindlist(coefs), file.path(tabdir, "protest_original_controls_coefficients.csv"))
fwrite(rbindlist(avgs), file.path(tabdir, "protest_original_controls_pre_post_averages.csv"))
message("Completed ", length(cfg$controls) * 32L,
        " original and rotated protest figure pairs.")
