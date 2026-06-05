# nowcasting-mexico

**Nowcasting Economic Activity in an Emerging Market Using Alternative High-Frequency Data: Evidence from Mexico**

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20563443.svg)](https://doi.org/10.5281/zenodo.20563443)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Research Question

Can alternative high-frequency data (Google Trends, mobility indicators, payment proxies) significantly improve real-time nowcasting accuracy of Mexican economic activity compared with models based solely on traditional official statistics?

## Key Finding

LASSO with alternative data reduces RMSE by **72%** vs the AR(4) benchmark over 2018–2024, with the largest gains during the COVID-19 shock (2020–2021) where RMSE is reduced by **79%**.

## Models

| Model | RMSE | vs AR(4) |
|-------|------|----------|
| LASSO | 0.0145 | −72% |
| Ridge | 0.0182 | −65% |
| MIDAS | 0.0278 | −47% |
| DFM Benchmark | 0.0280 | −47% |
| DFM Augmented | 0.0283 | −46% |
| Random Forest | 0.0286 | −46% |
| AR(4) | 0.0527 | baseline |

## Data Sources

- **IGAE** (target): INEGI Global Indicator of Economic Activity
- **Traditional**: Industrial production, retail sales, unemployment (INEGI); exchange rate, CETES, M1, credit (Banxico)
- **Alternative**: Google Trends (7 keywords), Google Mobility (2020–2022)

## Reproducibility

### Option 1: Docker (recommended)

```bash
docker build -t nowcasting-mexico .
docker run -v $(pwd)/data:/project/data \
           -v $(pwd)/outputs:/project/outputs \
           nowcasting-mexico snakemake --cores 4
```

### Option 2: Local setup

```bash
git clone https://github.com/thisisZAQ/nowcasting-mexico.git
cd nowcasting-mexico

# R environment
Rscript setup_r_environment.R

# Python environment
python3 setup_python_environment.py
source .venv/bin/activate

# Run full pipeline
snakemake --cores 4
```

### Requirements

- R >= 4.3
- Python >= 3.10
- Graphviz (for DAG: `brew install graphviz`)
- Banxico API token (store in `.env` as `BANXICO_TOKEN=your_token`)
- INEGI flat files (see `scripts/01_collect/collect_inegi.R` for instructions)

## Project Structure

```
nowcasting-mexico/
├── config/config.yaml          # All parameters — nothing hardcoded
├── Snakefile                   # Full pipeline DAG
├── scripts/
│   ├── 01_collect/             # Data collection (Banxico, INEGI, Trends, Mobility)
│   ├── 02_process/             # Cleaning, ADF tests, seasonal adjustment
│   ├── 03_model/               # AR, DFM, MIDAS, LASSO, Ridge, RF
│   └── 04_evaluate/            # RMSE, DM tests, sub-period analysis, figures
├── outputs/
│   ├── figures/                # Thesis-quality plots
│   ├── tables/                 # CSV results tables
│   └── manuscript/             # LaTeX tables ready to include
├── renv.lock                   # R environment lock
└── environment/requirements.txt # Python environment lock
```

## Citation

```bibtex
@software{qureshi2026nowcasting,
  author = {Qureshi, Zahra},
  title  = {nowcasting-mexico: Nowcasting Economic Activity in Mexico Using Alternative High-Frequency Data},
  year   = {2026},
  url    = {https://github.com/thisisZAQ/nowcasting-mexico},
  doi    = {10.5281/zenodo.20563443}
}
```

## Supervisor

Professor Enda Hargarden, University College Dublin
