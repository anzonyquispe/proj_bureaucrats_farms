################################################################################

library(data.table)
library(doParallel)
library(dplyr)
library(HonestDiD)
library(ggplot2)

################################################################################


################################################################################
############## Functions Required to Compute EV and Honest #####################

mean_coef_test <- function(betahat, V, subset = NULL, df = 100, level = 0.95) {
  if (!is.null(subset)) {
    betahat <- betahat[subset]
    V <- V[subset, subset, drop = FALSE]
  }
  k <- length(betahat)
  w <- rep(1/k, k)                       # equal weights for the mean
  est <- as.numeric(crossprod(w, betahat))
  se  <- as.numeric(sqrt(t(w) %*% V %*% w))
  t   <- est / se
  crit <- if (is.null(df)) qnorm(1 - (1 - level)/2) else qt(1 - (1 - level)/2, df)
  p   <- if (is.null(df)) 2*pnorm(-abs(t)) else 2*pt(-abs(t), df)
  list(estimate = est, se = se, t = t, p = p,
       ci = c(est - crit*se, est + crit*se))
}
plot_honest_from_rds <- function(out, file_base, M=0.5, numPrePeriods = 4, numPostPeriods = 5,
                                  extra_args_relativeMagnitudes = list(),
                                  extra_args_sensitivityResults = list()) {


  ##############################################################################
  ##########################  Original Coefficients ############################

  # Read RDS file
  # out <- readRDS(rds_path)
  betahat <- out$beta
  sigma <- out$sigma

  # Sensitivity analysis
  base_args_rm <- list(
    betahat       = betahat,
    sigma         = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods= numPostPeriods,
    Mbarvec = seq(0.05,M,by=0.2),
    parallel = TRUE
  )
  delta_rm_results <- do.call(HonestDiD::createSensitivityResults_relativeMagnitudes,
                              c(base_args_rm, extra_args_relativeMagnitudes))

  # Original CS results
  originalResults <- HonestDiD::constructOriginalCS(
    betahat       = betahat,
    sigma         = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods= numPostPeriods
  )
  originalResults$Mbar <- 0

  # Plot
  p <- HonestDiD::createSensitivityPlot_relativeMagnitudes(delta_rm_results, originalResults) +
    labs( y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")

  # Save plot
  save_path <- file.path(figure_farms, paste0(file_base, "_honest1.png"))
  ggsave(save_path, plot = p, width = 8, height = 4, dpi = 300)


  base_args_sd <- list(
    betahat = betahat,
    sigma = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    Mvec = seq(0.05,M,by=0.2),
    parallel = TRUE
  )
  delta_sd_results <- do.call(HonestDiD::createSensitivityResults,
                              c(base_args_sd, extra_args_sensitivityResults))

  p3 <- createSensitivityPlot(delta_sd_results, originalResults) +
    labs( y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")

  # Save plot
  save_path <- file.path(figure_farms, paste0(file_base, "_honest2.png"))
  ggsave(save_path, plot = p3, width = 8, height = 4, dpi = 300)

  ##############################################################################


  #
  # ##############################################################################
  # ########################  Mean Original Coefficients #########################
  #
  # p <- length(betahat)
  # nobs <- numPostPeriods + 1
  # T <- matrix(0, nrow = nobs, ncol = p)
  # precols <- p-numPostPeriods
  # T[1, 1:precols] <- 1/precols
  # for (j in 1:numPostPeriods) {
  #   T[j+1, precols + j] <- 1
  # }
  #
  # beta_red <- drop(T %*% betahat)
  # V_red    <- T %*% sigma %*% t(T)
  # V_red    <- (V_red + t(V_red))/2
  #
  #
  # # Original CS results
  # originalResults <- HonestDiD::constructOriginalCS(
  #   betahat       = beta_red,
  #   sigma         = V_red,
  #   numPrePeriods = 1,
  #   numPostPeriods= numPostPeriods
  # )
  # originalResults$Mbar <- 0
  #
  #
  # # Sensitivity analysis
  # delta_rm_results <- HonestDiD::createSensitivityResults_relativeMagnitudes(
  #   betahat       = beta_red,
  #   sigma         = V_red,
  #   numPrePeriods = 1,
  #   numPostPeriods= numPostPeriods,
  #   Mbarvec = seq(0.05,M,by=0.2), #values of Mbar,
  #   parallel = TRUE
  # )
  #
  # p <- HonestDiD::createSensitivityPlot_relativeMagnitudes(delta_rm_results, originalResults) +
  #   labs( y = "Effect on Fires (1,000 units)", title = "") +
  #   theme_classic(base_size = 12) +
  #   theme(legend.position = "none")
  #
  # # Save plot
  # save_path <- file.path(figure_farms, paste0(file_base, "_meanpre_honest1.png"))
  # ggsave(save_path, plot = p, width = 8, height = 4, dpi = 300)
  #
  #
  #
  # delta_sd_results <-
  #   HonestDiD::createSensitivityResults(betahat = beta_red,
  #                                       sigma = V_red,
  #                                       numPrePeriods = 1,
  #                                       numPostPeriods = numPostPeriods,
  #                                       Mvec = seq(0.05,M,by=0.2), #values of Mbar,
  #                                       parallel = TRUE)
  # p3 <- HonestDiD::createSensitivityPlot(delta_sd_results, originalResults) +
  #   labs( y = "Effect on Fires (1,000 units)", title = "") +
  #   theme_classic(base_size = 12) +
  #   theme(legend.position = "none")
  #
  # # Save plot
  # save_path <- file.path(figure_farms, paste0(file_base, "_meanpre_honest2.png"))
  # ggsave(save_path, plot = p3, width = 8, height = 4, dpi = 300)
  #
  # ##############################################################################
  #
  #

  ##############################################################################
  ###########################  Rotated Coefficients ############################

  # Read RDS file
  # out <- readRDS(rds_path)
  betahat <- out$beta_rot
  sigma <- out$sigma

  # Sensitivity analysis
  base_args_rm_rot <- list(
    betahat       = betahat,
    sigma         = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods= numPostPeriods,
    Mbarvec = seq(0.05,M,by=0.2),
    parallel = TRUE
  )
  delta_rm_results <- do.call(HonestDiD::createSensitivityResults_relativeMagnitudes,
                              c(base_args_rm_rot, extra_args_relativeMagnitudes))

  # Original CS results
  originalResults <- HonestDiD::constructOriginalCS(
    betahat       = betahat,
    sigma         = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods= numPostPeriods
  )
  originalResults$Mbar <- 0

  # Plot
  p <- HonestDiD::createSensitivityPlot_relativeMagnitudes(delta_rm_results, originalResults) +
    labs( y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")

  # Save plot
  save_path <- file.path(figure_farms, paste0(file_base, "_rot_honest1.png"))
  ggsave(save_path, plot = p, width = 8, height = 4, dpi = 300)


  base_args_sd_rot <- list(
    betahat = betahat,
    sigma = sigma,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    Mvec = seq(0.05,M,by=0.2),
    parallel = TRUE
  )
  delta_sd_results <- do.call(HonestDiD::createSensitivityResults,
                              c(base_args_sd_rot, extra_args_sensitivityResults))

  p3 <- createSensitivityPlot(delta_sd_results, originalResults) +
    labs( y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")

  # Save plot
  save_path <- file.path(figure_farms, paste0(file_base, "_rot_honest2.png"))
  ggsave(save_path, plot = p3, width = 8, height = 4, dpi = 300)

  ##############################################################################

  #
  #
  # ##############################################################################
  # #####################Mean of Pre Rotated Coefficients#########################
  #
  # p <- length(betahat)
  # nobs <- numPostPeriods + 1
  # T <- matrix(0, nrow = nobs, ncol = p)
  # precols <- p-numPostPeriods
  # T[1, 1:precols] <- 1/precols
  # for (j in 1:numPostPeriods) {
  #   T[j+1, precols + j] <- 1
  # }
  #
  # beta_red <- drop(T %*% betahat)
  # V_red    <- T %*% sigma %*% t(T)
  # V_red    <- (V_red + t(V_red))/2
  #
  #
  # # Original CS results
  # originalResults <- HonestDiD::constructOriginalCS(
  #   betahat       = beta_red,
  #   sigma         = V_red,
  #   numPrePeriods = 1,
  #   numPostPeriods= numPostPeriods
  # )
  # originalResults$Mbar <- 0
  #
  #
  # # Sensitivity analysis
  # delta_rm_results <- HonestDiD::createSensitivityResults_relativeMagnitudes(
  #   betahat       = beta_red,
  #   sigma         = V_red,
  #   numPrePeriods = 1,
  #   numPostPeriods= numPostPeriods,
  #   Mbarvec = seq(0.05,M,by=0.2), #values of Mbar,
  #   parallel = TRUE
  # )
  #
  # p <- HonestDiD::createSensitivityPlot_relativeMagnitudes(delta_rm_results, originalResults) +
  #   labs( y = "Effect on Fires (1,000 units)", title = "") +
  #   theme_classic(base_size = 12) +
  #   theme(legend.position = "none")
  #
  # # Save plot
  # save_path <- file.path(figure_farms, paste0(file_base, "_rot_meanpre_honest1.png"))
  # ggsave(save_path, plot = p, width = 8, height = 4, dpi = 300)
  #
  #
  #
  # delta_sd_results <-
  #   HonestDiD::createSensitivityResults(betahat = beta_red,
  #                                       sigma = V_red,
  #                                       numPrePeriods = 1,
  #                                       numPostPeriods = numPostPeriods,
  #                                       Mvec = seq(0.05,M,by=0.2),
  #                                       parallel = TRUE)
  # p3 <- HonestDiD::createSensitivityPlot(delta_sd_results, originalResults) +
  #   labs( y = "Effect on Fires (1,000 units)", title = "") +
  #   theme_classic(base_size = 12) +
  #   theme(legend.position = "none")
  #
  # # Save plot
  # save_path <- file.path(figure_farms, paste0(file_base, "_rot_meanpre_honest2.png"))
  # ggsave(save_path, plot = p3, width = 8, height = 4, dpi = 300)
  message("Plot saved to: ", save_path)

  ##############################################################################
}
agregation_result <- function(ev, numPrePeriods = 4, numPostPeriods = 5, M = 1, honest = FALSE, omitted_period = -1,
                              xlab = "Time from Treatment (years)", ylab = "Effect on Fires (1,000 units)",
                              extra_args_relativeMagnitudes = list(),
                              extra_args_sensitivityResults = list()){
  # omitted_period: -1 (default) or 0
  # When omitted_period = -1: pre-periods are -numPrePeriods to -2, post-periods are 0 to numPostPeriods-1

  # When omitted_period = 0:  pre-periods are -numPrePeriods to -1, post-periods are 1 to numPostPeriods

  y0 <- mean(as.numeric(ev$ymean), rm.na = TRUE)
  V <- as.matrix(ev[,-c(1,2)])
  beta <- ev$beta
  out <- list(beta = beta, sigma = V )
  ev$se <- sqrt(diag(V))

  # Create time indices based on omitted period

  if (omitted_period == -1) {
    ev$term <- c(-numPrePeriods:-2, 0:(numPostPeriods-1))
    ev$t <- ev$term
    ev$est <- ev$beta
    ev <- ev %>% bind_rows(tibble(t = -1L, est = 0, se = 0)) %>%
      arrange(t) %>% as.data.table() %>%
      mutate(
        lb = est - 1.96 * se,
        ub = est + 1.96 * se
      )
    # Index of omitted period in sorted ev
    omitted_idx <- numPrePeriods
    x_breaks <- seq(-numPrePeriods, (numPostPeriods-1), by = 1)
  } else if (omitted_period == 0) {
    ev$term <- c(-numPrePeriods:-1, 1:numPostPeriods)
    ev$t <- ev$term
    ev$est <- ev$beta
    ev <- ev %>% bind_rows(tibble(t = 0L, est = 0, se = 0)) %>%
      arrange(t) %>% as.data.table() %>%
      mutate(
        lb = est - 1.96 * se,
        ub = est + 1.96 * se
      )
    # Index of omitted period in sorted ev
    omitted_idx <- numPrePeriods + 1
    x_breaks <- seq(-numPrePeriods, numPostPeriods, by = 1)
  } else {
    stop("omitted_period must be -1 or 0")
  }

  out.pre <- mean_coef_test(beta, V, subset= c(1:(numPrePeriods-1)))
  pre.coef <- round(out.pre$estimate,3)
  pre.se <- round(out.pre$se,3)
  out.post <- mean_coef_test(beta, V, subset= c((numPrePeriods):(numPrePeriods+(numPostPeriods-1))))
  post.coef <- round(out.post$estimate,3)
  post.se <- round(out.post$se,3)
  pp2 <- list(
    pre  = paste0(pre.coef, " (", pre.se, ")"),
    post = paste0(post.coef, " (", post.se, ")")
  )
  # 7) annotation  text
  ann <- paste0( " Mean DV = ",    round(y0,   3), "\n",
                 "Pre Avg =  ", pp2$pre,        "\n",
                 "Post Avg = ", pp2$post,       "\n"
  )



  p1 <- ggplot(ev, aes(x = t, y = est)) +
    # Ribbon for CI
    geom_ribbon(aes(ymin = lb, ymax = ub), fill = "#279FF5", alpha = 0.2) +
    # Line and points
    geom_line(color = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, color = "#279FF5") +
    # Reference lines
    geom_vline(xintercept = omitted_period, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    # Labels and scales
    labs(x = xlab, y = ylab) +
    scale_x_continuous(breaks = x_breaks) +
    # Theme
    theme(
      panel.background  = element_rect(fill = "white", colour = NA),
      plot.background   = element_rect(fill = "white", colour = NA),
      panel.grid.minor  = element_blank(),
      axis.line         = element_line(colour = "black"),
      axis.line.x.top   = element_blank(),
      axis.line.y.right = element_blank(),
      panel.grid.major   = element_line(colour = "gray70", linetype = "dashed"),
      legend.position   = "none"
    ) +
    annotate("text",
             x = -Inf, y = Inf,
             hjust = -0.1, vjust = 1.1,
             label = ann,
             size  = 4)
  save_path <- file.path(figure_farms, paste0(file_base, "_ori.png"))
  ggsave(save_path, plot = p1, width = 8, height = 4, dpi = 300)


  # Rotation: shift time so omitted period maps to 0 for fitting
  ev$tfake <- ev$t - omitted_period
  fit_pre <- lm(est ~ tfake - 1, data = ev[tfake <= 0,])
  ev$pr_tr <- 0
  ev$pr_tr <- predict(fit_pre, newdata = ev)
  ev$res_b <- ev$est - ev$pr_tr
  ev <- ev %>%
    mutate(
      lb = res_b - 1.96 * se,
      ub = res_b + 1.96 * se
    )

  # Extract rotated betas excluding the omitted period
  if (omitted_period == -1) {
    beta <- c(ev$res_b[1:(numPrePeriods-1)], ev$res_b[(numPrePeriods+1):(numPrePeriods+numPostPeriods)])
  } else {
    beta <- c(ev$res_b[1:numPrePeriods], ev$res_b[(numPrePeriods+2):(numPrePeriods+1+numPostPeriods)])
  }

  out.pre <- mean_coef_test(beta, V, subset= c(1:(numPrePeriods-1)))
  pre.coef <- round(out.pre$estimate,3)
  pre.se <- round(out.pre$se,3)
  out.post <- mean_coef_test(beta, V, subset= c((numPrePeriods):(numPrePeriods+(numPostPeriods-1))))
  post.coef <- round(out.post$estimate,3)
  post.se <- round(out.post$se,3)
  pp2 <- list(
    pre  = paste0(pre.coef, " (", pre.se, ")"),
    post = paste0(post.coef, " (", post.se, ")")
  )
  # 7) annotation  text
  ann <- paste0( " Mean DV = ",    round(y0,   3), "\n",
                 "Pre Avg =  ", pp2$pre,        "\n",
                 "Post Avg = ", pp2$post,       "\n"
  )

  out[['beta_rot']] <- beta

  p2 <- ggplot(ev, aes(x = t, y = res_b)) +
    # Ribbon for CI
    geom_ribbon(aes(ymin = lb, ymax = ub), fill = "#279FF5", alpha = 0.2) +
    # Line and points
    geom_line(color = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, color = "#279FF5") +
    # Reference lines
    geom_vline(xintercept = omitted_period, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    # Labels and scales
    labs(x = xlab, y = ylab) +
    scale_x_continuous(breaks = x_breaks) +
    # Theme
    theme(
      panel.background  = element_rect(fill = "white", colour = NA),
      plot.background   = element_rect(fill = "white", colour = NA),
      panel.grid.minor  = element_blank(),
      axis.line         = element_line(colour = "black"),
      axis.line.x.top   = element_blank(),
      axis.line.y.right = element_blank(),
      panel.grid.major   = element_line(colour = "gray70", linetype = "dashed"),
      legend.position   = "none"
    ) +
    annotate("text",
             x = -Inf, y = Inf,
             hjust = -0.1, vjust = 1.1,
             label = ann,
             size  = 4)

  save_path <- file.path(figure_farms, paste0(file_base, "_rotated.png"))
  ggsave(save_path, plot = p2, width = 8, height = 4, dpi = 300)

  if (honest){
    plot_honest_from_rds(out, file_base, M=M, numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods,
                         extra_args_relativeMagnitudes = extra_args_relativeMagnitudes,
                         extra_args_sensitivityResults = extra_args_sensitivityResults)
  }
}

################################################################################
options(datatable.print.nrows = 100)
