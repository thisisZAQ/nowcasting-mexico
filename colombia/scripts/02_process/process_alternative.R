# colombia/scripts/02_process/process_alternative.R
# Processes alternative indicators for Colombia
# Mirrors Mexico's process_alternative.R

library(dplyr)
library(readr)
library(lubridate)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("colombia/config/config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
raw_dir    <- here("colombia/data/raw")
out_dir    <- here("colombia/data/processed")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

date_spine <- tibble(date=seq(start_date, end_date, by="month"))

# ── Google Trends ─────────────────────────────────────────────────────────────
cat("Processing Google Trends...\n")
trends_raw <- read_csv(file.path(raw_dir, "google_trends/google_trends.csv"),
                       show_col_types=FALSE) |>
  mutate(date=floor_date(as.Date(date), "month"))

trends_wide <- trends_raw |>
  mutate(keyword=gsub(" ", "_", keyword),
         keyword=gsub("[^a-zA-Z0-9_]", "", keyword),
         keyword=paste0("gt_", keyword)) |>
  group_by(date, keyword) |>
  summarise(hits=mean(hits, na.rm=TRUE), .groups="drop") |>
  tidyr::pivot_wider(names_from=keyword, values_from=hits)

cat(sprintf("  %d months, %d keywords\n", nrow(trends_wide), ncol(trends_wide)-1))

# ── Google Mobility ───────────────────────────────────────────────────────────
cat("Processing Google Mobility...\n")
mob_path <- file.path(raw_dir, "mobility/google_mobility_CO_combined.csv")

if (file.exists(mob_path)) {
  mobility_raw <- read_csv(mob_path, show_col_types=FALSE) |>
    mutate(date=floor_date(as.Date(date), "month"))

  mobility_monthly <- mobility_raw |>
    group_by(date) |>
    summarise(
      mob_retail    = mean(retail_and_recreation, na.rm=TRUE),
      mob_work      = mean(workplaces,            na.rm=TRUE),
      mob_transit   = mean(transit_stations,      na.rm=TRUE),
      mob_grocery   = mean(grocery_and_pharmacy,  na.rm=TRUE),
      mob_residential = mean(residential,         na.rm=TRUE),
      .groups="drop"
    )
  cat(sprintf("  %d months (%s to %s)\n", nrow(mobility_monthly),
              min(mobility_monthly$date), max(mobility_monthly$date)))
} else {
  cat("  Mobility file not found — skipping\n")
  mobility_monthly <- tibble(date=as.Date(character()))
}

# ── Merge ─────────────────────────────────────────────────────────────────────
cat("Merging alternative indicators...\n")
panel <- date_spine |>
  left_join(trends_wide,      by="date") |>
  left_join(mobility_monthly, by="date") |>
  arrange(date)

cat(sprintf("\nPanel: %d rows x %d columns\n", nrow(panel), ncol(panel)))

out_path <- file.path(out_dir, "alternative_indicators.csv")
write_csv(panel, out_path)
cat(sprintf("Saved -> %s\n", out_path))
