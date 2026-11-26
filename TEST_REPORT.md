# Conversion verification

## Results

| Check | Result |
|---|---|
| JavaScript syntax (`node --check` for all application scripts) | Pass |
| Synthetic scientific scenario comparison | Pass — 2,000 combinations |
| Hand-calculated baseline, regional, unrestricted and uncertainty-filtered results | Pass |
| CSV quoted values, CRLF, BOM, embedded newline and malformed inputs | Pass |
| Duplicate cells, missing joins/columns, invalid prevalence, inconsistent cattle and burden | Pass |
| Missing uncertainty, centre-map statuses, Madagascar exclusion and optional anchors | Pass |
| Map colours, cap saturation and missing-value transparency | Pass |
| Python data preparation and local real-data validator, exercised on artificial inputs | Pass — 120 scenario consistency checks |
| Chromium UI interaction, all map modes, zoom, clicked cell, uncertainty and buffer controls | Pass |
| Country sorting and filtering, plots, methods, mobile-width overflow | Pass |
| Missing optional/required CSV behaviour | Pass |
| Desktop screenshot visual inspection | Pass |

## Scope of checks

The supplied source was `app(1).R` and its associated deployment/preparation documentation. The model was ported directly from the R formulas. The independent test reference sums the original zone columns directly, rather than using the new cumulative representation. Tests used six artificial rows, including one excluded Madagascar row. These are deliberately tiny synthetic examples, not AAT estimates. The test runner creates them in a temporary directory only.

The Chromium test injects the shipped HTML, styles and JavaScript, with mocked CSV/GeoJSON fetch responses. HTTP navigation was blocked by the development environment; therefore actual local HTTP serving, GitHub Pages publication and live URL behaviour were not tested. All site fetch paths are relative and the package is static. A local HTTP smoke test with the real data is required before deployment.

R was not installed in the conversion environment. The supplied convenience R preparation script has been inspected but not executed. The Python preparation script was executed successfully on synthetic CSVs, including the optional anchor file.

## Outstanding verification before scientific publication

- Add the actual approved audit output CSVs; none were provided with the source code.
- Compare the default, unrestricted, and several regional/uncertainty scenarios against the original Shiny app, including country totals and sensitivity values. Run `node tools/validate_data.js` if Node is available to inspect unrounded figures and internal consistency.
- Check the map and responsiveness with the complete real prediction grid and on your target browsers. No full-size performance guarantee is made from the tiny fixtures.
- Confirm that all derived data may be publicly downloaded, as required for a browser-side implementation.
- Verify the published GitHub Pages URL after deployment.

## Deliberate presentation differences

The native canvas map uses Natural Earth boundaries rather than live OpenStreetMap tiles; the original 25-km grid uses nearest-neighbour display for every layer (including uncertainty), whereas the R app requested bilinear interpolation for uncertainty. Colours and chart rendering are not intended to be pixel-identical to R. Country comparison has country search, column sorting and pagination rather than DataTables' separate per-column filters. These are presentation changes, not changes to the underlying burden estimates.
