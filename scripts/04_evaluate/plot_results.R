# scripts/04_evaluate/plot_results.R
# Generates thesis-quality figures
# Outputs:
#   outputs/figures/forecast_comparison.png
#   outputs/figures/rmse_by_model.png

library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(yaml)
library(here)

cfg     <- yaml::read_yaml(here("config", "config.yaml"))
fig_dir <- here("outputs", "figures")
dir.create(fig_dir, showWarnings=FALSE, recursive=TRUE)

# ── Load data ─────────────────────────────────────────────────────────────────
ar    <- read_csv(here("data/final/forecasts_ar.csv"), show_col_types=FALSE)
dfm_b <- read_csv(here("data/final/forecasts_dfm_benchmark.csv"), show_col_types=FALSE)
dfm_a <- read_csv(here("data/final/forecasts_dfm_augmented.csv"), show_col_types=FALSE)
ml    <- read_csv(here("data/final/forecasts_ml.csv"), show_col_types=FALSE)
errors <- read_csv(here("outputs/tables/forecast_errors.csv"), show_col_types=FALSE)

all_fc <- ar |>
  select(date, actual, forecast_ar) |>
  left_join(dfm_b |> select(date, forecast_dfm_benchmark), by="date") |>
  left_join(dfm_a |> select(date, forecast_dfm_augmented), by="date") |>
  left_join(ml    |> select(date, forecast_lasso, forecast_ridge, forecast_rf), by="date") |>
  mutate(date=as.Date(date))

# ── Theme ─────────────────────────────────────────────────────────────────────
theme_thesis <- theme_minimal(base_size=11) +
  theme(
    panel.grid.minor   = element_blank(),
    legend.position    = "bottom",
    legend.title       = element_blank(),
    plot.title         = element_text(face="bold", size=12),
    plot.subtitle      = element_text(color="grey40", size=10),
    axis.title         = element_text(size=10),
    strip.text         = element_text(face="bold")
  )

# ── Figure 1: Forecast comparison ─────────────────────────────────────────────
fc_long <- all_fc |>
  select(date, actual,
         `AR(4)`          = forecast_ar,
         `DFM Benchmark`  = forecast_dfm_benchmark,
         `LASSO`          = forecast_lasso) |>
  pivot_longer(-date, names_to="model", values_to="value") |>
  mutate(model=factor(model, levels=c("actual","AR(4)","DFM Benchmark","LASSO")))

colors <- c("actual"="black", "AR(4)"="#E07B54",
            "DFM Benchmark"="#5B8DB8", "LASSO"="#4CAF50")

p1 <- ggplot(fc_long, aes(x=date, y=value, color=model, linetype=model)) +
  geom_line(linewidth=0.7) +
  geom_hline(yintercept=0, linetype="dashed", color="grey60", linewidth=0.4) +
  scale_color_manual(values=colors) +
  scale_linetype_manual(values=c("actual"="solid","AR(4)"="dashed",
                                  "DFM Benchmark"="dashed","LASSO"="solid")) +
  scale_x_date(date_breaks="1 year", date_labels="%Y") +
  labs(
    title    = "Nowcast Comparison: Actual vs. Model Forecasts",
    subtitle = "Monthly log-growth of IGAE, pseudo out-of-sample 2018–2024",
    x        = NULL,
    y        = "Log-difference (monthly growth)"
  ) +
  theme_thesis

ggsave(file.path(fig_dir, "forecast_comparison.png"),
       p1, width=10, height=5, dpi=300)
cat("Saved forecast_comparison.png\n")

# ── Figure 2: RMSE bar chart ──────────────────────────────────────────────────
errors_plot <- errors |>
  mutate(model=factor(model, levels=rev(errors$model))) |>
  mutate(highlight=model=="LASSO")

p2 <- ggplot(errors_plot, aes(x=model, y=RMSE, fill=highlight)) +
  geom_col(width=0.6) +
  geom_text(aes(label=sprintf("%.4f", RMSE)), hjust=-0.1, size=3.2) +
  scale_fill_manual(values=c("FALSE"="#5B8DB8","TRUE"="#4CAF50"), guide="none") +
  coord_flip(ylim=c(0, max(errors$RMSE)*1.2)) +
  labs(
    title    = "Root Mean Square Error by Model",
    subtitle = "Pseudo out-of-sample evaluation, 2018–2024 (n=81)",
    x        = NULL,
    y        = "RMSE"
  ) +
  theme_thesis +
  theme(legend.position="none")

ggsave(file.path(fig_dir, "rmse_by_model.png"),
       p2, width=8, height=5, dpi=300)
cat("Saved rmse_by_model.png\n")

# ── Figure 3: Rolling RMSE ────────────────────────────────────────────────────
window <- 12
roll_rmse <- all_fc |>
  mutate(
    e_ar    = (actual - forecast_ar)^2,
    e_lasso = (actual - forecast_lasso)^2
  ) |>
  arrange(date) |>
  mutate(
    rmse_ar    = sqrt(zoo::rollmean(e_ar,    window, fill=NA, align="right")),
    rmse_lasso = sqrt(zoo::rollmean(e_lasso, window, fill=NA, align="right"))
  ) |>
  select(date, `AR(4)`=rmse_ar, `LASSO`=rmse_lasso) |>
  pivot_longer(-date, names_to="model", values_to="rmse") |>
  filter(!is.na(rmse))

p3 <- ggplot(roll_rmse, aes(x=date, y=rmse, color=model)) +
  geom_line(linewidth=0.8) +
  scale_color_manual(values=c("AR(4)"="#E07B54","LASSO"="#4CAF50")) +
  scale_x_date(date_breaks="1 year", date_labels="%Y") +
  labs(
    title    = "Rolling 12-Month RMSE: AR(4) vs. LASSO",
    subtitle = "Shows periods where alternative data adds most value",
    x        = NULL,
    y        = "Rolling RMSE (12-month window)"
  ) +
  theme_thesis

ggsave(file.path(fig_dir, "rolling_rmse.png"),
       p3, width=10, height=5, dpi=300)
cat("Saved rolling_rmse.png\n")

cat("\nAll figures saved to outputs/figures/\n")
