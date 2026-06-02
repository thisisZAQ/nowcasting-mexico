# scripts/03_model/model_ar.R
# Benchmark AR model — pseudo out-of-sample nowcasting
# Expanding window: train on all data up to t, forecast t+1
# Output: data/final/forecasts_ar.csv

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("config", "config.yaml"))
oos_start  <- as.Date(cfg$evaluation$pseudo_oos_start)
lags       <- cfg$models$benchmark_ar$lags
final_dir  <- here("data", "final")

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading dataset...\n")
df <- read_csv(file.path(final_dir, "dataset_traditional.csv"),
               show_col_types = FALSE) |>
  mutate(date = as.Date(date)) |>
  filter(!is.na(igae_ldiff))

cat(sprintf("Sample: %s to %s (%d obs)\n",
            min(df$date), max(df$date), nrow(df)))
cat(sprintf("OOS evaluation from: %s\n", oos_start))

# ── Build lagged features ─────────────────────────────────────────────────────
for (k in 1:lags) {
  df[[paste0("igae_lag", k)]] <- dplyr::lag(df$igae_ldiff, k)
}

# ── Pseudo OOS expanding window ───────────────────────────────────────────────
oos_idx  <- which(df$date >= oos_start)
forecasts <- vector("numeric", length(oos_idx))
lag_cols  <- paste0("igae_lag", 1:lags)

cat(sprintf("Running %d OOS forecasts...\n", length(oos_idx)))

for (i in seq_along(oos_idx)) {
  t       <- oos_idx[i]
  train   <- df[1:(t - 1), ]
  newdata <- df[t, ]

  # Drop rows with NA in any lag
  train_clean <- train[complete.cases(train[, c("igae_ldiff", lag_cols)]), ]

  if (nrow(train_clean) < lags + 5) {
    forecasts[i] <- NA
    next
  }

  formula <- as.formula(paste("igae_ldiff ~", paste(lag_cols, collapse = " + ")))
  fit     <- lm(formula, data = train_clean)
  pred    <- predict(fit, newdata = newdata)
  forecasts[i] <- as.numeric(pred)
}

# ── Compile results ────────────────────────────────────────────────────────────
results <- df[oos_idx, c("date", "igae_ldiff")] |>
  mutate(
    forecast_ar = forecasts,
    model       = "AR"
  ) |>
  rename(actual = igae_ldiff)

cat(sprintf("\nForecasts generated: %d (non-NA: %d)\n",
            nrow(results), sum(!is.na(results$forecast_ar))))

# ── Save ──────────────────────────────────────────────────────────────────────
out_path <- file.path(final_dir, "forecasts_ar.csv")
write_csv(results, out_path)
cat(sprintf("Saved -> %s\n", out_path))

# ── Quick RMSE ────────────────────────────────────────────────────────────────
rmse <- sqrt(mean((results$actual - results$forecast_ar)^2, na.rm = TRUE))
cat(sprintf("AR RMSE: %.6f\n", rmse))
