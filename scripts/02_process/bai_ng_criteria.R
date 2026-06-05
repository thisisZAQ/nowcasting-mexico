# scripts/02_process/bai_ng_criteria.R
# Bai & Ng (2002) information criteria for number of factors
# Tests IC1, IC2, IC3 on the traditional indicator panel
# Output: outputs/tables/bai_ng_results.csv + LaTeX

library(dplyr)
library(readr)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("config", "config.yaml"))
out_dir <- here("outputs", "tables")
ms_dir  <- here("outputs", "manuscript")

# ── Load and prep data ────────────────────────────────────────────────────────
cat("Loading traditional indicators...\n")
df <- read_csv(here("data/final/dataset_traditional.csv"),
               show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |>
  filter(!is.na(igae_ldiff))

pred_vars <- c("igae_ldiff","ip_ldiff","unemp_diff",
               "fx_ldiff","cetes_diff","m1_ldiff","credit_ldiff")

X <- as.matrix(df[complete.cases(df[,pred_vars]), pred_vars])
X <- scale(X)  # standardise
n <- nrow(X)
k <- ncol(X)

cat(sprintf("Panel: %d obs x %d variables\n", n, k))

# ── Bai-Ng IC criteria ────────────────────────────────────────────────────────
# V(r) = sum of squared residuals from r-factor model / (n*k)
# IC1 = log(V(r)) + r * (n+k)/(n*k) * log(n*k/(n+k))
# IC2 = log(V(r)) + r * (n+k)/(n*k) * log(min(n,k))
# IC3 = log(V(r)) + r * log(min(n,k)) / min(n,k)

r_max <- min(8, floor(min(n,k)/2))
results <- data.frame(r=1:r_max, V=NA, IC1=NA, IC2=NA, IC3=NA)

for (r in 1:r_max) {
  svd_X  <- svd(X, nu=r, nv=r)
  F_hat  <- svd_X$u %*% diag(svd_X$d[1:r], r, r)
  Lambda <- t(svd_X$v)
  resid  <- X - F_hat %*% Lambda
  V      <- sum(resid^2) / (n * k)

  g1 <- (n + k) / (n * k) * log(n * k / (n + k))
  g2 <- (n + k) / (n * k) * log(min(n, k))
  g3 <- log(min(n, k)) / min(n, k)

  results$V[r]   <- round(V, 6)
  results$IC1[r] <- round(log(V) + r * g1, 6)
  results$IC2[r] <- round(log(V) + r * g2, 6)
  results$IC3[r] <- round(log(V) + r * g3, 6)
}

cat("\n── Bai-Ng Information Criteria ──────────────────────────────────────\n")
print(results)

# Optimal r per criterion
cat(sprintf("\nOptimal r: IC1=%d, IC2=%d, IC3=%d\n",
            which.min(results$IC1),
            which.min(results$IC2),
            which.min(results$IC3)))

write_csv(results, file.path(out_dir, "bai_ng_results.csv"))
cat("Saved -> outputs/tables/bai_ng_results.csv\n")

# ── LaTeX table ───────────────────────────────────────────────────────────────
lines <- c(
  "\\begin{table}[htbp]",
  "  \\centering",
  "  \\caption{Bai-Ng (2002) Factor Selection Criteria}",
  "  \\label{tab:bai_ng}",
  "  \\begin{tabular}{lcccc}",
  "    \\hline\\hline",
  "    $r$ & $V(r)$ & IC1 & IC2 & IC3 \\\\",
  "    \\hline"
)

ic1_min <- which.min(results$IC1)
ic2_min <- which.min(results$IC2)
ic3_min <- which.min(results$IC3)

for (i in seq_len(nrow(results))) {
  r   <- results[i,]
  ic1 <- ifelse(i==ic1_min, sprintf("\\textbf{%.4f}", r$IC1), sprintf("%.4f", r$IC1))
  ic2 <- ifelse(i==ic2_min, sprintf("\\textbf{%.4f}", r$IC2), sprintf("%.4f", r$IC2))
  ic3 <- ifelse(i==ic3_min, sprintf("\\textbf{%.4f}", r$IC3), sprintf("%.4f", r$IC3))
  lines <- c(lines, sprintf("    %d & %.6f & %s & %s & %s \\\\",
                             r$r, r$V, ic1, ic2, ic3))
}

lines <- c(lines,
  "    \\hline",
  "    \\multicolumn{5}{l}{\\footnotesize Note: Bold = minimum IC. Selected $r$ used in DFM estimation.} \\\\",
  "    \\hline\\hline",
  "  \\end{tabular}",
  "\\end{table}"
)

writeLines(lines, file.path(ms_dir, "bai_ng_table.tex"))
cat("Saved -> outputs/manuscript/bai_ng_table.tex\n")
