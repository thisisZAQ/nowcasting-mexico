library(readr); library(dplyr); library(here)
df <- read_csv(here("data/final/dataset_traditional.csv"), show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |> filter(!is.na(igae_ldiff))

pred_vars <- c("ip_ldiff","unemp_diff","fx_ldiff","cetes_diff","m1_ldiff","credit_ldiff")

dfm_forecast <- function(train_y, train_X, r, p) {
  X_std <- scale(train_X); X_std[is.na(X_std)] <- 0
  pca   <- prcomp(X_std, center=FALSE, scale.=FALSE)
  F_mat <- pca$x[,1:r,drop=FALSE]; n <- length(train_y)
  lag_list <- lapply(1:p, function(k) {
    l <- rbind(matrix(NA,k,r), F_mat[1:(n-k),,drop=FALSE])
    colnames(l) <- paste0("F",1:r,"_lag",k); l
  })
  F_lagged <- do.call(cbind, lag_list)
  X_reg <- cbind(F_mat, F_lagged)
  keep  <- complete.cases(cbind(train_y, X_reg))
  fit   <- lm(train_y[keep] ~ X_reg[keep,,drop=FALSE])
  newdata <- as.data.frame(matrix(c(tail(F_mat,1), tail(F_lagged,1)), nrow=1))
  colnames(newdata) <- colnames(X_reg)
  as.numeric(predict(fit, newdata=newdata))
}

oos_idx <- which(df$date >= as.Date("2018-01-01"))
actual  <- df$igae_ldiff[oos_idx]

for (r in c(2, 3)) {
  fc <- rep(NA_real_, length(oos_idx))
  for (i in seq_along(oos_idx)) {
    t     <- oos_idx[i]
    train <- df[1:(t-1),]
    cc    <- complete.cases(train[,c("igae_ldiff",pred_vars)])
    train <- train[cc,]
    tryCatch({ fc[i] <- dfm_forecast(train$igae_ldiff, as.matrix(train[,pred_vars]), r, 2) },
             error=function(e) NULL)
  }
  rmse <- sqrt(mean((actual-fc)^2, na.rm=TRUE))
  cat(sprintf("DFM r=%d RMSE: %.6f\n", r, rmse))
}
