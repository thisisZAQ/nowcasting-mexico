# scripts/02_process/adf_tests.R
# Augmented Dickey-Fuller unit root tests on all series
# Tests levels and first differences
# Output: outputs/tables/adf_results.csv + LaTeX table

library(dplyr)
library(readr)
library(urca)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("config", "config.yaml"))
out_dir <- here("outputs", "tables")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

# ── Load processed panel ──────────────────────────────────────────────────────
trad <- read_csv(here("data/processed/traditional_indicators.csv"),
                 show_col_types=FALSE) |>
  mutate(date=as.Date(date))

# Test both levels and differences
level_vars <- c("igae_sa", "ip_sa", "retail_sa", "unemp_sa",
                "fx_avg", "cetes_28", "m1", "credit")
diff_vars  <- c("igae_ldiff", "ip_ldiff", "retail_ldiff", "unemp_diff",
                "fx_ldiff", "cetes_diff", "m1_ldiff", "credit_ldiff")

labels <- c("IGAE", "Industrial production", "Retail sales",
            "Unemployment rate", "Exchange rate (MXN/USD)",
            "CETES 28-day", "M1 money supply", "Private credit")

# ── ADF test helper ───────────────────────────────────────────────────────────
run_adf <- function(x, label, type="drift") {
  x <- x[!is.na(x)]
  if (length(x) < 20) return(NULL)
  tryCatch({
    fit  <- ur.df(x, type=type, selectlags="AIC")
    stat <- fit@teststat[1]
    crit <- fit@cval[1, ]  # 1%, 5%, 10%
    tibble(
      series    = label,
      adf_stat  = round(stat, 3),
      crit_1pct = round(crit["1pct"], 3),
      crit_5pct = round(crit["5pct"], 3),
      crit_10pct= round(crit["10pct"], 3),
      reject_5pct = stat < crit["5pct"]
    )
  }, error=function(e) NULL)
}

# ── Run tests ─────────────────────────────────────────────────────────────────
cat("Running ADF tests on levels...\n")
level_results <- bind_rows(mapply(function(v, l) {
  if (!v %in% names(trad)) return(NULL)
  run_adf(trad[[v]], l)
}, level_vars, labels, SIMPLIFY=FALSE))

cat("Running ADF tests on first differences...\n")
diff_results <- bind_rows(mapply(function(v, l) {
  if (!v %in% names(trad)) return(NULL)
  run_adf(trad[[v]], l, type="none")
}, diff_vars, labels, SIMPLIFY=FALSE))

# ── Combine ───────────────────────────────────────────────────────────────────
results <- bind_rows(
  level_results |> mutate(transformation="Level"),
  diff_results  |> mutate(transformation="First difference")
) |>
  select(series, transformation, adf_stat, crit_5pct, reject_5pct)

cat("\n── ADF Results ──────────────────────────────────────────────────────\n")
print(results, n=Inf)

write_csv(results, file.path(out_dir, "adf_results.csv"))
cat("\nSaved -> outputs/tables/adf_results.csv\n")

# ── LaTeX table ───────────────────────────────────────────────────────────────
lines <- c(
  "\\begin{table}[htbp]",
  "  \\centering",
  "  \\caption{Augmented Dickey-Fuller Unit Root Tests}",
  "  \\label{tab:adf}",
  "  \\begin{tabular}{llccc}",
  "    \\hline\\hline",
  "    Series & Transformation & ADF stat & CV (5\\%) & Stationary? \\\\",
  "    \\hline"
)

for (i in seq_len(nrow(results))) {
  r      <- results[i, ]
  star   <- ifelse(r$reject_5pct, "Yes$^{**}$", "No")
  lines  <- c(lines, sprintf("    %s & %s & %.3f & %.3f & %s \\\\",
                              r$series, r$transformation,
                              r$adf_stat, r$crit_5pct, star))
}

lines <- c(lines,
  "    \\hline",
  "    \\multicolumn{5}{l}{\\footnotesize Note: ADF with AIC lag selection. $^{**}$ reject unit root at 5\\%.} \\\\",
  "    \\hline\\hline",
  "  \\end{tabular}",
  "\\end{table}"
)

writeLines(lines, file.path(here("outputs/manuscript"), "adf_table.tex"))
cat("Saved -> outputs/manuscript/adf_table.tex\n")
