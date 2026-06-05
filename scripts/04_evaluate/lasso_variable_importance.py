# scripts/04_evaluate/lasso_variable_importance.py
# LASSO variable importance using ElasticNet (alpha=0.1, l1_ratio=0.9)
# Less aggressive than pure LASSO — shows which features consistently matter

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from pathlib import Path
from sklearn.linear_model import ElasticNet, LassoCV
from sklearn.preprocessing import StandardScaler
import yaml

with open("config/config.yaml") as f:
    cfg = yaml.safe_load(f)

final_dir  = Path(cfg["paths"]["final"])
out_tables = Path("outputs/tables")
out_figs   = Path("outputs/figures")
out_ms     = Path("outputs/manuscript")

df = pd.read_csv(final_dir / "dataset_full.csv", parse_dates=["date"])
df = df[df["igae_ldiff"].notna()].reset_index(drop=True)

trad_vars   = ["ip_ldiff","unemp_diff","fx_ldiff","cetes_diff","m1_ldiff","credit_ldiff"]
trends_vars = [c for c in df.columns if c.startswith("gt_")]
mob_vars    = [c for c in df.columns if c.startswith("mob_")]
all_features = trad_vars + trends_vars + mob_vars
for k in range(1, 4):
    df[f"igae_lag{k}"] = df["igae_ldiff"].shift(k)
    all_features.append(f"igae_lag{k}")

# Full sample
trad_c = df[trad_vars + ["igae_ldiff"]].notna().all(axis=1)
train  = df[trad_c].copy()
X = train[all_features].fillna(train[all_features].mean()).fillna(0)
y = train["igae_ldiff"].values

scaler   = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Use ElasticNet with mild regularisation — shows relative importance
model = ElasticNet(alpha=0.001, l1_ratio=0.9, max_iter=10000, random_state=42)
model.fit(X_scaled, y)

def label_type(f):
    if f.startswith("gt_"):   return "Google Trends"
    if f.startswith("mob_"):  return "Mobility"
    if f.startswith("igae_"): return "AR lags"
    return "Traditional"

def clean_name(f):
    names = {
        "ip_ldiff": "Ind. production (Δlog)",
        "unemp_diff": "Unemployment (Δ)",
        "fx_ldiff": "Exchange rate (Δlog)",
        "cetes_diff": "CETES 28-day (Δ)",
        "m1_ldiff": "M1 money supply (Δlog)",
        "credit_ldiff": "Private credit (Δlog)",
        "gt_IMSS_empleo": "GT: IMSS empleo",
        "gt_crdito_hipotecario": "GT: crédito hipotecario",
        "gt_desempleo_Mexico": "GT: desempleo México",
        "gt_inflacin_Mexico": "GT: inflación México",
        "gt_remate": "GT: remate",
        "gt_tipo_de_cambio": "GT: tipo de cambio",
        "gt_venta_de_autos": "GT: venta de autos",
        "igae_lag1": "IGAE lag 1",
        "igae_lag2": "IGAE lag 2",
        "igae_lag3": "IGAE lag 3",
    }
    return names.get(f, f)

coef_df = pd.DataFrame({
    "feature":     all_features,
    "coefficient": model.coef_,
    "abs_coef":    np.abs(model.coef_)
}).sort_values("abs_coef", ascending=False)
coef_df["type"]  = coef_df["feature"].apply(label_type)
coef_df["label"] = coef_df["feature"].apply(clean_name)

print("Top 15 features by absolute coefficient:")
print(coef_df.head(15)[["label","coefficient","type"]].to_string())

coef_df.to_csv(out_tables / "lasso_importance.csv", index=False)

# Plot top 12
top12 = coef_df.head(12).iloc[::-1]
colors = {"Google Trends":"#4CAF50","Mobility":"#9C27B0",
          "AR lags":"#FF9800","Traditional":"#5B8DB8"}

fig, ax = plt.subplots(figsize=(9, 6))
ax.barh(top12["label"], top12["coefficient"],
        color=[colors[t] for t in top12["type"]])
ax.axvline(0, color="black", linewidth=0.8)
ax.set_xlabel("Standardised coefficient (ElasticNet, α=0.001)", fontsize=10)
ax.set_title("Variable Importance in Regularised Model\n(Top 12 features by absolute coefficient)",
             fontsize=12, fontweight="bold")
legend_elements = [Patch(facecolor=v, label=k) for k,v in colors.items()
                   if k in top12["type"].values]
ax.legend(handles=legend_elements, loc="lower right", fontsize=9)
plt.tight_layout()
plt.savefig(out_figs / "lasso_importance.png", dpi=300, bbox_inches="tight")
print("Saved -> outputs/figures/lasso_importance.png")

# LaTeX table top 10
top10 = coef_df.head(10)
lines = [
    "\\begin{table}[htbp]",
    "  \\centering",
    "  \\caption{Variable Importance: Top 10 Features (ElasticNet)}",
    "  \\label{tab:lasso_importance}",
    "  \\begin{tabular}{llc}",
    "    \\hline\\hline",
    "    Feature & Type & Coefficient \\\\",
    "    \\hline"
]
for _, row in top10.iterrows():
    lines.append(f"    {row['label']} & {row['type']} & {row['coefficient']:.5f} \\\\")
lines += [
    "    \\hline",
    "    \\multicolumn{3}{l}{\\footnotesize Standardised coefficients, ElasticNet ($\\alpha=0.001$, $\\ell_1$-ratio$=0.9$).} \\\\",
    "    \\hline\\hline",
    "  \\end{tabular}",
    "\\end{table}"
]
with open(out_ms / "lasso_importance_table.tex", "w") as f:
    f.write("\n".join(lines))
print("Saved -> outputs/manuscript/lasso_importance_table.tex")
