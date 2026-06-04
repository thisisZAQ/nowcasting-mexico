# scripts/03_model/model_ml.py
# ML nowcasting models: LASSO, Ridge, Random Forest
# Expanding window pseudo OOS evaluation
# Output: data/final/forecasts_ml.csv

import pandas as pd
import numpy as np
import yaml
from pathlib import Path
from sklearn.linear_model import LassoCV, RidgeCV
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

# ── Config ────────────────────────────────────────────────────────────────────
with open("config/config.yaml", "r") as f:
    cfg = yaml.safe_load(f)

oos_start  = pd.Timestamp(cfg["evaluation"]["pseudo_oos_start"])
cv_folds   = cfg["models"]["ml"]["cv_folds"]
final_dir  = Path(cfg["paths"]["final"])

# ── Load data ─────────────────────────────────────────────────────────────────
print("Loading dataset...")
df = pd.read_csv(final_dir / "dataset_full.csv", parse_dates=["date"])
df = df[df["igae_ldiff"].notna()].reset_index(drop=True)

print(f"Sample: {df.date.min().date()} to {df.date.max().date()} ({len(df)} obs)")

# ── Feature sets ──────────────────────────────────────────────────────────────
trad_vars   = ["ip_ldiff", "unemp_diff", "fx_ldiff",
               "cetes_diff", "m1_ldiff", "credit_ldiff"]
trends_vars = [c for c in df.columns if c.startswith("gt_")]
mob_vars    = [c for c in df.columns if c.startswith("mob_")]
all_features = trad_vars + trends_vars + mob_vars

# Add lags of target (AR component)
for k in range(1, 5):
    df[f"igae_lag{k}"] = df["igae_ldiff"].shift(k)
    all_features.append(f"igae_lag{k}")

print(f"Features: {len(all_features)} total")

# ── Models ────────────────────────────────────────────────────────────────────
models = {
    "lasso": Pipeline([
        ("scaler", StandardScaler()),
        ("model",  LassoCV(cv=cv_folds, max_iter=5000, random_state=42))
    ]),
    "ridge": Pipeline([
        ("scaler", StandardScaler()),
        ("model",  RidgeCV(cv=cv_folds))
    ]),
    "rf": RandomForestRegressor(
        n_estimators=100, max_depth=5,
        min_samples_leaf=5, random_state=42, n_jobs=-1
    )
}

# ── Pseudo OOS expanding window ───────────────────────────────────────────────
oos_mask  = df["date"] >= oos_start
oos_idx   = df.index[oos_mask].tolist()
results   = {name: [np.nan] * len(oos_idx) for name in models}

print(f"Running {len(oos_idx)} OOS forecasts...")

for i, t in enumerate(oos_idx):
    train = df.iloc[:t].copy()

    # Use complete cases for traditional vars
    trad_complete = train[trad_vars + ["igae_ldiff"]].notna().all(axis=1)
    train = train[trad_complete]
    if len(train) < 30:
        continue

    # Fill NAs in alternative vars with column mean
    X_train = train[all_features].copy()
    X_train = X_train.fillna(X_train.mean())
    X_train = X_train.fillna(0)  # fallback for all-NA columns
    y_train = train["igae_ldiff"].values

    # Test point
    X_test = df.iloc[[t]][all_features].copy()
    X_test = X_test.fillna(X_train.mean())
    X_test = X_test.fillna(0)

    for name, model in models.items():
        try:
            model.fit(X_train, y_train)
            pred = model.predict(X_test)[0]
            results[name][i] = float(pred)
        except Exception as e:
            pass

    if (i + 1) % 20 == 0:
        print(f"  {i+1}/{len(oos_idx)} done")

# ── Compile results ───────────────────────────────────────────────────────────
out = df.iloc[oos_idx][["date", "igae_ldiff"]].copy().reset_index(drop=True)
out = out.rename(columns={"igae_ldiff": "actual"})

for name in models:
    out[f"forecast_{name}"] = results[name]

print(f"\nForecasts generated: {len(out)}")

# RMSE per model
for name in models:
    col  = f"forecast_{name}"
    mask = out[col].notna() & out["actual"].notna()
    rmse = np.sqrt(((out.loc[mask, "actual"] - out.loc[mask, col]) ** 2).mean())
    print(f"{name.upper()} RMSE: {rmse:.6f}")

# ── Save ──────────────────────────────────────────────────────────────────────
out_path = final_dir / "forecasts_ml.csv"
out.to_csv(out_path, index=False)
print(f"\nSaved -> {out_path}")
