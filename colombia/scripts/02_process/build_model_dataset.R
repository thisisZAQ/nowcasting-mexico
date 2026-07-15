# colombia/scripts/02_process/build_model_dataset.R
# Merges traditional and alternative into final model datasets

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("colombia/config/config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
proc_dir   <- here("colombia/data/processed")
final_dir  <- here("colombia/data/final")
dir.create(final_dir, showWarnings=FALSE, recursive=TRUE)

trad <- read_csv(file.path(proc_dir, "traditional_indicators.csv"),
                 show_col_types=FALSE) |> mutate(date=as.Date(date))
alt  <- read_csv(file.path(proc_dir, "alternative_indicators.csv"),
                 show_col_types=FALSE) |> mutate(date=as.Date(date))

cat(sprintf("Traditional: %d rows x %d cols\n", nrow(trad), ncol(trad)))
cat(sprintf("Alternative: %d rows x %d cols\n", nrow(alt),  ncol(alt)))

# Traditional model dataset — stationary variables only
trad_model <- trad |>
  select(date, ise_sa, ise_ldiff, ip_ldiff, retail_ldiff,
         unemp_diff, fx_ldiff, interest_diff, m1_ldiff, credit_diff) |>
  filter(!is.na(ise_ldiff))

cat(sprintf("\nTraditional model dataset: %d rows x %d cols\n",
            nrow(trad_model), ncol(trad_model)))
write_csv(trad_model, file.path(final_dir, "dataset_traditional.csv"))
cat("Saved -> colombia/data/final/dataset_traditional.csv\n")

# Full dataset — add alternative data
full_model <- trad_model |>
  left_join(alt |> select(-any_of(names(trad_model)[-1])), by="date")

miss <- colSums(is.na(full_model))
miss <- miss[miss > 0]
if (length(miss) > 0) {
  cat("\nMissing values by column:\n")
  print(miss)
}

cat(sprintf("\nFull model dataset: %d rows x %d cols\n",
            nrow(full_model), ncol(full_model)))
write_csv(full_model, file.path(final_dir, "dataset_full.csv"))
cat("Saved -> colombia/data/final/dataset_full.csv\n")

cat("\n── Variable inventory ───────────────────────────────────────────────\n")
cat("TARGET:      ise_ldiff\n")
cat("TRADITIONAL:", paste(names(trad_model)[-c(1,2,3)], collapse=", "), "\n")
alt_cols <- setdiff(names(full_model), names(trad_model))
cat("ALTERNATIVE:", paste(alt_cols, collapse=", "), "\n")
