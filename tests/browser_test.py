"""Optional browser smoke test. Requires Python playwright and Chromium; uses only temporary synthetic data."""
from pathlib import Path
import tempfile, shutil, subprocess, os
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent.parent

def main():
 with tempfile.TemporaryDirectory() as t:
  target=Path(t)/'site';shutil.copytree(ROOT,target,ignore=shutil.ignore_patterns('*.csv','__pycache__')); subprocess.run(['node',str(ROOT/'tests/fixtures.js'),str(target/'data')],check=True)
  with sync_playwright() as p:
   browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH',shutil.which('chromium')),args=['--no-sandbox']);page=browser.new_page(viewport={'width':1440,'height':1050});errors=[];page.on('pageerror',lambda e: errors.append(str(e)))
   # Inject local assets and mock same-origin fetch to run even in a network-restricted browser.
   import json
   def load_page():
    payload={f'data/{f.name}':f.read_text() for f in (target/'data').iterdir() if f.suffix in ('.csv','.geojson')}
    html=(target/'index.html').read_text().replace('<link rel="stylesheet" href="style.css">','<style>'+ (target/'style.css').read_text()+'</style>')
    for n in ('model.js','map.js','app.js'): html=html.replace(f'<script defer src="{n}"></script>','')
    page.goto('about:blank');page.set_content(html)
    page.evaluate('(files)=>{window.fetch=async (url)=>new Response(files[url]??"Not found",{status:Object.hasOwn(files,url)?200:404});}',payload)
    for n in ('model.js','map.js','app.js'): page.add_script_tag(content=(target/n).read_text())
   load_page();page.locator('#dashboard').wait_for(state='visible');page.wait_for_function("document.querySelector('#scenario_caption').textContent.includes('Belt + 50 km')");assert page.locator('#kpi_bshare').inner_text()=='69.2%';assert page.locator('#kpi_cshare').inner_text()=='60.0%';assert not page.locator('#country option[value=MDG]').count()
   page.wait_for_function("document.querySelector('#aat_map').width>0");page.wait_for_timeout(200);page.locator('#aat_map').click(position={'x':400,'y':250});assert 'Selected cell' in page.locator('#clicked_cell').inner_text();page.locator('#zoom-in').click();page.locator('#zoom-out').click();page.locator('#map-reset').click()
   page.locator('#map_mode').select_option('prevalence');page.wait_for_function("document.querySelector('#map_legend').textContent.includes('Mean prevalence')");page.locator('#prevalence_max_pct').fill('5');page.wait_for_function("document.querySelector('#prevalence_scale_note').textContent.includes('saturated')");page.locator('input[name=prevalence_scale][value=auto]').check();page.wait_for_function("document.querySelector('#prevalence_scale_note').textContent.includes('80%')");
   page.locator('#map_mode').select_option('regions');page.wait_for_function("document.querySelector('#map_legend').textContent.includes('Provisional buffer regions')");page.locator('#map_mode').select_option('uncertainty');page.wait_for_function("document.querySelector('#map_legend').textContent.includes('logit')")
   page.locator('#apply_unc').check();page.wait_for_function("document.querySelector('#kpi_bshare').textContent==='4.6%'");page.locator('#apply_unc').uncheck();page.locator('input[name=buffer_mode][value=regional]').check();page.wait_for_function("document.querySelector('#kpi_bshare').textContent==='46.2%'");page.locator('input[name=buffer_mode][value=uniform]').check();page.locator('#buffer_stage').select_option('9');page.wait_for_function("document.querySelector('#kpi_bshare').textContent==='100.0%'");
   page.locator('#unc_metric').select_option('prob');page.locator('#anchor').click();page.wait_for_function("document.querySelector('#apply_unc').checked && document.querySelector('#prob_width_pp').value==='25'");page.wait_for_function("document.querySelector('#kpi_bshare').textContent==='11.5%'");page.locator('#apply_unc').uncheck();page.locator('#country').select_option('KEN');page.wait_for_function("document.querySelector('#scenario_caption').textContent.startsWith('Kenya')");
   page.locator('#tab-country').click();page.locator('#country_table tbody tr').first.wait_for();assert page.locator('#country_table tbody tr').count()==3;page.locator('#table-search').fill('Sudan');assert page.locator('#country_table tbody tr').count()==1;assert 'Sudan' in page.locator('#country_table tbody tr').inner_text();page.locator('#table-search').fill('');page.locator('#country_table thead button').first.click();assert page.locator('#country_chart svg').count()==1
   page.locator('#tab-sensitivity').click();page.locator('#buffer_plot svg').wait_for();assert page.locator('#uncertainty_plot svg').count()==1;page.locator('#unc_metric').select_option('logit');page.wait_for_function("document.querySelector('#uncertainty_plot svg').textContent.includes('logit')");page.locator('#tab-methods').click();assert 'Loaded cells: 5' in page.locator('#checks').inner_text();page.locator('#country').select_option('ALL');page.locator('#tab-map').click();page.wait_for_function("document.querySelector('#scenario_caption').textContent.startsWith('Africa')");
   # Responsive layout and a screenshot for visual review.
   page.locator('#map_mode').select_option('status');page.locator('#buffer_stage').select_option('6');page.wait_for_timeout(300)
   if os.environ.get('AAT_SCREENSHOT'): page.screenshot(path=os.environ['AAT_SCREENSHOT'],full_page=True)
   page.set_viewport_size({'width':390,'height':844});page.wait_for_timeout(250);assert page.evaluate('document.documentElement.scrollWidth <= innerWidth+1');assert not errors,errors
   # Graceful optional and missing-required file handling.
   (target/'data/Uncertainty_only_mask_thresholds.csv').unlink();load_page();page.locator('#dashboard').wait_for(state='visible');assert page.locator('#anchor').is_disabled();(target/'data/Uncertainty_only_primary_masks_25km.csv').unlink();load_page();page.locator('#error').wait_for(state='visible');assert 'HTTP 404' in page.locator('#error-text').inner_text();browser.close()
  print('PASS: Chromium dashboard, map modes/zoom/cell inspection, colour saturation, regional controls, uncertainty anchor, country table, plots, methods, mobile overflow, missing optional and required files.')
if __name__=='__main__': main()
