# scripts/01_collect/collect_google_trends.R
# Downloads Google Trends data for Mexico using gtrendsR
# Outputs: data/raw/google_trends/google_trends.csv

library(gtrendsR)
library(dplyr)
library(readr)
library(yaml)
library(here)

# ── Config ────────────────────────────────────────────────────────────────────
cfg        <- yaml::read_yaml(here("config", "config.yaml"))
keywords   <- cfg$alternative$google_trends$keywords
geo        <- cfg$alternative$google_trends$geo
start_date <- cfg$dates$start
end_date   <- cfg$dates$end

time_range <- paste(start_date, end_date)

out_dir <- here("data", "raw", "google_trends")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── Download ──────────────────────────────────────────────────────────────────
# gtrendsR allows max 5 keywords per call — split into batches
batch_size <- 5
batches    <- split(keywords, ceiling(seq_along(keywords) / batch_size))

all_trends <- list()

for (i in seq_along(batches)) {
  batch <- batches[[i]]
  cat(sprintf("Downloading batch %d/%d: %s\n", i, length(batches), paste(batch, collapse=", ")))

  tryCatch({
    res <- gtrends(
      keyword    = batch,
      geo        = geo,
      time       = time_range,
      onlyInterest = TRUE
    )

    df <- res$interest_over_time |>
      select(date, keyword, hits) |>
      mutate(
        date = as.Date(date),
        hits = as.numeric(ifelse(hits == "<1", "0.5", hits))
      ) |>
      filter(!is.na(hits))

    all_trends[[i]] <- df
    cat(sprintf("  Got %d rows\n", nrow(df)))

    # Be polite to the API — avoid rate limiting
    if (i < length(batches)) Sys.sleep(2)

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", conditionMessage(e)))
  })
}

# ── Combine and save ──────────────────────────────────────────────────────────
if (length(all_trends) > 0) {
  combined <- bind_rows(all_trends) |>
    arrange(keyword, date)

  out_path <- file.path(out_dir, "google_trends.csv")
  write_csv(combined, out_path)
  cat(sprintf("\nSaved %d rows (%d keywords) -> %s\n",
              nrow(combined), n_distinct(combined$keyword), out_path))
} else {
  cat("No data downloaded.\n")
}
