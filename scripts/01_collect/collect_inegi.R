# scripts/01_collect/collect_inegi.R
library(dplyr)
library(readr)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("config", "config.yaml"))
out_dir <- here("data", "raw", "inegi")

read_bie <- function(path, series_name) {
  df <- read_csv(
    path,
    skip           = 5,
    col_names      = c("period", "value"),
    col_types      = cols(period = col_character(), value = col_character()),
    show_col_types = FALSE
  ) |>
    filter(!is.na(period), nchar(trimws(period)) == 7) |>
    mutate(
      date   = as.Date(paste0(gsub("/", "-", period), "-01")),
      value  = as.numeric(value),
      series = series_name
    ) |>
    filter(!is.na(value)) |>
    select(date, value, series) |>
    arrange(date)
  return(df)
}

files <- list(
  igae_original         = "igae_original_utf8.csv",
  igae_sa               = "igae_sa_utf8.csv",
  industrial_production = "industrial_production_utf8.csv",
  retail_sales          = "retail_sales_utf8.csv",
  unemployment_rate     = "employment_imss_utf8.csv"
)

for (name in names(files)) {
  path <- file.path(out_dir, files[[name]])
  if (!file.exists(path)) { cat(sprintf("SKIP: %s not found\n", name)); next }
  cat(sprintf("Processing %s...\n", name))
  tryCatch({
    df       <- read_bie(path, name)
    out_path <- file.path(out_dir, paste0(name, "_clean.csv"))
    write_csv(df, out_path)
    cat(sprintf("  Saved %d rows (%s to %s)\n", nrow(df), min(df$date), max(df$date)))
  }, error = function(e) cat(sprintf("  ERROR: %s\n", conditionMessage(e))))
}

cat("INEGI collection complete.\n")
