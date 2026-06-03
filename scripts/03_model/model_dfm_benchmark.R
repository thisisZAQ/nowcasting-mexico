# scripts/03_model/model_dfm_benchmark.R
# Dynamic Factor Model — traditional data only (benchmark)
# Uses nowcasting package 2s method (all monthly variables)
# Output: data/final/forecasts_dfm_benchmark.csv

library(dplyr)
library(readr)
library(yaml)
library(here)
library(nowcasting)

cfg       <- yaml::read_yaml(here("config", "config.yaml"))
oos_start <- as.Date(cfg$evaluation$pseudo_oos_start)
r         <- cfg$models$benchmark_dfm$factors
p         <- cfg$models$benchmark_dfm$lags
final_dir <- here("data", "final")

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading dataset...\n")
df <- read_csv(file.path(final_dir, "dataset_traditional.csv"),
               show_col_types = FALSE) |>
  mutate(date = as.Date(date)) |>
  filter(!is.na(igae_ldiff))

cat(sprintf("Sample: %s to %s (%d obs)\n",
            min(df$date), max(df$date), nrow(df)))

# Variables for DFM — exclude retail (too many NAs before 2017)
dfm_vars <- c("igae_ldiff", "ip_ldiff", "unemp_diff",
              "fx_ldiff", "cetes_diff", "m1_ldiff", "credit_ldiff")

# All variables are monthly frequency
frequency <- rep(12, length(dfm_vars))

# ── Pseudo OOS expanding window ───────────────────────────────────────────────
oos_idx   <- which(df$date >= oos_start)
forecasts <- rep(NA_real_, length(oos_idx))

cat(sprintf("Running %d OOS forecasts (r=%d, p=%d)...\n",
            length(oos_idx), r, p))

for (i in seq_along(oos_idx)) {
  t     <- oos_idx[i]
  train <- df[1:(t-1), dfm_vars]

  if (nrow(train) < 30) next

  tryCatch({
    start_yr <- as.integer(format(df$date[1], "%Y"))
    start_mo <- as.integer(format(df$date[1], "%m"))

    # Apply Bpanel transformation (trans=0 = no transformation, already stationary)
    trans  <- rep(0, length(dfm_vars))
    X_mat  <- as.matrix(train)
    X_ts   <- ts(X_mat, start = c(start_yr, start_mo), frequency = 12)
    X_bp   <- Bpanel(base = X_ts, trans = trans, NA.replace = TRUE, na.prop = 0.5)

    fit <- nowcast(
      formula   = igae_ldiff ~ .,
      data      = X_bp,
      r         = r,
      p         = p,
      q         = r,
      method    = "2s",
      frequency = frequency
    )

    fc <- tail(fit$yfcst[, "out"], 1)
    forecasts[i] <- as.numeric(fc)

  }, error = function(e) {
    cat(sprintf("  t=%s ERROR: %s\n", df$date[t], conditionMessage(e)))
  })

  if (i %% 20 == 0) cat(sprintf("  %d/%d done\n", i, length(oos_idx)))
}

# ── Compile and save ──────────────────────────────────────────────────────────
results <- df[oos_idx, c("date", "igae_ldiff")] |>
  mutate(forecast_dfm_benchmark = forecasts, model = "DFM_benchmark") |>
  rename(actual = igae_ldiff)

non_na <- sum(!is.na(results$forecast_dfm_benchmark))
cat(sprintf("\nForecasts: %d (non-NA: %d)\n", nrow(results), non_na))

write_csv(results, file.path(final_dir, "forecasts_dfm_benchmark.csv"))
cat("Saved -> data/final/forecasts_dfm_benchmark.csv\n")

if (non_na > 0) {
  rmse <- sqrt(mean((results$actual - results$forecast_dfm_benchmark)^2, na.rm=TRUE))
  cat(sprintf("DFM benchmark RMSE: %.6f\n", rmse))
}
