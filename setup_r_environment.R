options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::init()
packages <- c("tidyverse","lubridate","tseries","forecast","xts","zoo","httr2","jsonlite","readxl","here","glue","tictoc")
install.packages(packages)
renv::snapshot()
message("R environment ready.")
