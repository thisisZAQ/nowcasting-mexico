library(dplyr); library(readr); library(yaml); library(here)
cfg <- yaml::read_yaml(here("config","config.yaml"))
out_dir <- here("outputs","tables"); ms_dir <- here("outputs","manuscript")

ar    <- read_csv(here("data/final/forecasts_ar.csv"), show_col_types=FALSE)
dfm_b <- read_csv(here("data/final/forecasts_dfm_benchmark.csv"), show_col_types=FALSE)
dfm_a <- read_csv(here("data/final/forecasts_dfm_augmented.csv"), show_col_types=FALSE)
ml    <- read_csv(here("data/final/forecasts_ml.csv"), show_col_types=FALSE)

all_fc <- ar |> select(date,actual,forecast_ar) |>
  left_join(dfm_b |> select(date,forecast_dfm_benchmark), by="date") |>
  left_join(dfm_a |> select(date,forecast_dfm_augmented), by="date") |>
  left_join(ml    |> select(date,forecast_lasso,forecast_ridge,forecast_rf), by="date") |>
  mutate(date=as.Date(date))

periods <- list(
  list(name="Full (2018-2024)",    s="2018-01-01", e="2024-09-01"),
  list(name="Pre-COVID (2018-19)", s="2018-01-01", e="2019-12-01"),
  list(name="COVID (2020-21)",     s="2020-01-01", e="2021-12-01"),
  list(name="Post-COVID (2022-24)",s="2022-01-01", e="2024-09-01")
)
fc_cols <- c("forecast_ar","forecast_dfm_benchmark","forecast_dfm_augmented","forecast_lasso","forecast_ridge","forecast_rf")
labels  <- c("AR(4)","DFM Benchmark","DFM Augmented","LASSO","Ridge","Random Forest")
rmse_fn <- function(a,f) sqrt(mean((a-f)^2,na.rm=TRUE))

tbl <- data.frame(Model=labels, stringsAsFactors=FALSE)
for (p in periods) {
  sub <- all_fc |> filter(date>=p$s, date<=p$e)
  tbl[[p$name]] <- sapply(fc_cols, function(c) round(rmse_fn(sub$actual,sub[[c]]),4))
}

cat("Sub-period RMSE:\n"); print(tbl)

ar_row <- as.numeric(tbl[1, -1])
ratios <- tbl
ratios[,-1] <- round(sweep(as.matrix(tbl[,-1]), 2, ar_row, "/"), 3)
cat("\nRMSE ratios vs AR(4):\n"); print(ratios)

write_csv(tbl,    file.path(out_dir,"subperiod_rmse.csv"))
write_csv(ratios, file.path(out_dir,"rmse_ratios.csv"))
cat("Done.\n")
