#!/usr/bin/env python3
"""Copy only columns used by the static app; preserve original numeric text."""
import argparse, csv, os, tempfile
from pathlib import Path
DIST=[0,5,10,15,20,25,50,100,200]
ZONES=['Cattle_inside']+[f'Cattle_outside_{a}_{b}' for a,b in zip(DIST,DIST[1:])]+['Cattle_outside_gt_200','Cattle_unknown']
FILES={
 'Prediction_cells_tsetse_distance_cattle_and_burden.csv':['cell_id','x3857','y3857','longitude','latitude','Country','iso_a3','Mean_Prevalence','Cattle_total','Infected_total','Buffer_region']+ZONES,
 'Uncertainty_only_primary_masks_25km.csv':['cell_id','Posterior_CrI_Width','Posterior_Logit_CrI_Width','Distance_to_tsetse_belt_km_Centre','Tsetse_Presence_Centre'],
 'Uncertainty_only_mask_thresholds.csv':['Metric_id','Threshold_source','Anchor_region','Quantile','Threshold_value']}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('audit_dir',type=Path);p.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'data');p.add_argument('--approved-public',action='store_true',help='Confirm derived cell-level data are approved for public release.');a=p.parse_args()
 if not a.approved_public: p.error('Public GitHub Pages exposes these CSVs. Use --approved-public only after checking permission.')
 a.output.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(dir=a.output) as temp:
  staged=[]
  for i,(filename,columns) in enumerate(FILES.items()):
   src=a.audit_dir/filename
   if i==2 and not src.exists(): continue
   dst=Path(temp)/filename
   with src.open(encoding='utf-8-sig',newline='') as f,dst.open('w',encoding='utf-8',newline='') as out:
    reader=csv.DictReader(f);missing=set(columns)-set(reader.fieldnames or [])
    if missing: raise ValueError(f'{src}: missing columns {sorted(missing)}')
    if len(set(reader.fieldnames))!=len(reader.fieldnames): raise ValueError(f'{src}: duplicate headers')
    writer=csv.DictWriter(out,fieldnames=columns,extrasaction='ignore',lineterminator='\n');writer.writeheader();n=0
    for row in reader:
     if None in row or any(row[k] is None for k in columns): raise ValueError(f'{src}: malformed row {reader.line_num}')
     writer.writerow(row);n+=1
   if dst.stat().st_size>=100*1024**2: raise ValueError(f'{filename} is at least 100 MiB, too large for normal GitHub upload. Contact maintainer about splitting.')
   staged.append((dst,a.output/filename));print(f'{filename}: {n:,} rows; {dst.stat().st_size/1024**2:.2f} MiB')
  for src,dst in staged: os.replace(src,dst)
  optional=a.output/list(FILES)[-1]
  if not (a.audit_dir/list(FILES)[-1]).exists() and optional.exists(): optional.unlink();print('Removed stale optional threshold CSV.')
 print('Snapshot ready. Validate locally before uploading. No raw records or fitted models copied.')
if __name__=='__main__': main()
