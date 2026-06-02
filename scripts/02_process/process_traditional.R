# scripts/02_process/process_traditional.R
# Loads, transforms, and seasonally adjusts all traditional indicators
# Output: data/processed/traditional_indicators.csv (wide format, monthly)

library(dplyr)
library(tidyr)
library(readr)
library(lubridate)
library(zoo)
library(seasonal)
library(yaml)
library(here)

# ── Config ────────────────────────────────────────────────────────────────────
cfg        <- yaml::read_yaml(here("config", "config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
raw_dir    <- here("data", "raw")
out_dir    <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── Helper: log difference ────────────────────────────────────────────────────
log_diff <- function(x) c(NA, diff(log(x)))

# ── Helper: seasonal adjustment with X-13 ────────────────────────────────────
seas_adjust <- function(df, series_name) {
  cat(sprintf("  X-13 adjusting %s...\n", series_name))
  tryCatch({
    ts_obj <- ts(df$value,
                 start     = c(year(min(df$date)), month(min(df$date))),
                 frequency = 12)
    fit    <- seas(ts_obj)
    sa     <- as.numeric(final(fit))
    df$value <- sa
    return(df)
  }, error = function(e) {
    cat(sprintf("    X-13 failed for %s: %s — using original\n",
                series_name, conditionMessage(e)))
    return(df)
  })
}

# ── Helper: read clean INEGI file ─────────────────────────────────────────────
read_clean <- function(path) {
  read_csv(path, show_col_types = FALSE) |>
    mutate(date = as.Date(date))
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. IGAE — target variable
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing IGAE...\n")

igae_orig <- read_clean(file.path(raw_dir, "inegi/igae_original_clean.csv"))
igae_sa   <- read_clean(file.path(raw_dir, "inegi/igae_sa_clean.csv"))

# Use INEGI's own SA series as target (already adjusted)
igae <- igae_sa |>
  rename(igae_sa = value) |>
  select(date, igae_sa) |>
  mutate(igae_ldiff = log_diff(igae_sa))  # log-diff = monthly growth rate

# ══════════════════════════════════════════════════════════════════════════════
# 2. Industrial production
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing industrial production...\n")

ip_raw <- read_clean(file.path(raw_dir, "inegi/industrial_production_clean.csv"))
ip_sa  <- seas_adjust(ip_raw, "industrial_production")

ip <- ip_sa |>
  rename(ip_sa = value) |>
  select(date, ip_sa) |>
  mutate(ip_ldiff = log_diff(ip_sa))

# ══════════════════════════════════════════════════════════════════════════════
# 3. Retail sales
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing retail sales...\n")

retail_raw <- read_clean(file.path(raw_dir, "inegi/retail_sales_clean.csv"))
retail_sa  <- seas_adjust(retail_raw, "retail_sales")

retail <- retail_sa |>
  rename(retail_sa = value) |>
  select(date, retail_sa) |>
  mutate(retail_ldiff = log_diff(retail_sa))

# ══════════════════════════════════════════════════════════════════════════════
# 4. Unemployment rate
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing unemployment rate...\n")

unemp_raw <- read_clean(file.path(raw_dir, "inegi/unemployment_rate_clean.csv"))
unemp_sa  <- seas_adjust(unemp_raw, "unemployment_rate")

unemp <- unemp_sa |>
  rename(unemp_sa = value) |>
  select(date, unemp_sa) |>
  mutate(unemp_diff = c(NA, diff(unemp_sa)))  # diff (not log) for rates

# ══════════════════════════════════════════════════════════════════════════════
# 5. Banxico financial variables (already monthly or aggregated)
# ══════════════════════════════════════════════════════════════════════════════
cat("Processing Banxico series...\n")

read_banxico <- function(name) {
  read_csv(file.path(raw_dir, "banxico", paste0(name, ".csv")),
           show_col_types = FALSE) |>
    mutate(date = as.Date(date)) |>
    select(date, value)
}

# Exchange rate: daily -> monthly average
fx <- read_banxico("exchange_rate") |>
  mutate(month = floor_date(date, "month")) |>
  group_by(date = month) |>
  summarise(fx_avg = mean(value, na.rm = TRUE), .groups = "drop") |>
  mutate(fx_ldiff = log_diff(fx_avg))

# CETES 28: already monthly
cetes <- read_banxico("cetes_28") |>
  rename(cetes_28 = value) |>
  mutate(cetes_diff = c(NA, diff(cetes_28)))

# M1: already monthly
m1 <- read_banxico("m1") |>
  rename(m1 = value) |>
  mutate(m1_ldiff = log_diff(m1))

# Credit: already monthly
credit <- read_banxico("credit_private") |>
  rename(credit = value) |>
  mutate(credit_ldiff = log_diff(credit))

# ══════════════════════════════════════════════════════════════════════════════
# 6. Merge all into wide panel
# ══════════════════════════════════════════════════════════════════════════════
cat("Merging into wide panel...\n")

panel <- igae |>
  full_join(ip,     by = "date") |>
  full_join(retail, by = "date") |>
  full_join(unemp,  by = "date") |>
  full_join(fx,     by = "date") |>
  full_join(cetes,  by = "date") |>
  full_join(m1,     by = "date") |>
  full_join(credit, by = "date") |>
  filter(date >= start_date, date <= end_date) |>
  filter(day(date) == 1) |>
  arrange(date)

cat(sprintf("\nPanel: %d rows x %d columns (%s to %s)\n",
            nrow(panel), ncol(panel),
            min(panel$date), max(panel$date)))
cat(sprintf("Columns: %s\n", paste(names(panel), collapse = ", ")))

# ── Save ──────────────────────────────────────────────────────────────────────
out_path <- file.path(out_dir, "traditional_indicators.csv")
write_csv(panel, out_path)
cat(sprintf("\nSaved -> %s\n", out_path))
# Note: after full_join, check for duplicate dates from daily fx aggregation
