# AAT burden-domain explorer
# Run from the project root with:
#   shiny::runApp("AAT_Burden_Explorer")
# or from any location inside the project after placing this folder there.
# Uses outputs from the TSETSE-BELT DATA-SUPPORT AND BURDEN AUDIT.
# Does NOT refit INLA. Values are posterior MEAN burden estimates, not
# posterior credible intervals for country/continental totals.

required_packages <- c("shiny", "bslib", "leaflet", "terra", "dplyr", "ggplot2", "DT", "scales")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop("Install required R packages first: install.packages(c(",
       paste(sprintf('"%s"', missing_packages), collapse = ", "), "))")
}
suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(leaflet)
  library(terra)
  library(dplyr)
  library(ggplot2)
  library(DT)
  library(scales)
})

# ---------------------------------------------------------------
# Locate source outputs. Shiny changes the working directory to the
# app folder, so search upwards rather than assuming the project root.
# You can also set AAT_AUDIT_DIR to the absolute output directory.
# ---------------------------------------------------------------
find_audit_directory <- function() {
  # A hosted app cannot see the author's computer. The deployment includes
  # only the three precomputed audit CSVs in its own data/ directory.
  bundled <- file.path(getwd(), "data")
  expected <- "Prediction_cells_tsetse_distance_cattle_and_burden.csv"
  if (file.exists(file.path(bundled, expected))) {
    return(normalizePath(bundled, winslash = "/", mustWork = TRUE))
  }
  custom <- Sys.getenv("AAT_AUDIT_DIR", "")
  if (nzchar(custom)) {
    if (!dir.exists(custom)) stop("AAT_AUDIT_DIR does not exist: ", custom)
    return(normalizePath(custom, winslash = "/"))
  }
  here <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  parents <- here
  for (i in seq_len(8)) {
    parent <- dirname(tail(parents, 1))
    if (identical(parent, tail(parents, 1))) break
    parents <- c(parents, parent)
  }
  candidates <- unique(c(
    file.path(parents, "Code_Nagana", "Results", "Tsetse_belt_audit"),
    file.path(parents, "Results", "Tsetse_belt_audit"),
    file.path(parents, "Tsetse_belt_audit")
  ))
  valid <- candidates[file.exists(file.path(candidates, expected))]
  if (!length(valid)) {
    stop(paste0(
      "Could not find the bundled audit data. Run prepare_data.R from the project ",
      "root before deploying. Expected ", expected,
      " in this app's data/ folder; alternatively set AAT_AUDIT_DIR locally."
    ))
  }
  normalizePath(valid[1], winslash = "/")
}

audit_dir <- find_audit_directory()
main_path <- file.path(audit_dir, "Prediction_cells_tsetse_distance_cattle_and_burden.csv")
unc_path <- file.path(audit_dir, "Uncertainty_only_primary_masks_25km.csv")
anchor_path <- file.path(audit_dir, "Uncertainty_only_mask_thresholds.csv")
if (!file.exists(unc_path)) {
  stop("Missing uncertainty data: ", unc_path,
       ". Re-run the uncertainty section of the tsetse audit first.")
}
read_table <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
cell <- read_table(main_path)
unc <- read_table(unc_path)
required_main <- c("cell_id", "x3857", "y3857", "longitude", "latitude",
                   "Country", "iso_a3", "Mean_Prevalence", "Cattle_total", "Infected_total")
buffer_dist <- c(seq(0, 25, by = 5), 50, 100, 200, Inf)
lo <- head(buffer_dist, -1)
hi <- tail(buffer_dist, -1)
annulus_keys <- ifelse(is.infinite(hi), paste0("outside_gt_", lo), paste0("outside_", lo, "_", hi))
zone_keys <- c("inside", annulus_keys, "unknown")
region_keys <- c("Sahel", "Southern_Africa", "Other")
region_labels <- c("Sahel proxy", "Southern Africa proxy", "Other regions")
region_colors <- c("#D59A43", "#5186B0", "#A5ACA8")
required_main <- c(required_main, "Buffer_region")
zone_cols <- paste0("Cattle_", zone_keys)
required_unc <- c("cell_id", "Posterior_CrI_Width", "Posterior_Logit_CrI_Width",
                  "Distance_to_tsetse_belt_km_Centre", "Tsetse_Presence_Centre")
missing_main <- setdiff(c(required_main, zone_cols), names(cell))
missing_unc <- setdiff(required_unc, names(unc))
if (length(missing_main)) stop("Missing columns in cell audit file: ", paste(missing_main, collapse = ", "))
if (length(missing_unc)) stop("Missing columns in uncertainty audit file: ", paste(missing_unc, collapse = ", "))
if (anyDuplicated(cell$cell_id) || anyDuplicated(unc$cell_id)) {
  stop("Duplicate cell_id values detected. Cannot merge the two output tables safely.")
}
lookup <- match(cell$cell_id, unc$cell_id)
if (anyNA(lookup)) {
  stop("The uncertainty output is missing ", sum(is.na(lookup)),
       " cells from the main audit output. Regenerate matching audit outputs.")
}
for (name in setdiff(required_unc, "cell_id")) cell[[name]] <- unc[[name]][lookup]

number_cols <- c("x3857", "y3857", "longitude", "latitude", "Mean_Prevalence",
                 "Cattle_total", "Infected_total", zone_cols, setdiff(required_unc, "cell_id"))
for (nm in number_cols) cell[[nm]] <- suppressWarnings(as.numeric(cell[[nm]]))
if (any(!is.finite(cell$Mean_Prevalence) | cell$Mean_Prevalence < 0 | cell$Mean_Prevalence > 1)) {
  stop("Main audit contains invalid or missing Mean_Prevalence values.")
}
if (any(!is.finite(cell$x3857) | !is.finite(cell$y3857))) stop("Invalid 25-km grid coordinates.")
if (any(!is.finite(cell$longitude) | !is.finite(cell$latitude))) stop("Invalid longitude/latitude.")

# Restrict to country-assigned cells and exclude Madagascar from ALL app outputs.
# Filter before country menus, burden totals, plotting, sensitivity and exports.
cell <- cell[!is.na(cell$Country) & nzchar(cell$Country), , drop = FALSE]
cell <- cell[!(toupper(trimws(as.character(cell$iso_a3))) == "MDG" |
               tolower(trimws(as.character(cell$Country))) == "madagascar"),
             , drop = FALSE]
if (!nrow(cell)) stop("No eligible country-assigned cells after excluding Madagascar.")
if (any(!cell$Buffer_region %in% region_keys)) stop("Invalid Buffer_region; rerun the regional audit.")
if (any(!is.finite(cell$Cattle_total) & rowSums(is.finite(as.matrix(cell[zone_cols]))) > 0)) {
  stop("Some country cells have unknown total cattle but zone-specific counts. Investigate GLW coverage.")
}
# The source audit uses na.rm=TRUE for no-data cattle cells. Do not silently
# replace partial coverage: if cattle total is positive, all zone fractions
# must be available and reconstruct the total within 0.1%.
positive <- is.finite(cell$Cattle_total) & cell$Cattle_total > 0
z <- as.matrix(cell[zone_cols]); storage.mode(z) <- "double"
if (any(!is.finite(z[positive, , drop = FALSE]))) {
  stop("Positive-cattle cells contain NA/nonfinite tsetse-zone counts; cannot safely recompute totals.")
}
if (any(z[is.finite(z)] < -1e-6)) stop("Negative zone-specific cattle counts found.")
z[!is.finite(z)] <- 0
cell[zone_cols] <- as.data.frame(z)
cell$Cattle_total[!is.finite(cell$Cattle_total)] <- 0
cell$Infected_total[!is.finite(cell$Infected_total)] <- 0
relative_error <- abs(rowSums(z) - cell$Cattle_total) / pmax(cell$Cattle_total, 1)
if (any(relative_error[positive] > 0.001)) {
  stop("The zonal cattle counts do not reconstruct Cattle_total in some cells. ",
       "Check the audit CSVs and alignment before using this app.")
}
# Ensure exact consistency between the display's unrestricted burden
# and the numerator calculated from the prevalence map.
if (any(abs(cell$Infected_total - cell$Cattle_total * cell$Mean_Prevalence) >
        pmax(1, cell$Infected_total) * 1e-5)) {
  stop("Infected_total does not match Mean_Prevalence x Cattle_total.")
}

anchors <- if (file.exists(anchor_path)) read_table(anchor_path) else NULL
get_anchor <- function(metric, quantile = 0.95) {
  if (is.null(anchors)) return(NA_real_)
  need <- c("Metric_id", "Threshold_source", "Anchor_region", "Quantile", "Threshold_value")
  if (!all(need %in% names(anchors))) return(NA_real_)
  a <- anchors[anchors$Metric_id == metric &
               anchors$Threshold_source == "Unique Atlas sampling locations" &
               anchors$Anchor_region == "Africa" &
               abs(as.numeric(anchors$Quantile) - quantile) < 1e-9, , drop = FALSE]
  if (nrow(a) != 1L) return(NA_real_)
  as.numeric(a$Threshold_value[1])
}
anchor_prob <- get_anchor("Probability_CrI_width")
anchor_logit <- get_anchor("Logit_CrI_width")

buffer_labels <- c("Mapped tsetse only", paste0("Belt + ", buffer_dist[is.finite(buffer_dist) & buffer_dist > 0], " km"), "Unrestricted")
buffer_choices <- setNames(as.character(seq_along(buffer_dist)), buffer_labels)
selected_zone_keys <- function(stage) {
  km <- buffer_dist[as.integer(stage)]
  if (length(km) != 1L || is.na(km)) stop("Unknown buffer stage")
  if (is.infinite(km)) return(zone_keys)
  c("inside", annulus_keys[hi <= km])
}

# This reproduces the audit's zone-fraction burden calculation. The
# uncertainty filter operates on the ENTIRE 25-km prevalence cell, not on
# individual GLW pixels; this distinction is stated in the interface.
make_scenario <- function(dat, stage, apply_unc, metric, threshold, regional_stages = NULL) {
  if (is.null(regional_stages)) regional_stages <- setNames(rep(stage, 3), region_keys)
  stages <- as.integer(regional_stages[dat$Buffer_region])
  if (anyNA(stages)) stop("Missing region-specific buffer stage")
  geo_cattle <- numeric(nrow(dat))
  for (k in unique(stages)) {
    idx <- which(stages == k)
    zones <- paste0("Cattle_", selected_zone_keys(k))
    geo_cattle[idx] <- if (is.infinite(buffer_dist[k])) dat$Cattle_total[idx] else
      rowSums(as.matrix(dat[idx, zones, drop = FALSE]))
  }
  dat$Selected_buffer_km <- buffer_dist[stages]
  all_cattle <- dat$Cattle_total
  p <- dat$Mean_Prevalence
  u <- if (metric == "prob") dat$Posterior_CrI_Width * 100 else dat$Posterior_Logit_CrI_Width
  valid_unc <- is.finite(u)
  pass_unc <- if (isTRUE(apply_unc)) valid_unc & u <= threshold else rep(TRUE, nrow(dat))
  retained_cattle <- geo_cattle * as.numeric(pass_unc)
  geo_infected <- geo_cattle * p
  retained_infected <- retained_cattle * p
  dat$Geographic_cattle <- geo_cattle
  dat$Geographic_infected <- geo_infected
  dat$Retained_cattle <- retained_cattle
  dat$Retained_infected <- retained_infected
  dat$Uncertainty_value <- u
  dat$Uncertainty_pass <- pass_unc
  dat$Uncertainty_missing <- !valid_unc
  dat$Excluded_cattle_geography <- pmax(0, all_cattle - geo_cattle)
  dat$Excluded_cattle_uncertainty <- pmax(0, geo_cattle - retained_cattle)
  dat$Excluded_burden_geography <- pmax(0, dat$Infected_total - geo_infected)
  dat$Excluded_burden_uncertainty <- pmax(0, geo_infected - retained_infected)
  # Centre-based categories are visual ONLY: burden uses fractional zone counts.
  # Cells with unknown tsetse classification are displayed as OUTSIDE the
  # selected finite buffer, rather than with a separate "unknown" map class.
  # The underlying Cattle_unknown fraction cannot be assigned to a specific
  # distance band from the saved CSV; it is included only when unrestricted.
  center_unknown <- !is.finite(dat$Tsetse_Presence_Centre) |
                    !is.finite(dat$Distance_to_tsetse_belt_km_Centre)
  center_inside <- is.finite(dat$Tsetse_Presence_Centre) &
                   dat$Tsetse_Presence_Centre > 0.5
  center_geog <- is.infinite(dat$Selected_buffer_km) | center_inside |
    ((!center_unknown) & dat$Selected_buffer_km > 0 &
      dat$Distance_to_tsetse_belt_km_Centre <= dat$Selected_buffer_km)
  # Avoid NA results from missing centre distances when evaluating &.
  center_geog[is.na(center_geog)] <- FALSE
  status <- ifelse(center_geog, 1L, 3L)
  if (isTRUE(apply_unc)) {
    status[center_geog & valid_unc & !pass_unc] <- 2L
    status[center_geog & !valid_unc] <- 4L
  }
  dat$Map_status_code <- status
  dat$Map_reported_prevalence <- ifelse(center_geog & pass_unc, p, NA_real_)
  dat
}

summarise_burden <- function(dat) {
  sum_num <- function(x) sum(x, na.rm = TRUE)
  original_cattle <- sum_num(dat$Cattle_total)
  original_burden <- sum_num(dat$Infected_total)
  geo_cattle <- sum_num(dat$Geographic_cattle)
  geo_burden <- sum_num(dat$Geographic_infected)
  retained_cattle <- sum_num(dat$Retained_cattle)
  retained_burden <- sum_num(dat$Retained_infected)
  data.frame(
    All_cattle = original_cattle,
    Unrestricted_burden = original_burden,
    Geographic_cattle = geo_cattle,
    Geographic_burden = geo_burden,
    Retained_cattle = retained_cattle,
    Retained_burden = retained_burden,
    Cattle_share = if (original_cattle > 0) 100 * retained_cattle / original_cattle else NA_real_,
    Burden_share = if (original_burden > 0) 100 * retained_burden / original_burden else NA_real_,
    Geographic_exclusion_burden = original_burden - geo_burden,
    Uncertainty_exclusion_burden = geo_burden - retained_burden,
    Missing_uncertainty_cells = sum(dat$Geographic_cattle > 0 & dat$Uncertainty_missing),
    stringsAsFactors = FALSE
  )
}

# Properly identify country choices without collapsing distinct names.
country_choices <- unique(cell[, c("iso_a3", "Country")])
country_choices <- country_choices[order(country_choices$Country), , drop = FALSE]
country_choices <- country_choices[!is.na(country_choices$iso_a3) & nzchar(country_choices$iso_a3), , drop = FALSE]
country_option_list <- c("Africa (all countries)" = "ALL",
                         setNames(as.character(country_choices$iso_a3), country_choices$Country))

fmt_count <- function(x) if (length(x) && is.finite(x)) format(round(x), big.mark=",", scientific=FALSE, trim=TRUE) else "—"
fmt_million <- function(x) if (length(x) && is.finite(x)) sprintf("%.2f M", x / 1e6) else "—"
fmt_percent <- function(x) if (length(x) && is.finite(x)) sprintf("%.1f%%", x) else "—"

status_colors <- c("#1d998b", "#f4aa54", "#c7ccd1", "#d95f58")
status_labels <- c("Retained (centre)", "High uncertainty", "Outside selected belt buffer",
                   "Uncertainty unavailable")

app_css <- "
body { background: #f4f6f8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
.app-heading { padding: 22px 10px 18px 10px; }
.app-heading h1 { font-size: 29px; font-weight: 760; color: #17343e; margin: 0 0 5px 0; }
.app-heading p { color:#60747e; margin-bottom:0; }
.controls { background:white; padding:21px; border-radius:14px; border:1px solid #e2e7eb;
            box-shadow: 0 2px 8px #17343e08; margin-bottom:18px; }
.controls h3 { font-size:15px; font-weight:750; text-transform:uppercase; letter-spacing:.04em; color:#3f5962; margin-top:0; }
.kpi { background:white; border:1px solid #e2e7eb; border-radius:13px; padding:17px 18px; margin-bottom:16px; min-height:116px; }
.kpi .kpi-label { color:#687d86; font-size:12px; font-weight:650; text-transform:uppercase; letter-spacing:.04em; }
.kpi .kpi-value { color:#17343e; font-size:28px; font-weight:760; margin-top:7px; }
.kpi .kpi-foot { color:#70848b; font-size:12px; margin-top:1px; }
.content-card { background:white; border:1px solid #e2e7eb; border-radius:13px; padding:15px; margin:10px 0 17px; }
.helper { font-size:12px; line-height:1.5; color:#687d86; margin: 8px 0 14px; }
.nav-tabs { font-weight:600; }
.btn-primary { background-color:#1d7e83; border-color:#1d7e83; }
.shiny-input-container { width: 100%; }
.scenario-tag { background:#e8f3f0; color:#166960; border-radius:8px; padding:9px 12px; font-weight:700; margin:10px 0; }
.plot-note { color:#71828a; font-size:12px; }
"

ui <- fluidPage(
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly", primary = "#1d7e83"),
  tags$head(tags$style(HTML(app_css))),
  div(class="app-heading",
      tags$h1("AAT · Burden & reporting domains"),
      tags$p("Explore geographical support, uncertainty and modelled infected-cattle burden. No model refitting required.")),
  fluidRow(
    column(width = 3,
      div(class = "controls",
        tags$h3("Geographical domain"),
        selectInput("country", "Region", choices = country_option_list, selected = "ALL"),
        radioButtons("buffer_mode", "Buffer mode", choices = c("Uniform" = "uniform", "Regional" = "regional"), selected = "uniform", inline = TRUE),
        conditionalPanel("input.buffer_mode == 'uniform'",
          selectInput("buffer_stage", "Continental buffer", choices = buffer_choices, selected = as.character(match(50, buffer_dist)))),
        conditionalPanel("input.buffer_mode == 'regional'",
          selectInput("sahel_stage", "Sahel proxy", choices = buffer_choices, selected = as.character(match(50, buffer_dist))),
          selectInput("south_stage", "Southern Africa proxy", choices = buffer_choices, selected = as.character(match(10, buffer_dist))),
          selectInput("other_stage", "Other regions (including East Africa)", choices = buffer_choices, selected = as.character(match(50, buffer_dist)))),
        uiOutput("buffer_text"),
        tags$p(class="helper", "The 0–25 km range is resolved in 5 km steps, followed by 50, 100 and 200 km. Regional definitions are provisional expert-review proxies. View the buffer regions map. Missing tsetse classifications are outside finite buffers; Madagascar is excluded."),
        tags$hr(),
        tags$h3("Uncertainty filter"),
        checkboxInput("apply_unc", "Exclude cells above uncertainty threshold", value = FALSE),
        selectInput("unc_metric", "Measure", choices = c(
          "95% CrI width (percentage points)" = "prob",
          "95% CrI width (logit units)" = "logit"), selected = "logit"),
        conditionalPanel("input.unc_metric == 'prob'",
          sliderInput("prob_width_pp", "Maximum 95% CrI width", min = 1, max = 100, value = 20, step = 1, post = " pp")),
        conditionalPanel("input.unc_metric == 'logit'",
          sliderInput("max_logit_width", "Maximum 95% logit CrI width", min = 0.1, max = 12, value = 2.0, step = 0.1)),
        actionButton("anchor", "Use observed-site 95th percentile", width="100%"),
        uiOutput("anchor_note"),
        tags$p(class="helper", "This filter is OFF by default. It hides modelled burden from high-uncertainty cells; it does not assert absence of infection."),
        tags$hr(),
        tags$h3("Display"),
        selectInput("map_mode", "Map layer", choices=c(
          "Reporting-domain status"="status",
          "Retained prevalence"="prevalence",
          "Posterior uncertainty"="uncertainty", "Provisional buffer regions"="regions"), selected="status"),
        conditionalPanel("input.map_mode == 'prevalence'",
          radioButtons("prevalence_scale", "Prevalence colour scale",
            choices = c("Fixed upper limit" = "fixed",
                        "Automatic (highest displayed prevalence)" = "auto"),
            selected = "fixed"),
          conditionalPanel("input.prevalence_scale == 'fixed'",
            sliderInput("prevalence_max_pct", "Upper colour limit", min = 5,
                        max = 100, value = 50, step = 5, post = "%")),
          tags$p(class="helper", "Values above a fixed limit use the darkest red, not a missing colour. Automatic scaling uses the highest retained prevalence in the selected region, rounded up to a whole percent. For comparisons between countries, keep the fixed scale unchanged."),
          uiOutput("prevalence_scale_note")
        ),
        sliderInput("map_opacity", "Map opacity", min=0.3, max=1, value=0.85, step=0.05)
      )
    ),
    column(width = 9,
      fluidRow(
        column(3, div(class="kpi", div(class="kpi-label", "Retained burden"), div(class="kpi-value", textOutput("kpi_burden", inline=TRUE)), div(class="kpi-foot", "Posterior mean · infected cattle"))),
        column(3, div(class="kpi", div(class="kpi-label", "Retained cattle"), div(class="kpi-value", textOutput("kpi_cattle", inline=TRUE)), div(class="kpi-foot", "2020 cattle distribution"))),
        column(3, div(class="kpi", div(class="kpi-label", "Burden retained"), div(class="kpi-value", textOutput("kpi_bshare", inline=TRUE)), div(class="kpi-foot", "Of unrestricted scenario"))),
        column(3, div(class="kpi", div(class="kpi-label", "Cattle retained"), div(class="kpi-value", textOutput("kpi_cshare", inline=TRUE)), div(class="kpi-foot", "Of unrestricted scenario")))
      ),
      tabsetPanel(id="tab",
        tabPanel("Map",
          div(class="content-card",
            uiOutput("scenario_caption"),
            leafletOutput("aat_map", height = "610px"),
            tags$p(class="plot-note", "Map classes use prediction-cell centres. Burden totals use fractional tsetse-zone allocations from the original cattle raster, so boundary-cell totals need not match the map pixel classification exactly."),
            uiOutput("clicked_cell")
          )
        ),
        tabPanel("Country comparison",
          div(class="content-card", tags$h4("Burden by country"),
              DTOutput("country_table"),
              tags$p(class="helper", "Burden is the sum of cell-level posterior means multiplied by cattle counts. These are not credible intervals for aggregate infected cattle.")),
          div(class="content-card", plotOutput("country_chart", height="500px"))
        ),
        tabPanel("Sensitivity",
          div(class="content-card", tags$h4("Sensitivity to reporting-domain width"),
              plotOutput("buffer_plot", height = "340px"),
              tags$p(class="helper", "This is a uniform-buffer sweep for comparison, even in regional mode. The uncertainty choice above is held fixed. Unrestricted includes areas with missing tsetse classification; Madagascar is excluded.")),
          div(class="content-card", tags$h4("Sensitivity to uncertainty threshold"),
              plotOutput("uncertainty_plot", height="330px"),
              tags$p(class="helper", "The geographical domain is held fixed. Percentages are relative to the original unrestricted burden or cattle counts in the selected region."))
        ),
        tabPanel("Methods & checks",
          div(class="content-card",
            tags$h4("Interpretation"),
            tags$p("The dashboard computes modelled infected cattle retained under a reporting rule. Excluded cattle are not assumed disease-free. The main definition is mapped tsetse +50 km, with uncertainty filtering OFF."),
            tags$p("A tsetse buffer is a geographical reporting domain, not the complete extent of all animal trypanosomiasis transmission. AAT can persist outside mapped tsetse via movement or mechanical transmission."),
            tags$p("The '95% CrI width' refers to the width of a posterior interval for latent prevalence, not a 95% predictive accuracy guarantee. Probability-width and logit-width filters are not interchangeable."),
            tags$p("The prevalence surface, tsetse classification and 2020 cattle distribution are treated as fixed input layers. Only the spatial reporting domain and optional uncertainty criterion change."),
            tags$p("The prevalence colour scale is display-only. The default is 0–50%; values above a fixed colour limit are shown in the darkest red. Automatic scaling uses the highest retained prevalence in the selected region, rounded up to a whole percent. The map uses nearest-neighbour display for prevalence cells; all burden calculations and clicked-cell prevalence values use the original unmodified predictions."),
            tags$p("Madagascar is excluded from all country and continental results. Cells with missing tsetse classification are displayed as outside finite buffers; their unallocated cattle fractions remain included only in unrestricted totals. This is a reporting convention, not evidence of tsetse absence."),
            tags$p("Regional membership is assigned by the 25-km prediction-cell centre, using configurable country and latitude rules in the audit script. This is a provisional classification, not a validated epidemiological boundary. Distance-zone cattle allocations remain fractional."),
            tags$p("Public research preview: derived maps and summaries are visible to anyone with access. No direct CSV download controls are provided; the displayed data are not confidential."),
            tags$p("No aggregate posterior credible intervals are calculated; coherent joint posterior prevalence draws would be required for that."),
            tags$h4("Input file checks"),
            verbatimTextOutput("checks"),
            tags$h4("Provenance"),
            verbatimTextOutput("provenance")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  chosen_threshold <- reactive({
    if (identical(input$unc_metric, "prob")) input$prob_width_pp else input$max_logit_width
  })
  chosen_metric_label <- reactive({
    if (identical(input$unc_metric, "prob")) "95% probability-scale CrI width" else "95% logit-scale CrI width"
  })
  regional_stages <- reactive({
    if (!identical(input$buffer_mode, "regional")) return(NULL)
    req(input$sahel_stage, input$south_stage, input$other_stage)
    setNames(as.integer(c(input$sahel_stage, input$south_stage, input$other_stage)), region_keys)
  })
  scenario_label <- reactive({
    stages <- regional_stages()
    if (is.null(stages)) return(buffer_labels[as.integer(input$buffer_stage)])
    paste(paste(region_labels, buffer_labels[stages], sep = ": "), collapse = " · ")
  })
  output$buffer_text <- renderUI({
    div(class="scenario-tag", scenario_label())
  })
  output$anchor_note <- renderUI({
    a <- if (identical(input$unc_metric, "prob")) anchor_prob else anchor_logit
    if (is.finite(a)) {
      tags$p(class="helper", paste0("Observed Atlas sites · 95th percentile = ",
         if (identical(input$unc_metric, "prob")) sprintf("%.1f pp", a * 100) else sprintf("%.2f logit units", a),
         ". This is a descriptive benchmark, not a validated performance threshold."))
    } else tags$p(class="helper", "No observed-site threshold found in the optional threshold CSV.")
  })
  observeEvent(input$anchor, {
    a <- if (identical(input$unc_metric, "prob")) anchor_prob else anchor_logit
    if (!is.finite(a)) {
      showNotification("No 95th-percentile observed-site threshold found in the audit outputs.", type="warning")
      return()
    }
    if (identical(input$unc_metric, "prob")) {
      updateSliderInput(session, "prob_width_pp", value = min(100, max(1, round(a * 100, 1))))
    } else {
      updateSliderInput(session, "max_logit_width", value = min(12, max(0.1, round(a, 1))))
    }
    updateCheckboxInput(session, "apply_unc", value = TRUE)
  })

  # All-country reactive table feeds the map, country table and plots.
  scenario_all <- reactive({
    make_scenario(cell, input$buffer_stage, input$apply_unc,
                  input$unc_metric, chosen_threshold(), regional_stages())
  })
  scenario_region <- reactive({
    dat <- scenario_all()
    if (identical(input$country, "ALL")) dat else dat[dat$iso_a3 == input$country, , drop=FALSE]
  })
  summary_region <- reactive(summarise_burden(scenario_region()))
  output$kpi_burden <- renderText(fmt_million(summary_region()$Retained_burden))
  output$kpi_cattle <- renderText(fmt_million(summary_region()$Retained_cattle))
  output$kpi_bshare <- renderText(fmt_percent(summary_region()$Burden_share))
  output$kpi_cshare <- renderText(fmt_percent(summary_region()$Cattle_share))

  output$scenario_caption <- renderUI({
    scope <- if (input$country == "ALL") "Africa" else {
      nm <- country_choices$Country[match(input$country, country_choices$iso_a3)]
      if (length(nm) && !is.na(nm)) nm else input$country
    }
    div(class="scenario-tag", strong(scope), " · ", scenario_label(), " · ",
        if (input$apply_unc) paste0("Uncertainty cap: ", chosen_threshold(),
                                   if (input$unc_metric=="prob") " pp" else " logit units") else "No uncertainty exclusion")
  })

  # Colour settings affect only the map, not the prevalence or burden data.
  prevalence_colour_cap <- reactive({
    req(input$prevalence_scale)
    if (identical(input$prevalence_scale, "auto")) {
      p <- scenario_region()$Map_reported_prevalence
      p <- p[is.finite(p)]
      # A positive fallback keeps the palette well-defined for empty/zero maps.
      if (!length(p)) return(0.50)
      return(min(1, max(0.01, ceiling(max(p) * 100) / 100)))
    }
    req(input$prevalence_max_pct)
    min(1, max(0.05, as.numeric(input$prevalence_max_pct) / 100))
  })

  output$prevalence_scale_note <- renderUI({
    cap <- prevalence_colour_cap()
    p <- scenario_region()$Map_reported_prevalence
    p <- p[is.finite(p)]
    if (!length(p)) return(tags$p(class="helper", "No retained prevalence cells in this scenario."))
    tags$p(class="helper", sprintf(
      "Colour scale: 0–%.0f%%. Highest displayed prevalence: %.1f%%. %s",
      100 * cap, 100 * max(p),
      if (any(p > cap)) "Values above the colour limit are saturated." else "All displayed values are within the colour scale."))
  })

  map_raster <- reactive({
    dat <- scenario_region()
    if (!nrow(dat)) return(NULL)
    value <- switch(input$map_mode,
      status = as.numeric(dat$Map_status_code),
      prevalence = as.numeric(dat$Map_reported_prevalence),
      uncertainty = as.numeric(dat$Uncertainty_value),
      regions = match(dat$Buffer_region, region_keys))
    xyz <- data.frame(x = dat$x3857, y = dat$y3857, value = value)
    terra::rast(xyz, type = "xyz", crs = "EPSG:3857")
  })

  output$aat_map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas=TRUE)) %>%
      addTiles() %>%
      setView(lng=19, lat=1, zoom=3)
  })

  observeEvent(list(map_raster(), input$map_opacity,
                    if (identical(input$map_mode, "prevalence")) prevalence_colour_cap()), {
    r <- map_raster()
    req(!is.null(r))
    proxy <- leafletProxy("aat_map", session=session) %>%
      clearImages() %>% clearControls()
    if (input$map_mode == "status") {
      pal <- leaflet::colorFactor(palette = status_colors, domain = 1:4, na.color = "#00000000")
      proxy <- proxy %>%
        addRasterImage(r, colors = pal, opacity=input$map_opacity,
                       project=TRUE, method="ngb", maxBytes=25*1024*1024, layerId="layer") %>%
        addLegend(position="bottomright", colors=status_colors, labels=status_labels,
                  title="Reporting status", opacity=1)
    } else if (input$map_mode == "regions") {
      pal <- leaflet::colorFactor(palette = region_colors, domain = 1:3, na.color = "#00000000")
      proxy <- proxy %>%
        addRasterImage(r, colors = pal, opacity = input$map_opacity,
                       project = TRUE, method = "ngb", maxBytes = 25*1024*1024, layerId = "layer") %>%
        addLegend(position = "bottomright", colors = region_colors, labels = region_labels,
                  title = "Provisional buffer regions", opacity = 1)
    } else if (input$map_mode == "prevalence") {
      cap <- prevalence_colour_cap()
      # Saturate at the final colour-mapping step, AFTER raster reprojection.
      # Clamping the raster beforehand is insufficient: floating-point storage
      # can round the cap upward and colorNumeric then treats it as out of range.
      # Keep the original raster and underlying prevalence/burden unchanged.
      pal <- leaflet::colorNumeric(palette="YlOrRd", domain=c(0, cap), na.color="#00000000")
      saturated_pal <- function(x) {
        pal(pmin(pmax(x, 0), cap))  # NA stays NA (transparent).
      }
      ticks <- seq(0, cap, length.out=6)
      legend_labels <- function(type, cuts) {
        labels <- paste0(format(round(100 * cuts, 1), trim=TRUE, scientific=FALSE), "%")
        if (identical(input$prevalence_scale, "fixed") && cap < 1 && length(labels)) {
          labels[length(labels)] <- paste0("\u2265", labels[length(labels)])
        }
        labels
      }
      proxy <- proxy %>%
        addRasterImage(r, colors=saturated_pal, opacity=input$map_opacity,
                       project=TRUE, method="ngb", maxBytes=25*1024*1024, layerId="layer") %>%
        addLegend(position="bottomright", pal=pal, values=c(0, cap), bins=ticks,
                  labFormat=legend_labels, title="Mean prevalence", opacity=1)
    } else {
      vals <- scenario_region()$Uncertainty_value
      finite_vals <- vals[is.finite(vals)]
      max_val <- if (input$unc_metric == "prob") 100 else if (length(finite_vals))
        max(3, ceiling(as.numeric(quantile(finite_vals, .98)))) else 3
      pal <- leaflet::colorNumeric(palette="YlOrRd", domain=c(0,max_val), na.color="#00000000")
      proxy <- proxy %>%
        addRasterImage(r, colors=pal, opacity=input$map_opacity,
                       project=TRUE, method="bilinear", maxBytes=25*1024*1024, layerId="layer") %>%
        addLegend(position="bottomright", pal=pal, values=seq(0,max_val,length.out=5),
                  title=if (input$unc_metric=="prob") "95% CrI width (pp)" else "95% CrI width (logit)")
    }
  }, ignoreInit=FALSE)

  observeEvent(input$country, {
    dat <- scenario_region()
    if (!nrow(dat)) return()
    bounds <- range(dat$longitude, na.rm=TRUE)
    latbounds <- range(dat$latitude, na.rm=TRUE)
    padlng <- max(0.4, diff(bounds)*0.07)
    padlat <- max(0.4, diff(latbounds)*0.07)
    leafletProxy("aat_map") %>% fitBounds(bounds[1]-padlng, latbounds[1]-padlat,
                                          bounds[2]+padlng, latbounds[2]+padlat)
  }, ignoreInit=TRUE)

  # Clicking the map inspects the closest 25km prediction centre, not the
  # source cattle pixels. Cells near country/tsetse boundaries can mix zones.
  clicked <- reactiveVal(NULL)
  observeEvent(input$aat_map_click, {
    point <- input$aat_map_click
    dat <- scenario_region()
    if (!nrow(dat)) return()
    # Local spherical distance approximation sufficient for selecting the
    # nearest display-grid point at the clicked latitude.
    dx <- (dat$longitude - point$lng) * cos(point$lat*pi/180)
    dy <- dat$latitude - point$lat
    k <- which.min(dx*dx + dy*dy)
    clicked(dat$cell_id[k])
  })
  output$clicked_cell <- renderUI({
    id <- clicked()
    if (is.null(id)) return(tags$p(class="helper", "Click the map to inspect the nearest 25-km prediction cell."))
    dat <- scenario_region()
    d <- dat[dat$cell_id == id, , drop = FALSE]
    if (!nrow(d)) return(tags$p(class="helper", "Click the map to inspect a cell in the selected region."))
    tags$div(style="background:#f3f7f7;padding:12px;border-radius:9px;margin-top:9px;",
      tags$strong(paste0("Selected cell · ", d$Country[1], " · ", region_labels[match(d$Buffer_region[1], region_keys)],
                         " · ", if (is.infinite(d$Selected_buffer_km[1])) "Unrestricted" else paste0("+", d$Selected_buffer_km[1], " km"))),
      tags$p(style="margin:7px 0 0;",
        sprintf("Coordinates: %.2f°, %.2f° | Predicted prevalence: %.1f%% | Distance from tsetse at centre: %s km",
                d$longitude[1], d$latitude[1], d$Mean_Prevalence[1]*100,
                if (is.finite(d$Distance_to_tsetse_belt_km_Centre[1]))
                  sprintf("%.1f", d$Distance_to_tsetse_belt_km_Centre[1]) else "unknown")),
      tags$p(style="margin:4px 0 0;",
        paste0("Retained cattle (fractionally allocated): ", fmt_count(d$Retained_cattle[1]),
               " · Retained mean infected cattle: ", fmt_count(d$Retained_infected[1]),
               " · 95% CrI width: ",
               if (is.finite(d$Uncertainty_value[1]))
                 paste(round(d$Uncertainty_value[1],2), if (input$unc_metric=="prob") "pp" else "logit units") else "unknown"))
    )
  })

  country_data <- reactive({
    dat <- scenario_all()
    groups <- split(dat, dat$iso_a3, drop=TRUE)
    out <- lapply(groups, function(x) {
      s <- summarise_burden(x)
      s$Country <- x$Country[1]
      s$iso_a3 <- x$iso_a3[1]
      s
    })
    out <- dplyr::bind_rows(out)
    out[order(-out$Retained_burden), , drop=FALSE]
  })

  output$country_table <- DT::renderDT({
    t <- country_data()
    out <- data.frame(
      Country = t$Country,
      `Retained infected cattle` = round(t$Retained_burden),
      `Unrestricted infected cattle` = round(t$Unrestricted_burden),
      `Burden retained (%)` = round(t$Burden_share,1),
      `Cattle retained (%)` = round(t$Cattle_share,1),
      `Excluded by geography` = round(t$Geographic_exclusion_burden),
      `Excluded by uncertainty` = round(t$Uncertainty_exclusion_burden),
      check.names = FALSE
    )
    DT::datatable(out, rownames=FALSE, filter="top",
                  options=list(pageLength=15, scrollX=TRUE, dom="ftip"))
  })
  output$country_chart <- renderPlot({
    dat <- country_data()
    dat <- head(dat, 20)
    if (!nrow(dat)) return(NULL)
    ggplot(dat, aes(x=reorder(Country,Retained_burden),y=Retained_burden/1e6)) +
      geom_col(fill="#1d998b", width=.7) + coord_flip() +
      scale_y_continuous(labels=scales::label_number(accuracy=.1)) +
      labs(x=NULL, y="Retained modelled infected cattle (millions)",
           title="Countries with the highest retained burden") +
      theme_minimal(base_size=12) + theme(panel.grid.major.y=element_blank())
  })

  output$buffer_plot <- renderPlot({
    src <- if (input$country == "ALL") cell else cell[cell$iso_a3 == input$country, ,drop=FALSE]
    if (!nrow(src)) return(NULL)
    by_buffer <- lapply(seq_along(buffer_labels), function(k) {
      dat <- make_scenario(src,k,input$apply_unc,input$unc_metric,chosen_threshold())
      s <- summarise_burden(dat)
      data.frame(Buffer=factor(buffer_labels[k],levels=buffer_labels),
                 `Cattle`=s$Cattle_share, `Infected cattle`=s$Burden_share,
                 check.names=FALSE)
    })
    plot_dat <- tidyr_fallback_long(dplyr::bind_rows(by_buffer))
    ggplot(plot_dat,aes(x=Buffer,y=Percent,group=Series,color=Series)) +
      geom_line(linewidth=1.05) + geom_point(size=2.6) +
      scale_color_manual(values=c("Cattle"="#4a8099","Infected cattle"="#db7b55")) +
      scale_y_continuous(limits=c(0,100),labels=function(x)paste0(x,"%")) +
      labs(x=NULL,y="Share of unrestricted total retained",color=NULL) +
      theme_minimal(base_size=12) +
      theme(axis.text.x=element_text(angle=45,hjust=1),legend.position="bottom")
  })
  output$uncertainty_plot <- renderPlot({
    src <- if (input$country == "ALL") cell else cell[cell$iso_a3 == input$country, ,drop=FALSE]
    if (!nrow(src)) return(NULL)
    cutoffs <- if (input$unc_metric=="prob") seq(0,100,by=5) else seq(0,12,by=.5)
    out <- lapply(cutoffs, function(cut) {
      s <- summarise_burden(make_scenario(src,input$buffer_stage,TRUE,input$unc_metric,cut,regional_stages()))
      data.frame(Cutoff=cut, Cattle=s$Cattle_share, `Infected cattle`=s$Burden_share,
                 check.names=FALSE)
    })
    plot_dat <- dplyr::bind_rows(out)
    plot_dat <- data.frame(Cutoff=rep(plot_dat$Cutoff,2),
                           Percent=c(plot_dat$Cattle,plot_dat$`Infected cattle`),
                           Series=rep(c("Cattle","Infected cattle"),each=nrow(plot_dat)))
    ggplot(plot_dat,aes(x=Cutoff,y=Percent,color=Series)) +
      geom_line(linewidth=1.05) +
      geom_vline(xintercept=chosen_threshold(),color="#314b55",linetype="dashed") +
      scale_color_manual(values=c("Cattle"="#4a8099","Infected cattle"="#db7b55")) +
      scale_y_continuous(limits=c(0,100),labels=function(x)paste0(x,"%")) +
      labs(x=if (input$unc_metric=="prob") "Maximum 95% interval width (percentage points)" else "Maximum 95% logit interval width",
           y="Share of unrestricted total retained",color=NULL) +
      theme_minimal(base_size=12) + theme(legend.position="bottom")
  })

  output$checks <- renderPrint({
    cat("Loaded cells:", format(nrow(cell),big.mark=","), "\n")
    cat("Unique cell IDs:", length(unique(cell$cell_id)), "\n")
    cat("Maximum zonal cattle reconstruction error:", signif(max(relative_error,na.rm=TRUE),4), "\n")
    cat("Uncertainty unavailable in", sum(!is.finite(cell$Posterior_CrI_Width)),
        "cells on the probability scale and", sum(!is.finite(cell$Posterior_Logit_CrI_Width)),
        "cells on the logit scale.\n")
    cat("Default scenario: uniform belt +50 km, no uncertainty exclusion. Regional starting values: Sahel +50, Southern Africa +10, other +50 km (illustrative).\n")
    cat("Madagascar excluded; missing tsetse classification shown as outside finite buffers.\n")
  })
  output$provenance <- renderPrint({
    cat("Audit directory:\n",audit_dir,"\n\n")
    cat("Source tables:\n",basename(main_path),"\n",basename(unc_path),"\n\n")
    cat("Data model: 25-km prevalence cells, fractional cattle counts by distance zone.\n")
    cat("Country allocation: 25-km cell centre, as in source audit.\n")
    cat("Cattle: GLW 2020, interpreted by source audit as heads/km^2.\n")
    cat("No refitting. No assumption of zero infection outside selected domain.\n")
    cat("Madagascar excluded from all results; unknown tsetse cattle fraction retained only unrestricted.\n")
  })


}

# Small local helper avoids requiring tidyr for the two series in buffer plot.
tidyr_fallback_long <- function(dat) {
  data.frame(Buffer=rep(dat$Buffer,2),
             Percent=c(dat$Cattle,dat$`Infected cattle`),
             Series=rep(c("Cattle","Infected cattle"),each=nrow(dat)))
}

shinyApp(ui, server)
