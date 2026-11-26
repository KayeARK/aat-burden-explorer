/* Artificial unit-test data only. Never publish these as research results. */
const M=require('../model.js');
const csv=(header,rows)=>[header,...rows.map(r=>header.map(h=>r[h]??'NA'))].map(r=>r.map(v=>'"'+String(v).replaceAll('"','""')+'"').join(',')).join('\r\n');
function make(){const records=[
 ['A','Kenya','KEN','Other',0.2,100,[20,10,5,5,5,5,10,10,10,10,10],0.10,1,0,1,0,0],
 ['B','Sudan','SDN','Sahel',0.4,200,[0,20,20,20,20,20,20,20,20,20,20],0.35,3,15,0,25000,0],
 ['C','Zambia','ZMB','Southern_Africa',0.5,300,[60,30,30,30,30,30,30,20,10,10,20],'NA','NA','NA','NA',0,25000],
 ['D','Madagascar','MDG','Other',0.9,100,[100,0,0,0,0,0,0,0,0,0,0],0.1,1,0,1,25000,25000],
 ['E','Kenya','KEN','Other',0.8,0,[0,0,0,0,0,0,0,0,0,0,0],0.2,2,'NA',1,50000,0],
 ['F','Kenya','KEN','Other',0.1,100,[0,0,0,0,0,0,0,0,0,0,100],0.2,2,0,'NA',50000,25000]
 ];const main=[],unc=[];for(const [id,Country,iso_a3,Buffer_region,p,cattle,z,prob,logit,distance,presence,dx,dy] of records){const x=3000000+dx,y=500000+dy;main.push({cell_id:id,Country,iso_a3,Buffer_region,Mean_Prevalence:p,Cattle_total:cattle,Infected_total:cattle*p,x3857:x,y3857:y,longitude:x/6378137*180/Math.PI,latitude:(2*Math.atan(Math.exp(y/6378137))-Math.PI/2)*180/Math.PI,...Object.fromEntries(M.zones.map((k,i)=>[k,z[i]]))});unc.push({cell_id:id,Posterior_CrI_Width:prob,Posterior_Logit_CrI_Width:logit,Distance_to_tsetse_belt_km_Centre:distance,Tsetse_Presence_Centre:presence});}
 const anchors=[{Metric_id:'Probability_CrI_width',Threshold_source:'Unique Atlas sampling locations',Anchor_region:'Africa',Quantile:.95,Threshold_value:.25},{Metric_id:'Logit_CrI_width',Threshold_source:'Unique Atlas sampling locations',Anchor_region:'Africa',Quantile:.95,Threshold_value:2.4}];return {main,unc,anchors,mainCSV:csv(M.main,main),uncCSV:csv(M.unc,unc.reverse()),anchorCSV:csv(M.anchorCols,anchors)};}
if(require.main===module){const fs=require('node:fs'),path=require('node:path'),out=process.argv[2];if(!out)throw Error('Specify temporary fixture destination');fs.mkdirSync(out,{recursive:true});const f=make();for(const [name,value] of [['Prediction_cells_tsetse_distance_cattle_and_burden.csv',f.mainCSV],['Uncertainty_only_primary_masks_25km.csv',f.uncCSV],['Uncertainty_only_mask_thresholds.csv',f.anchorCSV]])fs.writeFileSync(path.join(out,name),value);}
module.exports={make,csv};
