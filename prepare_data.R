# Run locally, never on GitHub Pages. Copy only the deployment data used by the app.
# From the project root, set the folder path below if needed.
# Sys.setenv(AAT_WEB_VISIBILITY="public") only after data-sharing approval.
if (Sys.getenv("AAT_WEB_VISIBILITY") != "public") stop("Set AAT_WEB_VISIBILITY=public only when derived cell-level data are approved for public release.")
app_candidates <- c("AAT_Burden_Explorer_Website", ".", "../AAT_Burden_Explorer_Website")
app_candidates <- app_candidates[file.exists(file.path(app_candidates,"model.js"))]
if (!length(app_candidates)) stop("Cannot locate website folder. Run from project root or website folder.")
app_dir <- normalizePath(app_candidates[1], mustWork=TRUE)
audit_dir <- Sys.getenv("AAT_AUDIT_DIR", unset=file.path(dirname(app_dir),"Code_Nagana","Results","Tsetse_belt_audit"))
dest <- file.path(app_dir,"data"); dir.create(dest,showWarnings=FALSE,recursive=TRUE)
km <- c(seq(0,25,5),50,100,200)
zones <- c("Cattle_inside",paste0("Cattle_outside_",head(km,-1),"_",tail(km,-1)),"Cattle_outside_gt_200","Cattle_unknown")
expected <- list(
  Prediction_cells_tsetse_distance_cattle_and_burden.csv=c("cell_id","x3857","y3857","longitude","latitude","Country","iso_a3","Mean_Prevalence","Cattle_total","Infected_total","Buffer_region",zones),
  Uncertainty_only_primary_masks_25km.csv=c("cell_id","Posterior_CrI_Width","Posterior_Logit_CrI_Width","Distance_to_tsetse_belt_km_Centre","Tsetse_Presence_Centre"),
  Uncertainty_only_mask_thresholds.csv=c("Metric_id","Threshold_source","Anchor_region","Quantile","Threshold_value"))
# Read as text to avoid unnecessary rounding, especially at filter cutoffs.
frames <- list()
for (f in names(expected)) {
  path <- file.path(audit_dir,f)
  if (!file.exists(path)) {
    if (f==tail(names(expected),1)) next
    stop("Missing input: ",path)
  }
  d <- read.csv(path,check.names=FALSE,colClasses="character",na.strings=NULL)
  if (anyDuplicated(names(d))) stop("Duplicate headers in ",f)
  absent <- setdiff(expected[[f]],names(d)); if(length(absent)) stop(f," missing columns: ",paste(absent,collapse=", "))
  frames[[f]] <- d[,expected[[f]],drop=FALSE]
}
# Stage files before replacing current data.
tmp <- tempfile("aat-web-",tmpdir=dest); dir.create(tmp)
tryCatch({
  for (f in names(frames)) {
    path <- file.path(tmp,f); write.csv(frames[[f]],path,row.names=FALSE,na="NA",fileEncoding="UTF-8")
    if(file.info(path)$size>=100*1024^2) stop(f," is at least 100 MiB; too large for regular GitHub upload.")
    cat(sprintf("%s: %s rows, %.2f MiB\n",f,nrow(frames[[f]]),file.info(path)$size/1024^2))
  }
  for(f in names(frames)) if(!file.copy(file.path(tmp,f),file.path(dest,f),overwrite=TRUE)) stop("Copy failed: ",f)
  optional <- tail(names(expected),1); if(!optional %in% names(frames)) unlink(file.path(dest,optional))
},finally=unlink(tmp,recursive=TRUE))
cat("Snapshot ready in ",dest,". Validate locally before uploading.\n",sep="")
