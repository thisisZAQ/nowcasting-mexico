# scripts/04_evaluate/evaluate.R
# Computes RMSE, MAE, MAPE across all models
# Runs Diebold-Mariano tests against AR benchmark
# Outputs: outputs/tables/forecast_errors.csv
#          outputs/tables/dm_test_results.csv

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg       <- yaml::read_yaml(here("config", "config.yaml"))
final_dir <- here("colombia", "data", "final")
out_dir   <- here("colombia/outputs", "tables")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# ── Load all forecasts ────────────────────────────────────────────────────────
cat("Loading forecasts...\n")

ar   <- read_csv(file.path(final_dir, "forecasts_ar.csv"),
                 show_col_types=FALSE) |>
  select(date, actual, forecast_ar)

dfm_b <- read_csv(file.path(final_dir, "forecasts_dfm_benchmark.csv"),
                  show_col_types=FALSE) |>
  select(date, forecast_dfm_benchmark)

dfm_a <- read_csv(file.path(final_dir, "forecasts_dfm_augmented.csv"),
                  show_col_types=FALSE) |>
  select(date, forecast_dfm_augmented)

ml <- read_csv(file.path(final_dir, "forecasts_ml.csv"),
               show_col_types=FALSE) |>
  select(date, forecast_lasso, forecast_ridge, forecast_rf)

all_fc <- ar |>
  left_join(dfm_b, by="date") |>
  left_join(dfm_a, by="date") |>
  left_join(ml,    by="date") |>
  mutate(date=as.Date(date)) |>
  arrange(date)

cat(sprintf("Combined: %d observations\n", nrow(all_fc)))

# ── Forecast error metrics ────────────────────────────────────────────────────
forecast_cols <- c("forecast_ar", "forecast_dfm_benchmark",
                   "forecast_dfm_augmented", "forecast_lasso",
                   "forecast_ridge", "forecast_rf")

model_labels <- c("AR(4)", "DFM Benchmark", "DFM Augmented",
                  "LASSO", "Ridge", "Random Forest")

metrics <- lapply(seq_along(forecast_cols), function(i) {
  col    <- forecast_cols[i]
  e      <- all_fc$actual - all_fc[[col]]
  valid  <- !is.na(e)
  rmse   <- sqrt(mean(e[valid]^2))
  mae    <- mean(abs(e[valid]))
  mape   <- mean(abs(e[valid] / all_fc$actual[valid]) * 100)
  tibble(
    model = model_labels[i],
    n_forecasts = sum(valid),
    RMSE  = round(rmse, 6),
    MAE   = round(mae, 6),
    MAPE  = round(mape, 4)
  )
})

errors_df <- bind_rows(metrics) |>
  arrange(RMSE)

cat("\n── Forecast accuracy ────────────────────────────────────────────────\n")
print(errors_df)

write_csv(errors_df, file.path(out_dir, "forecast_errors.csv"))
cat(sprintf("\nSaved -> outputs/tables/forecast_errors.csv\n"))

# ── Diebold-Mariano test ──────────────────────────────────────────────────────
cat("\n── Diebold-Mariano tests (vs AR benchmark) ──────────────────────────\n")

dm_test <- function(actual, fc1, fc2) {
  e1 <- actual - fc1
  e2 <- actual - fc2
  d  <- e2^2 - e1^2
  valid <- !is.na(d)
  d <- d[valid]
  n <- length(d)
  if (n < 10) return(list(stat=NA, pval=NA))
  d_mean <- mean(d)
  # HAC variance (Newey-West with 1 lag)
  gamma0 <- var(d)
  gamma1 <- sum((d[-1] - d_mean) * (d[-n] - d_mean)) / n
  hac_var <- (gamma0 + 2 * gamma1) / n
  if (hac_var <= 0) return(list(stat=NA, pval=NA))
  stat <- d_mean / sqrt(hac_var)
  pval <- 2 * (1 - pnorm(abs(stat)))
  list(stat=round(stat, 3), pval=round(pval, 4))
}

benchmark_fc <- all_fc$forecast_ar
dm_results <- lapply(forecast_cols[-1], function(col) {
  res <- dm_test(all_fc$actual, benchmark_fc, all_fc[[col]])
  tibble(
    model      = model_labels[which(forecast_cols == col)],
    DM_stat    = res$stat,
    p_value    = res$pval,
    significant = ifelse(!is.na(res$pval), res$pval < 0.05, NA)
  )
})

dm_df <- bind_rows(dm_results)
cat("\nDM test: negative stat = alternative model beats AR\n")
print(dm_df)

write_csv(dm_df, file.path(out_dir, "dm_test_results.csv"))
cat("Saved -> outputs/tables/dm_test_results.csv\n")
