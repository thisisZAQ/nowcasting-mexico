# scripts/02_process/build_model_dataset.R
# Merges processed traditional and alternative indicators
# Outputs:
#   data/final/dataset_traditional.csv  — benchmark models
#   data/final/dataset_full.csv         — augmented + ML models

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("config", "config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
proc_dir   <- here("data", "processed")
final_dir  <- here("data", "final")
dir.create(final_dir, showWarnings = FALSE, recursive = TRUE)

# ── Load processed datasets ───────────────────────────────────────────────────
cat("Loading processed datasets...\n")

trad <- read_csv(file.path(proc_dir, "traditional_indicators.csv"),
                 show_col_types = FALSE) |>
  mutate(date = as.Date(date))

alt  <- read_csv(file.path(proc_dir, "alternative_indicators.csv"),
                 show_col_types = FALSE) |>
  mutate(date = as.Date(date))

cat(sprintf("Traditional: %d rows x %d cols\n", nrow(trad), ncol(trad)))
cat(sprintf("Alternative: %d rows x %d cols\n", nrow(alt),  ncol(alt)))

# ── Dataset 1: traditional only (benchmark) ───────────────────────────────────
# Keep stationary (differenced) variables for modelling
# Drop level variables — keep log-diffs and diffs only + date + igae_sa level
trad_model <- trad |>
  select(
    date,
    igae_sa,          # target level (for reference)
    igae_ldiff,       # target: monthly log-growth rate
    ip_ldiff,
    retail_ldiff,
    unemp_diff,
    fx_ldiff,
    cetes_diff,
    m1_ldiff,
    credit_ldiff
  ) |>
  filter(!is.na(igae_ldiff))  # drop first obs lost to differencing

cat(sprintf("\nTraditional model dataset: %d rows x %d cols\n",
            nrow(trad_model), ncol(trad_model)))

write_csv(trad_model, file.path(final_dir, "dataset_traditional.csv"))
cat(sprintf("Saved -> data/final/dataset_traditional.csv\n"))

# ── Dataset 2: full (augmented + ML) ─────────────────────────────────────────
full_model <- trad_model |>
  left_join(alt |> select(-any_of(c("m1_alt", "credit_alt"))),
            by = "date")

# Summary of missingness (mobility is NA outside 2020-2022 by design)
miss <- colSums(is.na(full_model))
miss <- miss[miss > 0]
if (length(miss) > 0) {
  cat("\nMissing values by column:\n")
  print(miss)
}

cat(sprintf("\nFull model dataset: %d rows x %d cols\n",
            nrow(full_model), ncol(full_model)))

write_csv(full_model, file.path(final_dir, "dataset_full.csv"))
cat(sprintf("Saved -> data/final/dataset_full.csv\n"))

# ── Summary ───────────────────────────────────────────────────────────────────
cat("\n── Variable inventory ──────────────────────────────────────────────\n")
cat("TARGET:      igae_ldiff (monthly log-growth of IGAE)\n")
cat("TRADITIONAL:", paste(names(trad_model)[-c(1,2,3)], collapse=", "), "\n")
alt_cols <- setdiff(names(full_model), names(trad_model))
cat("ALTERNATIVE:", paste(alt_cols, collapse=", "), "\n")
