# scripts/01_collect/collect_mobility.R
# Combines Google Mobility yearly files for Mexico (2020-2022)
# Filters to national level only (no sub-regions)
# Coverage: Feb 2020 - Oct 2022

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("config", "config.yaml"))
out_dir <- here("data", "raw", "mobility")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── Combine yearly files ──────────────────────────────────────────────────────
years <- c(2020, 2021, 2022)
files <- file.path(out_dir, paste0("google_mobility_MX_", years, ".csv"))
files <- c(files, file.path(out_dir, "google_mobility_MX.csv"))  # 2022 main file

existing <- files[file.exists(files)]
cat(sprintf("Found %d mobility files to combine\n", length(existing)))

raw <- bind_rows(lapply(existing, read_csv, show_col_types = FALSE))

# ── Filter to national level and clean ───────────────────────────────────────
mx <- raw |>
  filter(
    country_region_code == "MX",
    is.na(sub_region_1) | sub_region_1 == ""
  ) |>
  select(
    date,
    retail_and_recreation = retail_and_recreation_percent_change_from_baseline,
    grocery_and_pharmacy  = grocery_and_pharmacy_percent_change_from_baseline,
    parks                 = parks_percent_change_from_baseline,
    transit_stations      = transit_stations_percent_change_from_baseline,
    workplaces            = workplaces_percent_change_from_baseline,
    residential           = residential_percent_change_from_baseline
  ) |>
  mutate(date = as.Date(date)) |>
  distinct(date, .keep_all = TRUE) |>
  arrange(date)

out_path <- file.path(out_dir, "google_mobility_MX_combined.csv")
write_csv(mx, out_path)
cat(sprintf("Saved %d rows (%s to %s) -> %s\n",
            nrow(mx), min(mx$date), max(mx$date), out_path))

# ── Apple placeholder ─────────────────────────────────────────────────────────
apple_placeholder <- data.frame(
  date    = as.Date(character()),
  driving = numeric(),
  transit = numeric(),
  walking = numeric()
)
write_csv(apple_placeholder, file.path(out_dir, "apple_mobility_MX.csv"))

cat("Mobility collection complete.\n")
