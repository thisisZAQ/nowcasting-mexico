# Snakefile
# Nowcasting Economic Activity in Mexico
# Run: snakemake --cores 4
# DAG: snakemake --dag | dot -Tpdf > outputs/figures/dag.pdf

import yaml

# ── Load config ───────────────────────────────────────────────────────────────
configfile: "config/config.yaml"

# ── Target rule: defines the final outputs of the full pipeline ───────────────
rule all:
    input:
        "outputs/tables/forecast_errors.csv",
        "outputs/tables/dm_test_results.csv",
        "outputs/figures/forecast_comparison.png",
        "outputs/figures/rmse_by_model.png",
        "outputs/manuscript/results_summary.tex"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1 — DATA COLLECTION
# ══════════════════════════════════════════════════════════════════════════════

rule collect_inegi:
    output:
        igae                 = "data/raw/inegi/igae.csv",
        industrial_production= "data/raw/inegi/industrial_production.csv",
        retail_sales         = "data/raw/inegi/retail_sales.csv",
        employment_imss      = "data/raw/inegi/employment_imss.csv"
    log:
        "logs/collect_inegi.log"
    script:
        "scripts/01_collect/collect_inegi.R"

rule collect_banxico:
    output:
        exchange_rate  = "data/raw/banxico/exchange_rate.csv",
        cetes_28       = "data/raw/banxico/cetes_28.csv",
        remittances    = "data/raw/banxico/remittances.csv",
        m1             = "data/raw/banxico/m1.csv",
        credit_private = "data/raw/banxico/credit_private.csv"
    log:
        "logs/collect_banxico.log"
    script:
        "scripts/01_collect/collect_banxico.R"

rule collect_google_trends:
    output:
        trends = "data/raw/google_trends/google_trends.csv"
    log:
        "logs/collect_google_trends.log"
    script:
        "scripts/01_collect/collect_google_trends.R"

rule collect_mobility:
    output:
        google_mobility = "data/raw/mobility/google_mobility_MX.csv",
        apple_mobility  = "data/raw/mobility/apple_mobility_MX.csv"
    log:
        "logs/collect_mobility.log"
    script:
        "scripts/01_collect/collect_mobility.R"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2 — DATA PROCESSING
# ══════════════════════════════════════════════════════════════════════════════

rule process_traditional:
    input:
        igae                 = "data/raw/inegi/igae.csv",
        industrial_production= "data/raw/inegi/industrial_production.csv",
        retail_sales         = "data/raw/inegi/retail_sales.csv",
        employment_imss      = "data/raw/inegi/employment_imss.csv",
        exchange_rate        = "data/raw/banxico/exchange_rate.csv",
        cetes_28             = "data/raw/banxico/cetes_28.csv"
    output:
        "data/processed/traditional_indicators.csv"
    log:
        "logs/process_traditional.log"
    script:
        "scripts/02_process/process_traditional.R"

rule process_alternative:
    input:
        trends          = "data/raw/google_trends/google_trends.csv",
        google_mobility = "data/raw/mobility/google_mobility_MX.csv",
        apple_mobility  = "data/raw/mobility/apple_mobility_MX.csv",
        remittances     = "data/raw/banxico/remittances.csv",
        m1              = "data/raw/banxico/m1.csv",
        credit_private  = "data/raw/banxico/credit_private.csv"
    output:
        "data/processed/alternative_indicators.csv"
    log:
        "logs/process_alternative.log"
    script:
        "scripts/02_process/process_alternative.R"

rule build_model_dataset:
    input:
        traditional = "data/processed/traditional_indicators.csv",
        alternative = "data/processed/alternative_indicators.csv"
    output:
        full    = "data/final/dataset_full.csv",
        trad    = "data/final/dataset_traditional.csv"
    log:
        "logs/build_model_dataset.log"
    script:
        "scripts/02_process/build_model_dataset.R"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3 — MODELS
# ══════════════════════════════════════════════════════════════════════════════

rule model_benchmark_ar:
    input:
        "data/final/dataset_traditional.csv"
    output:
        "data/final/forecasts_ar.csv"
    log:
        "logs/model_ar.log"
    script:
        "scripts/03_model/model_ar.R"

rule model_benchmark_dfm:
    input:
        "data/final/dataset_traditional.csv"
    output:
        "data/final/forecasts_dfm_benchmark.csv"
    log:
        "logs/model_dfm_benchmark.log"
    script:
        "scripts/03_model/model_dfm_benchmark.R"

rule model_augmented_dfm:
    input:
        "data/final/dataset_full.csv"
    output:
        "data/final/forecasts_dfm_augmented.csv"
    log:
        "logs/model_dfm_augmented.log"
    script:
        "scripts/03_model/model_dfm_augmented.R"

rule model_ml:
    input:
        "data/final/dataset_full.csv"
    output:
        "data/final/forecasts_ml.csv"
    log:
        "logs/model_ml.py.log"
    script:
        "scripts/03_model/model_ml.py"

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 4 — EVALUATION
# ══════════════════════════════════════════════════════════════════════════════

rule evaluate:
    input:
        actual           = "data/final/dataset_traditional.csv",
        ar               = "data/final/forecasts_ar.csv",
        dfm_benchmark    = "data/final/forecasts_dfm_benchmark.csv",
        dfm_augmented    = "data/final/forecasts_dfm_augmented.csv",
        ml               = "data/final/forecasts_ml.csv"
    output:
        forecast_errors  = "outputs/tables/forecast_errors.csv",
        dm_results       = "outputs/tables/dm_test_results.csv"
    log:
        "logs/evaluate.log"
    script:
        "scripts/04_evaluate/evaluate.R"

rule plot_results:
    input:
        forecast_errors = "outputs/tables/forecast_errors.csv",
        dm_results      = "outputs/tables/dm_test_results.csv"
    output:
        forecast_plot   = "outputs/figures/forecast_comparison.png",
        rmse_plot       = "outputs/figures/rmse_by_model.png"
    log:
        "logs/plot_results.log"
    script:
        "scripts/04_evaluate/plot_results.R"

rule compile_results:
    input:
        forecast_errors = "outputs/tables/forecast_errors.csv",
        dm_results      = "outputs/tables/dm_test_results.csv"
    output:
        "outputs/manuscript/results_summary.tex"
    log:
        "logs/compile_results.log"
    script:
        "scripts/04_evaluate/compile_results.R"
