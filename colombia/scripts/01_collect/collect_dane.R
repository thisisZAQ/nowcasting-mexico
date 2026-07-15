# colombia/scripts/01_collect/collect_dane.R
# Reads and standardises DANE flat files
# DANE files use similar structure to INEGI BIE
# Files must be manually downloaded from dane.gov.co and converted to UTF-8

library(dplyr)
library(readr)
library(yaml)
library(here)
library(lubridate)

cfg     <- yaml::read_yaml(here("colombia/config/config.yaml"))
out_dir <- here("colombia/data/raw/dane")

# ── Helper: read DANE flat file ───────────────────────────────────────────────
# DANE files typically have metadata rows at top, then date/value columns
# Try multiple skip values to find the data
read_dane <- function(path, series_name) {
  # Try UTF-8 first, then Latin-1
  for (enc in c("UTF-8", "latin1", "UTF-16LE")) {
    for (skip in c(0, 3, 4, 5, 6, 8, 10)) {
      tryCatch({
        df <- read_csv(path, skip=skip, col_names=FALSE,
                       col_types=cols(.default=col_character()),
                       locale=locale(encoding=enc),
                       show_col_types=FALSE)
        # Look for rows where first col looks like a date (YYYY or YYYY-MM)
        date_rows <- grepl("^(19|20)[0-9]{2}[-/]?(0[1-9]|1[0-2])?", df[[1]], perl=TRUE)
        if (sum(date_rows, na.rm=TRUE) > 12) {
          df <- df[date_rows, 1:2]
          colnames(df) <- c("period", "value")
          df <- df |>
            mutate(
              period = trimws(period),
              value  = as.numeric(gsub(",", ".", trimws(value)))
            ) |>
            filter(!is.na(value))

          # Standardise date format
          df$date <- tryCatch({
            if (grepl("/", df$period[1])) {
              # YYYY/MM format (like INEGI)
              as.Date(paste0(gsub("/", "-", df$period), "-01"))
            } else if (nchar(df$period[1]) == 7) {
              as.Date(paste0(df$period, "-01"))
            } else {
              as.Date(df$period)
            }
          }, error=function(e) as.Date(NA))

          df <- df |>
            filter(!is.na(date)) |>
            mutate(series=series_name) |>
            select(date, value, series) |>
            arrange(date)

          if (nrow(df) > 12) return(df)
        }
      }, error=function(e) NULL)
    }
  }
  cat(sprintf("  Could not parse %s — check file format manually\n", series_name))
  return(NULL)
}

# ── Process each DANE file ────────────────────────────────────────────────────
files <- list(
  ise_original         = "ise_original.csv",
  ise_sa               = "ise_sa.csv",
  industrial_production = "industrial_production.csv",
  retail_sales         = "retail_sales.csv",
  unemployment_rate    = "unemployment_rate.csv"
)

for (name in names(files)) {
  path <- file.path(out_dir, files[[name]])
  if (!file.exists(path)) {
    cat(sprintf("SKIP: %s not found\n", name))
    next
  }
  cat(sprintf("Processing %s...\n", name))
  df <- read_dane(path, name)
  if (!is.null(df)) {
    out_path <- file.path(out_dir, paste0(name, "_clean.csv"))
    write_csv(df, out_path)
    cat(sprintf("  Saved %d rows (%s to %s)\n",
                nrow(df), min(df$date), max(df$date)))
  }
}

cat("DANE collection complete.\n")
