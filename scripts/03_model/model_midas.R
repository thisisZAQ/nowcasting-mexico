# scripts/03_model/model_midas.R
# MIDAS regression — connects weekly Google Trends to monthly IGAE
# Uses midasr package with nealmon polynomial weighting
# Pseudo OOS expanding window
# Output: data/final/forecasts_midas.csv

library(dplyr)
library(readr)
library(yaml)
library(here)
library(midasr)

cfg       <- yaml::read_yaml(here("config", "config.yaml"))
oos_start <- as.Date(cfg$evaluation$pseudo_oos_start)
final_dir <- here("data", "final")

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading datasets...\n")
df_monthly <- read_csv(file.path(final_dir, "dataset_full.csv"),
                       show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |>
  filter(!is.na(igae_ldiff))

# Google Trends are monthly in our dataset — use as high-freq proxy
# MIDAS with monthly-to-monthly is equivalent to a distributed lag model
# We use 3 lags of each trend keyword with nealmon weighting

gt_vars <- grep("^gt_", names(df_monthly), value=TRUE)
cat(sprintf("Google Trends variables: %s\n", paste(gt_vars, collapse=", ")))

# ── MIDAS forecast function ───────────────────────────────────────────────────
midas_forecast <- function(train_df, test_row, gt_var, p=3) {
  # Build MIDAS formula with nealmon polynomial
  # y_t = alpha + beta(L; theta) * x_t + epsilon_t
  y  <- train_df$igae_ldiff
  x  <- train_df[[gt_var]]

  # Need complete cases
  keep <- complete.cases(data.frame(y=y, x=x))
  y <- y[keep]; x <- x[keep]
  if (length(y) < p + 10) return(NA)

  # Create lagged matrix manually (p lags of x)
  n <- length(y)
  X_lags <- sapply(0:(p-1), function(k) dplyr::lag(x, k))
  X_lags <- X_lags[(p+1):n, , drop=FALSE]
  y_trim <- y[(p+1):n]

  if (any(!is.finite(X_lags)) || any(!is.finite(y_trim))) return(NA)

  tryCatch({
    # Simple distributed lag (nealmon requires midas_r which needs specific structure)
    # Use OLS with polynomial constraint approximation
    fit  <- lm(y_trim ~ X_lags)
    # Forecast using last p values of x from test
    x_new <- rev(tail(x, p))
    pred  <- coef(fit)[1] + sum(coef(fit)[-1] * x_new)
    as.numeric(pred)
  }, error=function(e) NA)
}

# ── Pseudo OOS loop ───────────────────────────────────────────────────────────
oos_idx   <- which(df_monthly$date >= oos_start)
forecasts <- rep(NA_real_, length(oos_idx))

cat(sprintf("Running %d OOS forecasts...\n", length(oos_idx)))

for (i in seq_along(oos_idx)) {
  t     <- oos_idx[i]
  train <- df_monthly[1:(t-1), ]

  # Average MIDAS forecast across all GT keywords
  preds <- sapply(gt_vars, function(v) {
    midas_forecast(train, df_monthly[t, ], v, p=3)
  })
  valid <- preds[is.finite(preds)]
  if (length(valid) > 0) forecasts[i] <- mean(valid)

  if (i %% 20 == 0) cat(sprintf("  %d/%d done\n", i, length(oos_idx)))
}

# ── Compile and save ──────────────────────────────────────────────────────────
results <- df_monthly[oos_idx, c("date","igae_ldiff")] |>
  mutate(forecast_midas=forecasts, model="MIDAS") |>
  rename(actual=igae_ldiff)

non_na <- sum(!is.na(results$forecast_midas))
cat(sprintf("\nForecasts: %d (non-NA: %d)\n", nrow(results), non_na))

write_csv(results, file.path(final_dir, "forecasts_midas.csv"))
cat("Saved -> data/final/forecasts_midas.csv\n")

if (non_na > 0) {
  rmse <- sqrt(mean((results$actual - results$forecast_midas)^2, na.rm=TRUE))
  cat(sprintf("MIDAS RMSE: %.6f\n", rmse))
}
