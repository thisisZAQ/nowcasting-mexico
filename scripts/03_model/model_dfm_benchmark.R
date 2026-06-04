# scripts/03_model/model_dfm_benchmark.R
# DFM benchmark — implemented via PCA + VAR (equivalent to 2-step DFM)
# Step 1: Extract factors via PCA on standardised predictors
# Step 2: Regress IGAE on lagged factors (bridge equation)
# Pseudo OOS expanding window
# Output: data/final/forecasts_dfm_benchmark.csv

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg       <- yaml::read_yaml(here("config", "config.yaml"))
oos_start <- as.Date(cfg$evaluation$pseudo_oos_start)
r         <- cfg$models$benchmark_dfm$factors
p         <- cfg$models$benchmark_dfm$lags
final_dir <- here("data", "final")

cat("Loading dataset...\n")
df <- read_csv(file.path(final_dir, "dataset_traditional.csv"),
               show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |>
  filter(!is.na(igae_ldiff))

cat(sprintf("Sample: %s to %s (%d obs)\n",
            min(df$date), max(df$date), nrow(df)))

pred_vars <- c("ip_ldiff","unemp_diff","fx_ldiff",
               "cetes_diff","m1_ldiff","credit_ldiff")

# ── Helper: PCA-based DFM forecast ───────────────────────────────────────────
dfm_forecast <- function(train_y, train_X, r, p) {
  # Standardise predictors
  X_mean <- colMeans(train_X, na.rm=TRUE)
  X_sd   <- apply(train_X, 2, sd, na.rm=TRUE)
  X_sd[X_sd == 0] <- 1
  X_std  <- scale(train_X, center=X_mean, scale=X_sd)
  X_std[is.na(X_std)] <- 0

  # Extract r factors via PCA
  pca    <- prcomp(X_std, center=FALSE, scale.=FALSE)
  F_mat  <- pca$x[, 1:r, drop=FALSE]

  # Build lagged factor matrix
  n <- length(train_y)
  if (n <= p + r) return(NA)

  # Create lagged factors
  lag_list <- list()
  for (k in 1:p) {
    lagged <- rbind(matrix(NA, k, r), F_mat[1:(n-k), , drop=FALSE])
    colnames(lagged) <- paste0("F", 1:r, "_lag", k)
    lag_list[[k]] <- lagged
  }
  F_lagged <- do.call(cbind, lag_list)

  # Combine with current factors for bridge equation
  X_reg  <- cbind(F_mat, F_lagged)
  keep   <- complete.cases(cbind(train_y, X_reg))
  y_reg  <- train_y[keep]
  X_reg  <- X_reg[keep, , drop=FALSE]

  if (length(y_reg) < r * p + 5) return(NA)

  fit  <- lm(y_reg ~ X_reg)
  
  # Forecast: use last row of factors
  last_F       <- tail(F_mat, 1)
  last_F_lags  <- tail(F_lagged, 1)
  newdata      <- matrix(c(last_F, last_F_lags), nrow=1)
  colnames(newdata) <- colnames(X_reg)
  pred <- predict(fit, newdata=as.data.frame(newdata))
  return(as.numeric(pred))
}

# ── Pseudo OOS expanding window ───────────────────────────────────────────────
oos_idx   <- which(df$date >= oos_start)
forecasts <- rep(NA_real_, length(oos_idx))

cat(sprintf("Running %d OOS forecasts (r=%d factors, p=%d lags)...\n",
            length(oos_idx), r, p))

for (i in seq_along(oos_idx)) {
  t     <- oos_idx[i]
  train <- df[1:(t-1), ]
  cc    <- complete.cases(train[, c("igae_ldiff", pred_vars)])
  train <- train[cc, ]
  if (nrow(train) < 20) next

  tryCatch({
    forecasts[i] <- dfm_forecast(
      train_y = train$igae_ldiff,
      train_X = as.matrix(train[, pred_vars]),
      r = r, p = p
    )
  }, error=function(e) {
    cat(sprintf("  t=%s ERROR: %s\n", df$date[t], conditionMessage(e)))
  })

  if (i %% 20 == 0) cat(sprintf("  %d/%d done\n", i, length(oos_idx)))
}

results <- df[oos_idx, c("date","igae_ldiff")] |>
  mutate(forecast_dfm_benchmark=forecasts, model="DFM_benchmark") |>
  rename(actual=igae_ldiff)

non_na <- sum(!is.na(results$forecast_dfm_benchmark))
cat(sprintf("\nForecasts: %d (non-NA: %d)\n", nrow(results), non_na))
write_csv(results, file.path(final_dir, "forecasts_dfm_benchmark.csv"))
cat("Saved -> data/final/forecasts_dfm_benchmark.csv\n")

if (non_na > 0) {
  rmse <- sqrt(mean((results$actual - results$forecast_dfm_benchmark)^2, na.rm=TRUE))
  cat(sprintf("DFM benchmark RMSE: %.6f\n", rmse))
}
