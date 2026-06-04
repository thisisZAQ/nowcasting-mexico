# scripts/03_model/model_dfm_augmented.R
# DFM augmented — PCA+bridge equation with traditional + Google Trends
# Output: data/final/forecasts_dfm_augmented.csv

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg       <- yaml::read_yaml(here("config", "config.yaml"))
oos_start <- as.Date(cfg$evaluation$pseudo_oos_start)
r         <- cfg$models$augmented_dfm$factors
p         <- cfg$models$augmented_dfm$lags
final_dir <- here("data", "final")

cat("Loading dataset...\n")
df <- read_csv(file.path(final_dir, "dataset_full.csv"),
               show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |>
  filter(!is.na(igae_ldiff))

trad_vars   <- c("ip_ldiff","unemp_diff","fx_ldiff",
                 "cetes_diff","m1_ldiff","credit_ldiff")
trends_vars <- grep("^gt_", names(df), value=TRUE)
all_pred    <- c(trad_vars, trends_vars)

cat(sprintf("Variables: %d trad + %d trends = %d total\n",
            length(trad_vars), length(trends_vars), length(all_pred)))

dfm_forecast <- function(train_y, train_X, r, p) {
  X_mean <- colMeans(train_X, na.rm=TRUE)
  X_sd   <- apply(train_X, 2, sd, na.rm=TRUE)
  X_sd[X_sd == 0] <- 1
  X_std  <- scale(train_X, center=X_mean, scale=X_sd)
  X_std[is.na(X_std)] <- 0

  pca   <- prcomp(X_std, center=FALSE, scale.=FALSE)
  F_mat <- pca$x[, 1:r, drop=FALSE]
  n     <- length(train_y)
  if (n <= p + r) return(NA)

  lag_list <- list()
  for (k in 1:p) {
    lagged <- rbind(matrix(NA, k, r), F_mat[1:(n-k), , drop=FALSE])
    colnames(lagged) <- paste0("F", 1:r, "_lag", k)
    lag_list[[k]] <- lagged
  }
  F_lagged <- do.call(cbind, lag_list)
  X_reg    <- cbind(F_mat, F_lagged)
  keep     <- complete.cases(cbind(train_y, X_reg))
  y_reg    <- train_y[keep]
  X_reg    <- X_reg[keep, , drop=FALSE]
  if (length(y_reg) < r * p + 5) return(NA)

  fit      <- lm(y_reg ~ X_reg)
  last_F   <- tail(F_mat, 1)
  last_lag <- tail(F_lagged, 1)
  newdata  <- as.data.frame(matrix(c(last_F, last_lag), nrow=1))
  colnames(newdata) <- colnames(X_reg)
  return(as.numeric(predict(fit, newdata=newdata)))
}

oos_idx   <- which(df$date >= oos_start)
forecasts <- rep(NA_real_, length(oos_idx))

cat(sprintf("Running %d OOS forecasts (r=%d, p=%d)...\n",
            length(oos_idx), r, p))

for (i in seq_along(oos_idx)) {
  t     <- oos_idx[i]
  train <- df[1:(t-1), c("igae_ldiff", all_pred)]

  # Drop columns with >50% NA in this window
  na_prop <- colMeans(is.na(train))
  use_pred <- all_pred[all_pred %in% names(na_prop[na_prop <= 0.5])]
  train_cc <- train[complete.cases(train[, c("igae_ldiff")]), ]
  if (nrow(train_cc) < 20 || length(use_pred) < 3) next

  tryCatch({
    forecasts[i] <- dfm_forecast(
      train_y = train_cc$igae_ldiff,
      train_X = as.matrix(train_cc[, use_pred]),
      r = min(r, length(use_pred) - 1),
      p = p
    )
  }, error=function(e) {
    cat(sprintf("  t=%s ERROR: %s\n", df$date[t], conditionMessage(e)))
  })

  if (i %% 20 == 0) cat(sprintf("  %d/%d done\n", i, length(oos_idx)))
}

results <- df[oos_idx, c("date","igae_ldiff")] |>
  mutate(forecast_dfm_augmented=forecasts, model="DFM_augmented") |>
  rename(actual=igae_ldiff)

non_na <- sum(!is.na(results$forecast_dfm_augmented))
cat(sprintf("\nForecasts: %d (non-NA: %d)\n", nrow(results), non_na))
write_csv(results, file.path(final_dir, "forecasts_dfm_augmented.csv"))
cat("Saved -> data/final/forecasts_dfm_augmented.csv\n")

if (non_na > 0) {
  rmse <- sqrt(mean((results$actual - results$forecast_dfm_augmented)^2, na.rm=TRUE))
  cat(sprintf("DFM augmented RMSE: %.6f\n", rmse))
}
