# scripts/02_process/process_alternative.R
# Processes all alternative high-frequency indicators:
#   - Google Trends (7 keywords)
#   - Google Mobility (2020-2022, COVID period)
#   - Banxico payments (remittances placeholder, M1, credit)
# Output: data/processed/alternative_indicators.csv (wide, monthly)

library(dplyr)
library(tidyr)
library(readr)
library(lubridate)
library(zoo)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("config", "config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
raw_dir    <- here("data", "raw")
out_dir    <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

log_diff <- function(x) c(NA, diff(log(x)))

# ── Full monthly date spine ───────────────────────────────────────────────────
date_spine <- tibble(date = seq(start_date, end_date, by = "month"))

# ══════════════════════════════════════════════════════════════════════════════
# 1. Google Trends — pivot to wide, one column per keyword
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing Google Trends...\n")

trends_raw <- read_csv(
  file.path(raw_dir, "google_trends/google_trends.csv"),
  show_col_types = FALSE
) |> mutate(date = floor_date(as.Date(date), "month"))

# Clean keyword names for column use
trends_wide <- trends_raw |>
  mutate(keyword = gsub(" ", "_", keyword),
         keyword = gsub("[^a-zA-Z0-9_]", "", keyword),
         keyword = paste0("gt_", keyword)) |>
  group_by(date, keyword) |>
  summarise(hits = mean(hits, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = keyword, values_from = hits)

cat(sprintf("  %d months, %d keywords\n",
            nrow(trends_wide), ncol(trends_wide) - 1))

# ══════════════════════════════════════════════════════════════════════════════
# 2. Google Mobility — aggregate daily to monthly, COVID period only
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing Google Mobility...\n")

mobility_path <- file.path(raw_dir, "mobility/google_mobility_MX_combined.csv")

if (file.exists(mobility_path)) {
  mobility_raw <- read_csv(mobility_path, show_col_types = FALSE) |>
    mutate(date = floor_date(as.Date(date), "month"))

  mobility_monthly <- mobility_raw |>
    group_by(date) |>
    summarise(
      mob_retail    = mean(retail_and_recreation, na.rm = TRUE),
      mob_work      = mean(workplaces,            na.rm = TRUE),
      mob_transit   = mean(transit_stations,      na.rm = TRUE),
      mob_grocery   = mean(grocery_and_pharmacy,  na.rm = TRUE),
      mob_residential = mean(residential,         na.rm = TRUE),
      .groups = "drop"
    )
  cat(sprintf("  %d months (%s to %s)\n",
              nrow(mobility_monthly),
              min(mobility_monthly$date),
              max(mobility_monthly$date)))
} else {
  cat("  Mobility file not found — creating empty placeholder\n")
  mobility_monthly <- tibble(date = as.Date(character()),
                             mob_retail = numeric(),
                             mob_work = numeric(),
                             mob_transit = numeric(),
                             mob_grocery = numeric(),
                             mob_residential = numeric())
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. Banxico payment proxies (M1, credit already in traditional — add growth)
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing Banxico payment proxies...\n")

read_banxico <- function(name) {
  path <- file.path(raw_dir, "banxico", paste0(name, ".csv"))
  if (!file.exists(path)) return(NULL)
  read_csv(path, show_col_types = FALSE) |>
    mutate(date = floor_date(as.Date(date), "month")) |>
    group_by(date) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop")
}

m1_raw     <- read_banxico("m1")
credit_raw <- read_banxico("credit_private")

payments <- date_spine
if (!is.null(m1_raw)) {
  payments <- payments |>
    left_join(m1_raw     |> rename(m1_alt = value),     by = "date")
}
if (!is.null(credit_raw)) {
  payments <- payments |>
    left_join(credit_raw |> rename(credit_alt = value), by = "date")
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. Merge all onto date spine
# ══════════════════════════════════════════════════════════════════════════════
cat("Merging alternative indicators...\n")

panel <- date_spine |>
  left_join(trends_wide,      by = "date") |>
  left_join(mobility_monthly, by = "date") |>
  left_join(payments,         by = "date") |>
  arrange(date)

cat(sprintf("\nPanel: %d rows x %d columns (%s to %s)\n",
            nrow(panel), ncol(panel),
            min(panel$date), max(panel$date)))

# ── Save ──────────────────────────────────────────────────────────────────────
out_path <- file.path(out_dir, "alternative_indicators.csv")
write_csv(panel, out_path)
cat(sprintf("Saved -> %s\n", out_path))
