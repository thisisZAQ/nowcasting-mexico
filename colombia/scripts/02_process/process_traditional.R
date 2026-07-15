# colombia/scripts/02_process/process_traditional.R
# Processes traditional indicators for Colombia
# Mirrors Mexico's process_traditional.R — adapted for Colombian data

library(dplyr)
library(readr)
library(lubridate)
library(zoo)
library(seasonal)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("colombia/config/config.yaml"))
start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)
raw_dir    <- here("colombia/data/raw")
out_dir    <- here("colombia/data/processed")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

log_diff <- function(x) c(NA, diff(log(x)))

seas_adjust <- function(df, series_name) {
  cat(sprintf("  X-13 adjusting %s...\n", series_name))
  tryCatch({
    ts_obj <- ts(df$value,
                 start=c(year(min(df$date)), month(min(df$date))),
                 frequency=12)
    fit  <- seas(ts_obj)
    df$value <- as.numeric(final(fit))
    return(df)
  }, error=function(e) {
    cat(sprintf("    X-13 failed for %s: %s — using original\n",
                series_name, conditionMessage(e)))
    return(df)
  })
}

read_clean <- function(path) {
  read_csv(path, show_col_types=FALSE) |> mutate(date=as.Date(date))
}

# ── 1. ISE — target variable ──────────────────────────────────────────────────
cat("Processing ISE...\n")
ise_sa <- read_clean(file.path(raw_dir, "dane/ise_sa.csv"))
ise <- ise_sa |>
  rename(ise_sa=value) |>
  select(date, ise_sa) |>
  mutate(ise_ldiff=log_diff(ise_sa))

# ── 2. Industrial production ──────────────────────────────────────────────────
cat("Processing industrial production...\n")
ip_raw <- read_clean(file.path(raw_dir, "dane/industrial_production.csv"))
# Already seasonally adjusted from EMMET
ip <- ip_raw |>
  rename(ip_sa=value) |>
  select(date, ip_sa) |>
  mutate(ip_ldiff=log_diff(ip_sa))

# ── 3. Retail sales ───────────────────────────────────────────────────────────
cat("Processing retail sales...\n")
retail_raw <- read_clean(file.path(raw_dir, "dane/retail_sales.csv"))
retail_sa  <- seas_adjust(retail_raw, "retail_sales")
retail <- retail_sa |>
  rename(retail_sa=value) |>
  select(date, retail_sa) |>
  mutate(retail_ldiff=log_diff(retail_sa))

# ── 4. Unemployment rate ──────────────────────────────────────────────────────
cat("Processing unemployment rate...\n")
unemp_raw <- read_clean(file.path(raw_dir, "dane/unemployment_rate.csv"))
unemp_sa  <- seas_adjust(unemp_raw, "unemployment_rate")
unemp <- unemp_sa |>
  rename(unemp_sa=value) |>
  select(date, unemp_sa) |>
  mutate(unemp_diff=c(NA, diff(unemp_sa)))

# ── 5. BanRep financial variables ─────────────────────────────────────────────
cat("Processing BanRep series...\n")

read_banrep <- function(name) {
  read_csv(file.path(raw_dir, "banrep", paste0(name, ".csv")),
           show_col_types=FALSE) |>
    mutate(date=as.Date(date)) |>
    select(date, value)
}

# Exchange rate: daily → monthly average
fx <- read_banrep("exchange_rate") |>
  mutate(month=floor_date(date, "month")) |>
  group_by(date=month) |>
  summarise(fx_avg=mean(value, na.rm=TRUE), .groups="drop") |>
  mutate(fx_ldiff=log_diff(fx_avg))

# Interest rate (monetary policy rate): already monthly
interest <- read_banrep("interest_rate") |>
  mutate(date=floor_date(date, "month")) |>
  group_by(date) |>
  summarise(interest_rate=mean(value, na.rm=TRUE), .groups="drop") |>
  mutate(interest_diff=c(NA, diff(interest_rate)))

# M1: already monthly
m1 <- read_banrep("m1") |>
  mutate(date=floor_date(date, "month")) |>
  rename(m1=value) |>
  mutate(m1_ldiff=log_diff(m1))

# Credit (consumer credit rate): already monthly
credit <- read_banrep("credit") |>
  mutate(date=floor_date(date, "month")) |>
  rename(credit_rate=value) |>
  mutate(credit_diff=c(NA, diff(credit_rate)))

# ── 6. Merge all into wide panel ──────────────────────────────────────────────
cat("Merging into wide panel...\n")

panel <- ise |>
  full_join(ip,       by="date") |>
  full_join(retail,   by="date") |>
  full_join(unemp,    by="date") |>
  full_join(fx,       by="date") |>
  full_join(interest, by="date") |>
  full_join(m1,       by="date") |>
  full_join(credit,   by="date") |>
  filter(day(date)==1, date>=start_date, date<=end_date) |>
  arrange(date)

cat(sprintf("\nPanel: %d rows x %d columns (%s to %s)\n",
            nrow(panel), ncol(panel), min(panel$date), max(panel$date)))
cat(sprintf("Columns: %s\n", paste(names(panel), collapse=", ")))

out_path <- file.path(out_dir, "traditional_indicators.csv")
write_csv(panel, out_path)
cat(sprintf("Saved -> %s\n", out_path))
