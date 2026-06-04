library(nowcasting); library(readr); library(dplyr)

df <- read_csv("data/final/dataset_full.csv", show_col_types=FALSE) |>
  mutate(date=as.Date(date)) |>
  filter(!is.na(igae_ldiff))

# Use only traditional vars — no NAs except first row from differencing
trad <- c("igae_ldiff","ip_ldiff","unemp_diff","fx_ldiff",
          "cetes_diff","m1_ldiff","credit_ldiff")

train <- df[1:95, trad]
# Drop first row (NA from differencing)
train <- train[complete.cases(train), ]
cat("train dim:", dim(train), "\n")

X_ts <- ts(as.matrix(train), start=c(2010,2), frequency=12)
blocks <- matrix(1, nrow=length(trad), ncol=2)
rownames(blocks) <- trad
freq <- rep(12, length(trad))

cat("Trying EM on traditional vars only...\n")
tryCatch({
  fit <- nowcast(formula=igae_ldiff~., data=X_ts, r=2, p=2,
                 method="EM", blocks=blocks, frequency=freq)
  cat("SUCCESS\n")
  cat("yfcst colnames:", paste(colnames(fit$yfcst), collapse=", "), "\n")
  print(tail(fit$yfcst, 3))
}, error=function(e) cat("ERROR:", conditionMessage(e), "\n"))
