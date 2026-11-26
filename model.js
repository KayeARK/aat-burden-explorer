/* Scientific calculation layer. No DOM or external dependencies. */
(function(root){
'use strict';
const distances=[0,5,10,15,20,25,50,100,200,Infinity];
const labels=distances.map(k=>k===0?'Mapped tsetse only':k===Infinity?'Unrestricted':`Belt + ${k} km`);
const regions=['Sahel','Southern_Africa','Other'];
const regionLabels=['Sahel proxy','Southern Africa proxy','Other regions'];
const zones=['Cattle_inside',...distances.slice(1).map((k,i)=>Number.isFinite(k)?`Cattle_outside_${distances[i]}_${k}`:`Cattle_outside_gt_${distances[i]}`),'Cattle_unknown'];
const main=['cell_id','x3857','y3857','longitude','latitude','Country','iso_a3','Mean_Prevalence','Cattle_total','Infected_total','Buffer_region',...zones];
const unc=['cell_id','Posterior_CrI_Width','Posterior_Logit_CrI_Width','Distance_to_tsetse_belt_km_Centre','Tsetse_Presence_Centre'];
const anchorCols=['Metric_id','Threshold_source','Anchor_region','Quantile','Threshold_value'];
const finite=Number.isFinite;
const num=s=>s==null||String(s).trim()===''||['NA','NaN','NULL'].includes(String(s).trim())?NaN:Number(s);
const missing=s=>s==null||s===''||s==='NA';
function fail(s){throw new Error(s);}
function parseCSV(text){
 text=text.replace(/^\uFEFF/,'');let rows=[],row=[],field='',quoted=false,closed=false;
 const push=()=>{row.push(field);field='';closed=false;};
 const line=()=>{push();if(row.some(v=>v!==''))rows.push(row);row=[];};
 for(let i=0;i<text.length;i++){const ch=text[i];if(quoted){if(ch==='"'){if(text[i+1]==='"'){field+='"';i++;}else{quoted=false;closed=true;}}else field+=ch;continue;}
 if(ch===','){push();continue;}if(ch==='\n'||ch==='\r'){if(ch==='\r'&&text[i+1]==='\n')i++;line();continue;}
 if(closed)fail('Unexpected character after closing CSV quote.');if(ch==='"'){if(field!=='')fail('Unexpected quote in CSV field.');quoted=true;}else field+=ch;
 }if(quoted)fail('Unclosed quoted CSV field.');if(field!==''||row.length||closed)line();
 if(!rows.length)fail('Empty CSV file.');const header=rows.shift();if(new Set(header).size!==header.length)fail('Duplicate CSV column names.');
 return {header,rows:rows.map((r,i)=>{if(r.length!==header.length)fail(`CSV row ${i+2}: expected ${header.length} fields, got ${r.length}.`);return Object.fromEntries(header.map((h,j)=>[h,r[j]]));})};
}
function requireCols(table,cols,label){const absent=cols.filter(c=>!table.header.includes(c));if(absent.length)fail(`${label}: missing columns: ${absent.join(', ')}`);}
function indexRows(rows,label){const m=new Map();for(const r of rows){if(missing(r.cell_id))fail(`${label}: missing cell_id`);if(m.has(r.cell_id))fail(`${label}: duplicate cell_id ${r.cell_id}`);m.set(r.cell_id,r);}return m;}
function load(mainCSV,uncCSV,anchorCSV=null){
 const m=parseCSV(mainCSV),u=parseCSV(uncCSV);requireCols(m,main,'Main audit');requireCols(u,unc,'Uncertainty audit');indexRows(m.rows,'Main audit');const lookup=indexRows(u.rows,'Uncertainty audit');
 const cells=[];let maxError=0,missingProb=0,missingLogit=0;const grid=new Set();
 for(const r of m.rows){const v=lookup.get(r.cell_id);if(!v)fail(`Uncertainty audit missing cell ${r.cell_id}`);
 const p=num(r.Mean_Prevalence),x=num(r.x3857),y=num(r.y3857),lon=num(r.longitude),lat=num(r.latitude);
 if(!finite(p)||p<0||p>1)fail(`Invalid prevalence: ${r.cell_id}`);if(![x,y,lon,lat].every(finite))fail(`Invalid coordinates: ${r.cell_id}`);
 if(missing(r.Country)||r.Country.trim().toLowerCase()==='madagascar'||r.iso_a3.trim().toUpperCase()==='MDG')continue;
 const region=regions.indexOf(r.Buffer_region);if(region<0)fail(`Invalid Buffer_region: ${r.cell_id}`);
 let cattle=num(r.Cattle_total),infected=num(r.Infected_total),z=zones.map(c=>num(r[c]));
 if(!finite(cattle)&&z.some(finite))fail(`Unknown cattle total with known zone counts: ${r.cell_id}`);
 if(finite(cattle)&&cattle>0&&!z.every(finite))fail(`Missing zone count in positive-cattle cell: ${r.cell_id}`);
 if(z.some(a=>finite(a)&&a< -1e-6))fail(`Negative zone cattle: ${r.cell_id}`);
 if(finite(cattle)&&cattle<0)fail(`Negative cattle total: ${r.cell_id}`);
 z=z.map(a=>finite(a)?a:0);cattle=finite(cattle)?cattle:0;infected=finite(infected)?infected:0;
 const err=Math.abs(z.reduce((a,b)=>a+b,0)-cattle)/Math.max(cattle,1);maxError=Math.max(err,maxError);if(cattle>0&&err>0.001)fail(`Zone counts do not reconstruct total: ${r.cell_id}`);
 if(Math.abs(infected-cattle*p)>Math.max(1,infected)*1e-5)fail(`Infected total inconsistent with prevalence: ${r.cell_id}`);
 const key=`${x},${y}`;if(grid.has(key))fail(`Duplicate grid coordinates: ${r.cell_id}`);grid.add(key);
 const cumulative=[];let s=0;for(let i=0;i<distances.length-1;i++){s+=z[i];cumulative.push(s);}cumulative.push(cattle);
 const prob=num(v.Posterior_CrI_Width),logit=num(v.Posterior_Logit_CrI_Width);if(!finite(prob))missingProb++;if(!finite(logit))missingLogit++;
 cells.push({id:r.cell_id,x,y,lon,lat,country:r.Country,iso:missing(r.iso_a3)?'':r.iso_a3,region,p,cattle,infected,prob,logit,distance:num(v.Distance_to_tsetse_belt_km_Centre),presence:num(v.Tsetse_Presence_Centre),cumulative});
 }
 if(!cells.length)fail('No eligible country-assigned cells after excluding Madagascar.');
 const anchors={prob:NaN,logit:NaN};if(anchorCSV!==null){const a=parseCSV(anchorCSV);if(anchorCols.every(c=>a.header.includes(c))){for(const [key,metric] of [['prob','Probability_CrI_width'],['logit','Logit_CrI_width']]){const matches=a.rows.filter(r=>r.Metric_id===metric&&r.Threshold_source==='Unique Atlas sampling locations'&&r.Anchor_region==='Africa'&&Math.abs(num(r.Quantile)-0.95)<1e-9);if(matches.length===1)anchors[key]=num(matches[0].Threshold_value);}}}
 return {cells,anchors,checks:{maxError,missingProb,missingLogit}};
}
function evaluate(c,settings){const stage=settings.regional?settings.stages[c.region]:settings.stage;if(!Number.isInteger(stage)||stage<0||stage>=distances.length)fail('Invalid buffer stage');const km=distances[stage];const geo=c.cumulative[stage];const u=settings.metric==='prob'?c.prob*100:c.logit;const valid=finite(u);const pass=!settings.apply||valid&&u<=settings.threshold;const retained=pass?geo:0;const centre=km===Infinity||(finite(c.presence)&&c.presence>0.5)||(finite(c.presence)&&finite(c.distance)&&km>0&&c.distance<=km);return {c,km,geo,geoBurden:geo*c.p,retained,burden:retained*c.p,u,valid,pass,status:!centre?3:!pass?(valid?2:4):1,reported:centre&&pass?c.p:NaN};}
function empty(){return {allCattle:0,unrestricted:0,geoCattle:0,geoBurden:0,retainedCattle:0,retainedBurden:0,missingUncertainty:0};}
function add(s,r){s.allCattle+=r.c.cattle;s.unrestricted+=r.c.infected;s.geoCattle+=r.geo;s.geoBurden+=r.geoBurden;s.retainedCattle+=r.retained;s.retainedBurden+=r.burden;if(r.geo>0&&!r.valid)s.missingUncertainty++;return s;}
function finish(s){return {...s,cattleShare:s.allCattle>0?100*s.retainedCattle/s.allCattle:NaN,burdenShare:s.unrestricted>0?100*s.retainedBurden/s.unrestricted:NaN,geographicExclusion:s.unrestricted-s.geoBurden,uncertaintyExclusion:s.geoBurden-s.retainedBurden};}
function summarize(rows){const s=empty();for(const r of rows)add(s,r);return finish(s);}
function aggregate(cells,settings){const s=empty();for(const c of cells)add(s,evaluate(c,settings));return finish(s);}
function byCountry(rows){const g=new Map();for(const r of rows){if(!r.c.iso)continue;let s=g.get(r.c.iso);if(!s){s={...empty(),iso:r.c.iso,country:r.c.country};g.set(r.c.iso,s);}add(s,r);}return [...g.values()].map(finish).sort((a,b)=>b.retainedBurden-a.retainedBurden);}
function quantile(values,q){const s=values.filter(finite).sort((a,b)=>a-b);if(!s.length)return NaN;const h=(s.length-1)*q,i=Math.floor(h);return s[i]+(s[Math.min(i+1,s.length-1)]-s[i])*(h-i);}
function prevalenceCap(rows,auto,fixed){if(!auto)return Math.min(1,Math.max(.05,fixed/100));let max=-Infinity;for(const r of rows)if(finite(r.reported))max=Math.max(max,r.reported);return max===-Infinity?.5:Math.min(1,Math.max(.01,Math.ceil(max*100)/100));}
const api={distances,labels,regions,regionLabels,zones,main,unc,anchorCols,num,parseCSV,load,evaluate,summarize,aggregate,byCountry,quantile,prevalenceCap};if(typeof module==='object'&&module.exports)module.exports=api;else root.AAT=api;
})(typeof globalThis!=='undefined'?globalThis:this);
