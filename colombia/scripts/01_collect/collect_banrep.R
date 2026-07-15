# colombia/scripts/01_collect/collect_banrep.R
# Downloads BanRep series via datos.gov.co API
# Exchange rate (TRM) available via open data API
# Interest rate, M1, credit downloaded as CSV from BanRep portal

library(dplyr)
library(readr)
library(httr2)
library(yaml)
library(here)
library(lubridate)

cfg     <- yaml::read_yaml(here("colombia/config/config.yaml"))
out_dir <- here("colombia/data/raw/banrep")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

start_date <- as.Date(cfg$dates$start)
end_date   <- as.Date(cfg$dates$end)

# ── 1. Exchange rate (TRM) via datos.gov.co Socrata API ──────────────────────
# Dataset: Tasa de Cambio Representativa del Mercado - Historico
# Resource ID: mcec-87by
cat("Downloading TRM (exchange rate) from datos.gov.co...\n")

tryCatch({
  url <- paste0(
    "https://www.datos.gov.co/resource/mcec-87by.csv",
    "?$limit=50000",
    "&$where=vigenciadesde >= '", format(start_date, "%Y-%m-%d"), "'",
    " AND vigenciadesde <= '", format(end_date, "%Y-%m-%d"), "'"
  )

  raw <- read_csv(url, show_col_types=FALSE)
  cat(sprintf("  Raw columns: %s\n", paste(names(raw), collapse=", ")))

  # Column names vary — find date and value columns
  date_col  <- grep("vigencia|fecha|date", names(raw), ignore.case=TRUE, value=TRUE)[1]
  value_col <- grep("valor|trm|value|tasa", names(raw), ignore.case=TRUE, value=TRUE)[1]

  df <- raw |>
    select(date=all_of(date_col), value=all_of(value_col)) |>
    mutate(
      date  = as.Date(substr(date, 1, 10)),
      value = as.numeric(value),
      series = "exchange_rate"
    ) |>
    filter(!is.na(value), date >= start_date, date <= end_date) |>
    arrange(date)

  write_csv(df, file.path(out_dir, "exchange_rate.csv"))
  cat(sprintf("  Saved %d rows -> banrep/exchange_rate.csv\n", nrow(df)))

}, error=function(e) {
  cat(sprintf("  ERROR: %s\n", conditionMessage(e)))
  cat("  Manual download: https://www.datos.gov.co/resource/mcec-87by.csv\n")
  # Create placeholder
  write_csv(data.frame(date=as.Date(character()), value=numeric(), series=character()),
            file.path(out_dir, "exchange_rate.csv"))
})

# ── 2. Placeholders for manual downloads ─────────────────────────────────────
# BanRep interest rate, M1, and credit require manual download from:
# https://suameca.banrep.gov.co/descarga-multiple-de-datos/

for (series in c("interest_rate", "m1", "credit")) {
  path <- file.path(out_dir, paste0(series, ".csv"))
  if (!file.exists(path)) {
    write_csv(
      data.frame(date=as.Date(character()), value=numeric(), series=character()),
      path
    )
    cat(sprintf("Placeholder created: banrep/%s.csv\n", series))
    cat(sprintf("  -> Download manually from: https://suameca.banrep.gov.co/descarga-multiple-de-datos/\n"))
  }
}

cat("\nBanRep collection complete.\n")
cat("Manual downloads needed for: interest_rate, m1, credit\n")
cat("URL: https://suameca.banrep.gov.co/descarga-multiple-de-datos/\n")
