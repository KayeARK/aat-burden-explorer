# AAT Burden & Reporting Domain Explorer — browser-ready deployment

This folder contains the Shiny website. You do not need to rewrite it in HTML or
JavaScript: hosted Shiny apps already run in a browser, and collaborators do not
need to install R. The website evaluates the geographical and uncertainty
reporting scenarios on precomputed data. **It does not refit INLA.**

## What gets published

- `app.R`: the interactive website (map, controls, country tables, exports)
- `data/Prediction_cells_tsetse_distance_cattle_and_burden.csv`: required
- `data/Uncertainty_only_primary_masks_25km.csv`: required
- `data/Uncertainty_only_mask_thresholds.csv`: optional (95th percentile helper)

The `data/` files are **not included** in the shared ZIP, because they were not
available with the audit code. The person publishing the app must run the
preparation step below on the computer with the actual audit outputs.

No INLA `.rds` models, source cattle/climate rasters, survey records, or files
from the 1,000 adjustment iterations are required.

## Step 1 — put the folder in the project

Unzip `AAT_Burden_Explorer_Web.zip` into the root of the existing project, next
to the `Code_Nagana/` folder. The root should then contain:

```
Code_Nagana/
Data/
AAT_Burden_Explorer_Web/
  app.R
  prepare_data.R
  deploy_connect_cloud.R
  data/
```

The audit should already have produced the CSV files in:

`Code_Nagana/Results/Tsetse_belt_audit/`

## Step 2 — create the website's own data snapshot

Run this from the **project root** in RStudio:

```r
source("AAT_Burden_Explorer_Web/prepare_data.R")
```

This copies only the required aggregate cell-level CSVs into the website's
`data/` folder. If the audit output is elsewhere, before running set
`Sys.setenv(AAT_AUDIT_DIR="/absolute/path/to/Tsetse_belt_audit")`.

**Check data-sharing permissions before proceeding.** A public website allows
visitors to inspect and download the modelled 25 km cell estimates and country
results. Hosting services also hold copies of the uploaded input CSVs.

## Step 3 — run locally first

Install packages (only once):

```r
install.packages(c("shiny", "bslib", "leaflet", "terra", "dplyr",
                   "ggplot2", "DT", "scales", "rsconnect"))
```

Then, from project root:

```r
shiny::runApp("AAT_Burden_Explorer_Web", launch.browser = TRUE)
```

Test selecting a country; +50, +100, unrestricted; applying and disabling the
uncertainty threshold; and downloading a country CSV.

## Step 4 — publish to Posit Connect Cloud

Visit https://connect.posit.cloud/ and create an account if needed. To authorize
RStudio to publish to the account, run once:

```r
rsconnect::connectCloudUser()
```

Choose one of the following modes **deliberately**. Free and Basic plans
only support public access. Enhanced and higher support private-link sharing;
Advanced and Enterprise can invite named individuals:

```r
# Access-restricted collaborators (needs a plan with private content):
Sys.setenv(AAT_WEB_VISIBILITY = "private")

# OR publicly viewable app, only if your data-sharing rules permit:
Sys.setenv(AAT_WEB_VISIBILITY = "public")
```

Then:

```r
source("AAT_Burden_Explorer_Web/deploy_connect_cloud.R")
```

RStudio will build and upload the app and the three precomputed data CSVs.
Connect Cloud provides the final URL after a successful publication; share
that URL with collaborators. For a private app, use **Share → Private link** on an Enhanced (or
higher) plan; collaborators with that link can view without an account. On
Advanced/Enterprise plans you can instead invite named individuals, who must
log in and may require viewer seats.

You may also publish with RStudio's **Publish** button on `app.R`; include the
`data/` files in the upload and choose the appropriate sharing permissions.

## Revising the website or updating results

To update the included data, rerun `prepare_data.R` after regenerating the audit
CSVs, and redeploy using `deploy_connect_cloud.R`. No INLA fit is required by
the app. Visitors cannot modify the underlying results; controls are
session-specific and can export their chosen scenario.

## Important scientific interpretation

- Default: mapped tsetse belt +50 km, without uncertainty exclusions.
- Cells omitted by a rule are `not reported`, *not* assumed uninfected.
- Tsetse buffer burden uses **fractional cattle allocation** by zone; the map
  status uses cell centres for display only.
- A posterior 95% interval width threshold is a model-uncertainty filtering
  rule; it does not demonstrate out-of-sample accuracy.
- Summary burden values are sums of posterior means, not aggregate credible
  intervals. Joint posterior field draws would be needed for those.
- The country attribution inherits the original audit's cell-centre method.
- The website uses whichever prevalence model was used to create the audit.
  Confirm its provenance before sharing scientific conclusions.

## Hosting alternatives

- Posit Connect Cloud: recommended, direct RStudio publishing and sharing.
- University-operated Posit Connect / Shiny Server: useful if Warwick has an
  internally managed platform or external data hosting is restricted.
- A fully static HTML/JavaScript site is possible, but requires rewriting the
  Shiny interactions and data computations. It is unnecessary for a small group
  of collaborators unless a no-server deployment is a strong requirement.

The site cannot be published without access to your hosting account and source
CSV outputs. The ZIP is **deployment-ready in structure**, but has not been
end-to-end tested on the Posit host.
