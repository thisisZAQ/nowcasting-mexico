# Quick script to add MIDAS to the forecast errors table
library(dplyr); library(readr); library(here)

midas <- read_csv(here("data/final/forecasts_midas.csv"), show_col_types=FALSE)
errors <- read_csv(here("outputs/tables/forecast_errors.csv"), show_col_types=FALSE)

rmse <- sqrt(mean((midas$actual - midas$forecast_midas)^2, na.rm=TRUE))
mae  <- mean(abs(midas$actual - midas$forecast_midas), na.rm=TRUE)
mape <- mean(abs((midas$actual - midas$forecast_midas)/midas$actual)*100, na.rm=TRUE)

midas_row <- tibble(model="MIDAS", n_forecasts=81,
                    RMSE=round(rmse,6), MAE=round(mae,6), MAPE=round(mape,4))

errors_updated <- bind_rows(errors, midas_row) |> arrange(RMSE)
write_csv(errors_updated, here("outputs/tables/forecast_errors.csv"))
cat("Updated forecast_errors.csv:\n")
print(errors_updated)
