# DEPLOY TO POSIT CONNECT CLOUD
# Run from the project root after prepare_data.R and after reviewing data-sharing.
# Requires an authenticated Posit Connect Cloud account.
# Do not store API tokens in files in the app directory.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop('Install rsconnect first: install.packages("rsconnect")')
}
app_dir <- if (file.exists("AAT_Burden_Explorer_Web/app.R")) {
  "AAT_Burden_Explorer_Web"
} else if (file.exists("app.R")) {
  "."
} else stop("Run from the project root or the app folder.")

must_have <- c(
  "Prediction_cells_tsetse_distance_cattle_and_burden.csv",
  "Uncertainty_only_primary_masks_25km.csv"
)
missing <- must_have[!file.exists(file.path(app_dir, "data", must_have))]
if (length(missing)) stop(
  "First run prepare_data.R. Missing: ", paste(missing, collapse=", ")
)

# IMPORTANT: Explicitly select one of the two modes below.
# A public app exposes the precomputed cell-level outputs to visitors.
visibility <- Sys.getenv("AAT_WEB_VISIBILITY", unset="")
if (!visibility %in% c("public", "private")) stop(
  "Choose access deliberately before deploying.\n",
  'For private sharing: Sys.setenv(AAT_WEB_VISIBILITY="private")\n',
  'For publicly approved outputs: Sys.setenv(AAT_WEB_VISIBILITY="public")\n',
  "Then source this deployment script again.\n",
  "Note: private apps need Enhanced or higher on Connect Cloud."
)

# First-time setup once, interactively in the R console:
# rsconnect::connectCloudUser()
# Only publish the runtime application and its three precomputed data CSVs.
# Do NOT include prepare_data.R or this deploy script: rsconnect would scan
# them as application code and incorrectly add deployment-only dependencies
# (including rsconnect -> openssl) to the server environment.
data_files <- file.path("data", c(
  "Prediction_cells_tsetse_distance_cattle_and_burden.csv",
  "Uncertainty_only_primary_masks_25km.csv"
))
optional_file <- file.path("data", "Uncertainty_only_mask_thresholds.csv")
if (file.exists(file.path(app_dir, optional_file))) {
  data_files <- c(data_files, optional_file)
}
bundle_files <- c("app.R", data_files)

rsconnect::deployApp(
  appDir = app_dir,
  appFiles = bundle_files,
  appName = "aat-burden-explorer",
  appTitle = "AAT Burden & Reporting Domain Explorer",
  appVisibility = visibility,
  launch.browser = TRUE
)
