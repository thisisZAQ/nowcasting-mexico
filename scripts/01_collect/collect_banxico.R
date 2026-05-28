library(siebanxicor)
library(dplyr)
library(readr)
library(yaml)
library(here)

cfg        <- yaml::read_yaml(here("config", "config.yaml"))
start_date <- cfg$dates$start
end_date   <- cfg$dates$end

token <- Sys.getenv(cfg$banxico$token_env_var)
if (nchar(token) == 0) stop("BANXICO_TOKEN not found")
setToken(token)

series_map <- c(
  exchange_rate  = "SF43718",
  cetes_28       = "SF43936",
  m1             = "SF311408",
  credit_private = "SF30626"
)

out_dir <- here("data", "raw", "banxico")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (name in names(series_map)) {
  series_id <- series_map[[name]]
  cat(sprintf("Downloading %s (%s)...\n", name, series_id))
  tryCatch({
    raw <- getSeriesData(series_id, startDate = start_date, endDate = end_date)
    df  <- as.data.frame(lapply(raw[[1]], unlist), stringsAsFactors = FALSE)
    colnames(df) <- c("date", "value")
    df <- df |>
      mutate(date = as.Date(date), value = as.numeric(value), series = name, id = series_id) |>
      filter(!is.na(value)) |>
      arrange(date)
    out_path <- file.path(out_dir, paste0(name, ".csv"))
    write_csv(df, out_path)
    cat(sprintf("  Saved %d rows -> %s\n", nrow(df), out_path))
  }, error = function(e) cat(sprintf("  ERROR: %s\n", conditionMessage(e))))
}

cat("Banxico collection complete.\n")
