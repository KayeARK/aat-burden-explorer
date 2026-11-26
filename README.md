# AAT · Burden & Reporting Domain Explorer

Static HTML, CSS and JavaScript version of the R/Shiny AAT Burden Explorer. It runs in the visitor's browser: there is no R, Shiny, INLA, Node.js, database or server-side compute on the hosting service. The website has no third-party JavaScript dependencies, analytics or live tile requests. All links and data paths are relative, so a GitHub Pages project URL works without changes.

## 1. Add the real audit output files

**The research CSVs are not included.** This package intentionally contains no invented predictions, fitted models, raw surveys or unpublished results. The bundled basemap is public-domain Natural Earth 1:110m country geometry. Before publishing, confirm that the derived 25-km cell-level results are approved for public release. Even without a download button, a public static website makes its CSVs accessible to visitors. A private GitHub repository is not a substitute for access control on a public Pages site.

The easiest route is to copy the following existing files from your previous `AAT_Burden_Explorer_Web/data/` into this package's `data/` directory:

- `Prediction_cells_tsetse_distance_cattle_and_burden.csv` (required)
- `Uncertainty_only_primary_masks_25km.csv` (required)
- `Uncertainty_only_mask_thresholds.csv` (optional)

Keep `basemap.geojson` in the directory. The old `prepare_data.R` selected the full original audit CSVs; the new app can read those directly. If you want smaller CSVs with only the columns used by the website, use one of the following preparation options instead.

**R option** (from the original project root, with this folder named `AAT_Burden_Explorer_Website` next to `Code_Nagana/`):

```r
Sys.setenv(AAT_WEB_VISIBILITY = "public") # ONLY after approval
source("AAT_Burden_Explorer_Website/prepare_data.R")
```

If the audit is elsewhere, set `Sys.setenv(AAT_AUDIT_DIR="/absolute/path/to/Tsetse_belt_audit")` first. This script is supplied for convenience but has not been executed in the development environment, which lacks R.

**Python option** (standard library only, run in the website folder):

```bash
python3 tools/prepare_data.py /path/to/Tsetse_belt_audit --approved-public
```

The Python script was tested on synthetic audit files. Both scripts select only the columns needed by the existing R calculation and preserve numeric strings without rounding. They refuse files >=100 MiB. For GitHub's browser upload, keep each file under 25 MiB; for larger files use Git on the command line or a Git client (GitHub's regular Git file limit is 100 MiB). Do not commit any unnecessary source data. Missing required columns or unmatched cells will cause a visible error in the website.

## 2. Test on your own computer

Open Terminal, change into the extracted website directory, then run:

```bash
python3 -m http.server 8000
```

Visit <http://localhost:8000> in your browser. Do not double-click `index.html`: local browser file restrictions may prevent CSV loading. Press Ctrl+C in Terminal to stop the server. The local server is just for previewing; GitHub Pages supplies the actual hosting.

Check that your default +50 km scenario matches the existing Shiny app, then test unrestricted and regional buffers, both uncertainty metrics, all map modes and the sensitivity plots. If Node.js is installed, an additional local check prints unrounded default, unrestricted and regional figures and checks all buffer stages:

```bash
node tools/validate_data.js
```

Compare those figures against your original Shiny application/audit results. This is still necessary: the real research CSVs were not provided during conversion and no actual R-vs-JavaScript run on them was possible.

## 3. Publish on GitHub Pages (free public website)

1. Sign into GitHub and create a **public** repository, for example `aat-burden-explorer`.
2. Upload the contents of this folder, not the enclosing folder. The repository root must contain `index.html`, `style.css`, `app.js`, `model.js`, `map.js`, `.nojekyll` and the `data/` directory with the basemap and approved CSVs. The README, preparation and test scripts are optional for deployment. Never upload the old fitted models or survey data. If your upload tool omits `.nojekyll`, create an empty file of that name at the root (recommended, not essential for these filenames).
3. In the repository, go to **Settings → Pages → Build and deployment**. Set **Source** to **Deploy from a branch**. Select `main`, `/ (root)`, then **Save**.
4. When the Pages deployment succeeds, open the URL shown in Settings → Pages. It will typically look like `https://YOUR_USERNAME.github.io/aat-burden-explorer/`.
5. Check the live website and share the link. Subsequent data updates require replacing the CSV files and committing the changes. GitHub redeploys the site automatically.

A free static site is subject to GitHub Pages' current storage, bandwidth and acceptable-use policies; no provider guarantees a free plan forever. Documentation: <https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site> and <https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits>.

## Scientific parity and changes from R

- Default +50 km buffer, no uncertainty filter; illustrative regional defaults +50/+10/+50 km. All ten buffer choices are retained. The unrestricted calculation uses the original `Cattle_total`, not a sum of potentially rounded zones. Fractional zonal allocations are used for finite buffers.
- Both uncertainty metrics and inclusive cutoffs retained; missing uncertainty is excluded only if filtering is active; the 95th-percentile anchor is optional. The probability slider is in percentage points, not proportions.
- Map centre rules follow the original code, including the explicit-inside exception for a missing distance. Map classes are not used to compute burden. Madagascar is excluded before all summaries. Country tables are continental even when a country is selected, matching the original R logic. Missing ISO codes are not included in country comparisons.
- The same posterior-mean arithmetic and exclusions are retained. No aggregate credible intervals are invented. The table is searchable by country, sortable on every column, and paginated; the plots use native SVG instead of ggplot2. No download controls.
- The map is a native Web Mercator canvas renderer rather than Leaflet/terra. It uses a bundled coarse Natural Earth basemap with pan, wheel zoom, zoom buttons, fit-region reset and nearest-cell inspection. All four overlays show original 25-km cell values with nearest-neighbour rendering. This differs from the original uncertainty layer's requested bilinear display and from the street-map basemap; the colour interpolation can also differ visually from R. High prevalence is saturated, not made transparent. Uncertainty above the legend maximum remains transparent as in the original R palette. Scientific calculations are unaffected by these presentation choices.
- Extra validation rejects duplicate projected grid centres and negative cattle totals. Data parsing preserves cell IDs as strings. The app refuses data with missing columns, inconsistent joins or inconsistent zone counts rather than silently making corrections.

## Development tests

```bash
node tests/model.test.js
# optional browser tests (Python Playwright + installed Chromium required)
python3 tests/browser_test.py
```

Tests create temporary artificial data and do not add it to the publication directory. The numerical tests compare 2,000 scenarios to an independently written direct source-column calculation, plus explicit known examples and data validation tests. The browser tests execute the shipped HTML, CSS and scripts in Chromium, injecting local assets and mocking fetch responses because the development browser blocks HTTP navigation. They cover the main controls, maps, tables, plots, missing files and mobile layout. They do not verify real-data numerical equivalence against R, actual GitHub hosting, other browsers or production-sized performance. See `TEST_REPORT.md` for details.

## Data and attribution

The Natural Earth basemap is a public-domain 1:110m country layer (Natural Earth, <https://www.naturalearthdata.com/about/terms-of-use/>), included as GeoJSON. It is for orientation, not an authoritative epidemiological or political boundary dataset. Scientific country allocation is inherited from the audit CSVs, not the basemap.
