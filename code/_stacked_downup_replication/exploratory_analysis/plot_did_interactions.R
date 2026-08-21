#!/usr/bin/env Rscript

# Shared DiD interaction renderer. The two post estimates are horizontally
# offset so that overlapping confidence intervals remain separately visible.
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

canonical_term <- function(term) {
  term <- gsub("(^|[:#])([0-9]+o?\\.)", "\\1", term, perl = TRUE)
  parts <- strsplit(gsub("#", ":", term, fixed = TRUE), ":", fixed = TRUE)[[1L]]
  paste(sort(parts), collapse = ":")
}

find_term <- function(beta, variables) {
  wanted <- paste(sort(variables), collapse = ":")
  hits <- names(beta)[vapply(names(beta), canonical_term, character(1L)) == wanted]
  if (length(hits) != 1L) {
    stop("Expected one coefficient for ", wanted, "; found: ", paste(hits, collapse = ", "))
  }
  hits
}

linear_result <- function(beta, vcov, weight, df, level) {
  estimate <- sum(weight * beta)
  se <- sqrt(drop(t(weight) %*% vcov %*% weight))
  critical <- qt(1 - (1 - level) / 2, df = df)
  c(estimate = estimate, se = se,
    lower = estimate - critical * se, upper = estimate + critical * se)
}

interaction_results <- function(beta, vcov, df, post_var, mod_var) {
  stopifnot(all(names(beta) %in% rownames(vcov)), all(names(beta) %in% colnames(vcov)))
  vcov <- vcov[names(beta), names(beta), drop = FALSE]
  unit_weight <- function(variables) {
    out <- setNames(numeric(length(beta)), names(beta))
    out[find_term(beta, variables)] <- 1
    out
  }

  w_pre <- unit_weight(mod_var)
  w_control_post <- w_pre + unit_weight(c(post_var, mod_var))
  w_treated_post <- w_control_post + unit_weight(c(post_var, "treat")) +
    unit_weight(c("treat", mod_var)) + unit_weight(c(post_var, "treat", mod_var))
  weights <- list(
    Pre = w_pre - w_pre,
    `Control post` = w_control_post - w_pre,
    `Treated post` = w_treated_post - w_pre,
    Difference = w_treated_post - w_control_post
  )

  out <- rbindlist(lapply(names(weights), function(group) {
    r95 <- linear_result(beta, vcov, weights[[group]], df, .95)
    r90 <- linear_result(beta, vcov, weights[[group]], df, .90)
    data.table(
      group = group, estimate = r95[["estimate"]], se = r95[["se"]],
      lower95 = r95[["lower"]], upper95 = r95[["upper"]],
      lower90 = r90[["lower"]], upper90 = r90[["upper"]]
    )
  }))
  out[, p_value := fifelse(se == 0, NA_real_, 2 * pt(-abs(estimate / se), df = df))]
  out
}

interaction_from_export <- function(coef_path, scalar_path, post_var = "post_",
                                    mod_var = "downup_ac_pop") {
  raw <- fread(coef_path)[reg == "evreg1"]
  beta <- setNames(as.numeric(raw$beta), raw$var)
  vcov <- as.matrix(raw[, grep("^cov[0-9]+$", names(raw), value = TRUE), with = FALSE])
  storage.mode(vcov) <- "double"
  rownames(vcov) <- colnames(vcov) <- raw$var
  df <- as.numeric(fread(scalar_path)[reg == "evreg1", df_r][1L])
  interaction_results(beta, vcov, df, post_var, mod_var)
}

interaction_from_fixest <- function(model, post_var = "post",
                                    mod_var = "downup_ac_pop") {
  beta <- coef(model)
  vcov <- vcov(model)
  df <- max(1, model$nobs - length(beta))
  interaction_results(beta, vcov, df, post_var, mod_var)
}

p_label <- function(p) {
  sprintf("p = %.3f", p)
}

plot_did_interaction <- function(results, output, type = c("politician", "protest"),
                                 y_range = NULL) {
  type <- match.arg(type)
  if (type == "politician") {
    x_pre <- .90; x_control <- 3.08; x_treated <- 3.42; x_post <- 3.25
    x_label <- 3.62; x_bracket <- 4.68; xlim <- c(-.35, 5.50)
    labels <- c("Non-Agricultural\nPolitician", "Agricultural\nPolitician")
    pre_label <- "Non-Agricultural\nPolitician"
  } else {
    x_pre <- .90; x_control <- 3.30; x_treated <- 3.70; x_post <- 3.50
    x_label <- 3.92; x_bracket <- 4.55; xlim <- c(-.40, 5.40)
    labels <- c("No Protest", "Protest")
    pre_label <- "Before protest"
  }

  if (is.null(y_range)) {
    observed <- range(
      c(results[group != "Difference", estimate], 0),
      finite = TRUE
    )
    padding <- max(diff(observed) * .12, 1)
    y_range <- observed + c(-padding, padding)
  }

  points <- copy(results[group != "Difference"])
  points[, x := c(x_pre, x_control, x_treated)]
  pre_y <- points[group == "Pre", estimate]
  control_y <- points[group == "Control post", estimate]
  treated_y <- points[group == "Treated post", estimate]
  difference_p <- results[group == "Difference", p_value]
  midpoint <- mean(c(control_y, treated_y))
  label_y <- c(control_y, treated_y)
  min_gap <- diff(y_range) * .09
  if (abs(diff(label_y)) < min_gap) {
    direction <- if (treated_y >= control_y) 1 else -1
    label_y <- midpoint + c(-direction, direction) * min_gap / 2
  }
  label_data <- data.table(
    x = x_label, y = label_y, point_x = c(x_control, x_treated),
    point_y = c(control_y, treated_y), label = labels
  )
  period_y <- y_range[1] + diff(y_range) * .06

  plot <- ggplot() +
    geom_hline(yintercept = 0, colour = "grey30", linetype = "dashed") +
    geom_segment(aes(x = x_pre + .05, y = pre_y,
                     xend = x_control - .08, yend = control_y),
                 arrow = grid::arrow(length = grid::unit(.09, "inches")), linewidth = .4) +
    geom_segment(aes(x = x_pre + .05, y = pre_y,
                     xend = x_treated - .08, yend = treated_y),
                 arrow = grid::arrow(length = grid::unit(.09, "inches")), linewidth = .4) +
    geom_point(data = points, aes(x = x, y = estimate), shape = 21,
               size = 3.3, fill = "black") +
    geom_segment(data = label_data,
                 aes(x = point_x + .05, y = point_y, xend = x - .04, yend = y),
                 linewidth = .3) +
    geom_text(data = label_data, aes(x = x, y = y, label = label),
              hjust = 0, size = 3.4, lineheight = .9) +
    annotate("text", x = x_pre - .17, y = pre_y, label = pre_label,
             hjust = 1, size = 3.4, lineheight = .9) +
    annotate("text", x = x_pre, y = period_y, label = "Pre", size = 3.5) +
    annotate("text", x = x_post, y = period_y, label = "Post", size = 3.5) +
    annotate("segment", x = x_bracket - .13, xend = x_bracket,
             y = control_y, yend = control_y) +
    annotate("segment", x = x_bracket - .13, xend = x_bracket,
             y = treated_y, yend = treated_y) +
    annotate("segment", x = x_bracket, xend = x_bracket,
             y = control_y, yend = treated_y) +
    annotate("segment", x = x_bracket, xend = x_bracket + .04,
             y = midpoint, yend = midpoint) +
    annotate("text", x = x_bracket + .09, y = midpoint,
             label = p_label(difference_p), hjust = 0, size = 3.1) +
    coord_cartesian(xlim = xlim, ylim = y_range, clip = "off") +
    labs(x = NULL, y = "Effect of Down>Up on Number of Fires (x 1,000)") +
    theme_classic(base_size = 12) +
    theme(
      panel.grid.major.y = element_line(colour = "grey90", linetype = "dashed"),
      axis.line.x = element_blank(), axis.text.x = element_blank(),
      axis.ticks.x = element_blank(), plot.margin = margin(8, 38, 8, 8)
    )
  ggsave(output, plot, width = 7.2, height = 4.4, dpi = 300)
  message("Generated: ", output)
}

render_cohort_sweep <- function(root, analysis = "all", first = 1L, last = 32L) {
  rel <- file.path("exploratory_analysis", "cohort_eventtime_fe_sweep")
  table_dir <- file.path(root, "tables", rel)
  figure_dir <- file.path(root, "figures", rel)
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  configs <- list(
    politician = list(prefix = "politician_byprov_cohorttime_fe", type = "politician"),
    protest = list(prefix = "protest_never_cohorttime_fe", type = "protest")
  )
  selected <- if (analysis == "all") names(configs) else analysis
  for (name in selected) {
    cfg <- configs[[name]]
    for (fe in first:last) {
      stem <- paste0(cfg$prefix, sprintf("%02d", fe),
                     "_did_interaction_rural_acpop_all")
      coef_path <- file.path(table_dir, paste0(stem, ".csv"))
      scalar_path <- file.path(table_dir, paste0(stem, "_scalars.csv"))
      if (!file.exists(coef_path) || !file.exists(scalar_path)) {
        stop("Missing interaction input for ", stem)
      }
      results <- interaction_from_export(coef_path, scalar_path)
      plot_did_interaction(
        results, file.path(figure_dir, paste0(stem, "_1.png")), cfg$type
      )
    }
  }
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  value_after <- function(flag, default = NULL) {
    at <- match(flag, args)
    if (is.na(at) || at == length(args)) default else args[[at + 1L]]
  }
  root <- value_after("--root", normalizePath(getwd(), winslash = "/"))
  analysis <- value_after("--analysis", "all")
  first <- as.integer(value_after("--first", "1"))
  last <- as.integer(value_after("--last", "32"))
  if (!analysis %in% c("all", "politician", "protest")) stop("Invalid --analysis")
  render_cohort_sweep(root, analysis, first, last)
}
