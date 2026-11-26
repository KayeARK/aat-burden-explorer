# PREPARE WEB DEPLOYMENT DATA
# Run from your project root, the folder containing Code_Nagana/.
# Example: source("AAT_Burden_Explorer_Web/prepare_data.R")
# Copies ONLY three precomputed output CSVs; no raw survey records, INLA model
# files, raster source files, nor the 1,000 adjustment iterations are uploaded.

files_required <- c(
  "Prediction_cells_tsetse_distance_cattle_and_burden.csv",
  "Uncertainty_only_primary_masks_25km.csv"
)
file_optional <- "Uncertainty_only_mask_thresholds.csv"

locate_app <- function() {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  candidates <- c(
    file.path(wd, "AAT_Burden_Explorer_Web"),
    wd,
    file.path(dirname(wd), "AAT_Burden_Explorer_Web")
  )
  candidates <- unique(candidates)
  choices <- candidates[file.exists(file.path(candidates, "app.R"))]
  if (!length(choices)) stop(
    "Cannot locate AAT_Burden_Explorer_Web/app.R. Run this script from the project root."
  )
  normalizePath(choices[1], winslash = "/", mustWork = TRUE)
}

app_dir <- locate_app()
project_root <- dirname(app_dir)
audit_dir <- Sys.getenv("AAT_AUDIT_DIR", "")
if (!nzchar(audit_dir)) {
  audit_dir <- file.path(project_root, "Code_Nagana", "Results", "Tsetse_belt_audit")
}
if (!dir.exists(audit_dir)) stop(
  "Audit output folder not found: ", audit_dir,
  "\nRun the audit in the same project, or set AAT_AUDIT_DIR."
)

missing <- files_required[!file.exists(file.path(audit_dir, files_required))]
if (length(missing)) stop(
  "Required audit outputs missing: ", paste(missing, collapse = ", ")
)

# Header checks catch accidentally copying the wrong version of audit results.
expect <- list(
  Prediction_cells_tsetse_distance_cattle_and_burden.csv =
    c("cell_id", "Country", "iso_a3", "Mean_Prevalence", "Cattle_total",
      "Infected_total", "Cattle_inside", "Cattle_outside_0_25",
      "Cattle_outside_25_50", "Cattle_outside_50_100",
      "Cattle_outside_100_200", "Cattle_outside_gt_200", "Cattle_unknown"),
  Uncertainty_only_primary_masks_25km.csv =
    c("cell_id", "Posterior_CrI_Width", "Posterior_Logit_CrI_Width")
)
for (f in files_required) {
  names_found <- names(read.csv(file.path(audit_dir, f), nrows = 1,
                               check.names = FALSE))
  absent <- setdiff(expect[[f]], names_found)
  if (length(absent)) stop(f, " is missing columns: ", paste(absent, collapse = ", "))
}

files_to_copy <- c(files_required,
                   if (file.exists(file.path(audit_dir, file_optional))) file_optional)
dest <- file.path(app_dir, "data")
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
for (f in files_to_copy) {
  src <- file.path(audit_dir, f)
  dst <- file.path(dest, f)
  if (!file.copy(src, dst, overwrite = TRUE)) stop("Could not copy ", f)
  cat(sprintf("Included %-60s %8.2f MB\n", f, file.info(dst)$size / 1024^2))
}

cat("\nPrepared a self-contained deployment snapshot in:\n", dest, "\n", sep="")
cat("WARNING: If published publicly, these cell-level model outputs can be downloaded.\n")
cat("Review data-sharing permission and hosting visibility before deployment.\n")
cat("The app does not change your original audit outputs.\n")
