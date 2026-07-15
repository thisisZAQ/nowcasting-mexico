# colombia/scripts/01_collect/collect_mobility.R
# Google Mobility for Colombia — same yearly files as Mexico
# Filter: country_region_code == "CO"

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("colombia/config/config.yaml"))
out_dir <- here("colombia/data/raw/mobility")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# Download yearly files
for (year in c(2020, 2021, 2022)) {
  url      <- sprintf("https://www.gstatic.com/covid19/mobility/%d_CO_Region_Mobility_Report.csv", year)
  out_file <- file.path(out_dir, sprintf("google_mobility_CO_%d.csv", year))
  cat(sprintf("Downloading %d mobility file...\n", year))
  tryCatch({
    download.file(url, destfile=out_file, quiet=TRUE)
    n <- nrow(read_csv(out_file, show_col_types=FALSE))
    cat(sprintf("  Saved %d rows -> mobility/google_mobility_CO_%d.csv\n", n, year))
  }, error=function(e) cat(sprintf("  ERROR: %s\n", conditionMessage(e))))
}

# Combine yearly files — national level only
files <- list.files(out_dir, pattern="google_mobility_CO_20", full.names=TRUE)
if (length(files) > 0) {
  raw <- bind_rows(lapply(files, read_csv, show_col_types=FALSE))
  co  <- raw |>
    filter(country_region_code=="CO", is.na(sub_region_1) | sub_region_1=="") |>
    select(
      date,
      retail_and_recreation = retail_and_recreation_percent_change_from_baseline,
      grocery_and_pharmacy  = grocery_and_pharmacy_percent_change_from_baseline,
      parks                 = parks_percent_change_from_baseline,
      transit_stations      = transit_stations_percent_change_from_baseline,
      workplaces            = workplaces_percent_change_from_baseline,
      residential           = residential_percent_change_from_baseline
    ) |>
    mutate(date=as.Date(date)) |>
    distinct(date, .keep_all=TRUE) |>
    arrange(date)

  out_path <- file.path(out_dir, "google_mobility_CO_combined.csv")
  write_csv(co, out_path)
  cat(sprintf("\nCombined: %d rows (%s to %s)\n",
              nrow(co), min(co$date), max(co$date)))
}
cat("Mobility collection complete.\n")
