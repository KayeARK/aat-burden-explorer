/* Self-contained Web Mercator canvas map. Natural Earth public-domain basemap. */
(function(root){'use strict';
const R=6378137, DEG=Math.PI/180, CELL=25000;
const xy=(lon,lat)=>[R*lon*DEG,R*Math.log(Math.tan(Math.PI/4+Math.max(-85.05112878,Math.min(85.05112878,lat))*DEG/2))];
const lonlat=(x,y)=>[x/R/DEG,(2*Math.atan(Math.exp(y/R))-Math.PI/2)/DEG];
const status=['#1d998b','#f4aa54','#c7ccd1','#d95f58'],region=['#D59A43','#5186B0','#A5ACA8'];
const palette=['#ffffcc','#ffeda0','#fed976','#feb24c','#fd8d3c','#fc4e2a','#e31a1c','#bd0026','#800026'];
const rgb=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
const colors=palette.map(rgb);
function ramp(v,cap){if(!Number.isFinite(v)||!Number.isFinite(cap)||cap<=0)return null;const t=Math.min(1,Math.max(0,v/cap))*(colors.length-1),i=Math.floor(t),f=t-i;return colors[i].map((n,j)=>Math.round(n+(colors[Math.min(i+1,colors.length-1)][j]-n)*f));}
function color(r,mode,cap){if(mode==='status')return rgb(status[r.status-1]);if(mode==='regions')return rgb(region[r.c.region]);if(mode==='prevalence')return ramp(r.reported,cap);if(r.u<0||r.u>cap)return null;return ramp(r.u,cap);}
class AtlasMap{
 constructor(canvas,inspect){this.canvas=canvas;this.ctx=canvas.getContext('2d');this.inspect=inspect;this.rows=[];this.shapes=[];this.labels=[];this.center=xy(19,1);this.scale=1/20000;this.opacity=.85;this.frame=0;this.drag=null;this.raster=null;this.selected=null;this.fitted=false;
 new ResizeObserver(()=>{const w=canvas.clientWidth,h=canvas.clientHeight;if(w&&h){if(!this.fitted)this.fitAfrica();this.schedule();}}).observe(canvas);
 canvas.addEventListener('wheel',e=>{e.preventDefault();const p=this.pos(e);this.zoom(Math.exp(-e.deltaY*.0016),p);},{passive:false});
 canvas.addEventListener('pointerdown',e=>{if(e.button!==0)return;canvas.setPointerCapture(e.pointerId);this.drag={id:e.pointerId,start:this.pos(e),center:[...this.center],moved:false};canvas.classList.add('dragging');});
 canvas.addEventListener('pointermove',e=>{if(!this.drag||this.drag.id!==e.pointerId)return;const p=this.pos(e),dx=p[0]-this.drag.start[0],dy=p[1]-this.drag.start[1];if(Math.hypot(dx,dy)>3)this.drag.moved=true;if(this.drag.moved){this.center=[this.drag.center[0]-dx/this.scale,this.drag.center[1]+dy/this.scale];this.clamp();this.schedule();}});
 const end=e=>{if(!this.drag||this.drag.id!==e.pointerId)return;const d=this.drag;this.drag=null;canvas.classList.remove('dragging');if(e.type==='pointerup'&&!d.moved)this.pick(this.pos(e));};canvas.addEventListener('pointerup',end);canvas.addEventListener('pointercancel',end);
 canvas.addEventListener('keydown',e=>{const d=80/this.scale;if(e.key==='+'||e.key==='=')this.zoom(1.5);else if(e.key==='-')this.zoom(1/1.5);else if(e.key==='ArrowLeft')this.center[0]-=d;else if(e.key==='ArrowRight')this.center[0]+=d;else if(e.key==='ArrowUp')this.center[1]+=d;else if(e.key==='ArrowDown')this.center[1]-=d;else if(e.key==='Enter'){this.pick([canvas.clientWidth/2,canvas.clientHeight/2]);}else return;e.preventDefault();this.clamp();this.schedule();});
 }
 pos(e){const r=this.canvas.getBoundingClientRect();return [e.clientX-r.left,e.clientY-r.top];}
 world(p){return [this.center[0]+(p[0]-this.canvas.clientWidth/2)/this.scale,this.center[1]-(p[1]-this.canvas.clientHeight/2)/this.scale];}
 screen(x,y){return [(x-this.center[0])*this.scale+this.canvas.clientWidth/2,(this.center[1]-y)*this.scale+this.canvas.clientHeight/2];}
 clamp(){this.center[0]=Math.max(-20037508,Math.min(20037508,this.center[0]));this.center[1]=Math.max(-20037508,Math.min(20037508,this.center[1]));}
 zoom(f,p=[this.canvas.clientWidth/2,this.canvas.clientHeight/2]){const a=this.world(p);this.scale=Math.min(.006,Math.max(.000008,this.scale*f));const b=this.world(p);this.center=[this.center[0]+a[0]-b[0],this.center[1]+a[1]-b[1]];this.clamp();this.schedule();}
 fitBounds(x0,y0,x1,y1){const w=this.canvas.clientWidth,h=this.canvas.clientHeight;if(!w||!h)return;this.center=[(x0+x1)/2,(y0+y1)/2];this.scale=Math.max(.000008,Math.min(.006,(w*.86)/Math.max(x1-x0,100000),(h*.88)/Math.max(y1-y0,100000)));this.fitted=true;this.schedule();}
 fitAfrica(){const a=xy(-22,-37),b=xy(56,39);this.fitBounds(...a,...b);}
 fitRows(all){if(all||!this.rows.length){this.fitAfrica();return;}let x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;for(const {c} of this.rows){x0=Math.min(x0,c.x-CELL/2);x1=Math.max(x1,c.x+CELL/2);y0=Math.min(y0,c.y-CELL/2);y1=Math.max(y1,c.y+CELL/2);}this.fitBounds(x0,y0,x1,y1);}
 setBasemap(g){this.shapes=[];for(const f of g.features||[]){const geo=f.geometry;if(!geo)continue;const polygons=geo.type==='Polygon'?[geo.coordinates]:geo.type==='MultiPolygon'?geo.coordinates:[];for(const poly of polygons){this.shapes.push(poly.map(ring=>ring.map(p=>xy(p[0],p[1]))));}}this.schedule();}
 setLabels(cells){const g=new Map();for(const c of cells){if(!c.iso)continue;let a=g.get(c.iso);if(!a){a={name:c.country,x:0,y:0,n:0};g.set(c.iso,a);}a.x+=c.x;a.y+=c.y;a.n++;}this.labels=[...g.values()].map(a=>({...a,x:a.x/a.n,y:a.y/a.n}));}
 setData(rows,mode,cap,opacity,selected){this.rows=rows;this.opacity=opacity;this.selected=selected;this.mode=mode;this.cap=cap;this.raster=null;
 if(rows.length){let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;for(const {c} of rows){minX=Math.min(minX,c.x);maxX=Math.max(maxX,c.x);minY=Math.min(minY,c.y);maxY=Math.max(maxY,c.y);}const w=Math.round((maxX-minX)/CELL)+1,h=Math.round((maxY-minY)/CELL)+1;
 const aligned=w*h<=4000000&&rows.every(({c})=>Math.abs((c.x-minX)/CELL-Math.round((c.x-minX)/CELL))<1e-5&&Math.abs((maxY-c.y)/CELL-Math.round((maxY-c.y)/CELL))<1e-5);
 if(aligned){const c=document.createElement('canvas');c.width=w;c.height=h;const ctx=c.getContext('2d'),im=ctx.createImageData(w,h);for(const r of rows){const col=color(r,mode,cap);if(!col)continue;const i=(Math.round((maxY-r.c.y)/CELL)*w+Math.round((r.c.x-minX)/CELL))*4;im.data.set([...col,255],i);}ctx.putImageData(im,0,0);this.raster={canvas:c,left:minX-CELL/2,top:maxY+CELL/2,w:w*CELL,h:h*CELL};}}
 this.schedule();}
 pick(p){if(!this.rows.length)return;const [lon,lat]=lonlat(...this.world(p));let best=null,dist=Infinity;const k=Math.cos(lat*DEG);for(const r of this.rows){const d=((r.c.lon-lon)*k)**2+(r.c.lat-lat)**2;if(d<dist){dist=d;best=r;}}if(best){this.selected=best.c.id;this.inspect(best.c.id);this.schedule();}}
 schedule(){if(this.frame)return;this.frame=requestAnimationFrame(()=>{this.frame=0;this.draw();});}
 draw(){const w=this.canvas.clientWidth,h=this.canvas.clientHeight;if(!w||!h)return;const dpr=Math.min(devicePixelRatio||1,2);if(this.canvas.width!==Math.round(w*dpr)||this.canvas.height!==Math.round(h*dpr)){this.canvas.width=Math.round(w*dpr);this.canvas.height=Math.round(h*dpr);}const ctx=this.ctx;ctx.setTransform(dpr,0,0,dpr,0,0);ctx.fillStyle='#e5edf0';ctx.fillRect(0,0,w,h);
 for(const poly of this.shapes){ctx.beginPath();for(const ring of poly){let first=true;for(const p of ring){const [x,y]=this.screen(...p);if(first){ctx.moveTo(x,y);first=false;}else ctx.lineTo(x,y);}ctx.closePath();}ctx.fillStyle='#f4f3ed';ctx.fill('evenodd');ctx.strokeStyle='#b4b9b0';ctx.lineWidth=.65;ctx.stroke();}
 ctx.globalAlpha=this.opacity;ctx.imageSmoothingEnabled=false;if(this.raster){const r=this.raster,[x,y]=this.screen(r.left,r.top);ctx.drawImage(r.canvas,x,y,r.w*this.scale,r.h*this.scale);}else{for(const r of this.rows){const col=color(r,this.mode,this.cap);if(!col)continue;const [x,y]=this.screen(r.c.x-CELL/2,r.c.y+CELL/2);ctx.fillStyle=`rgb(${col.join(',')})`;ctx.fillRect(x,y,CELL*this.scale,CELL*this.scale);}}ctx.globalAlpha=1;
 ctx.font='11px system-ui';ctx.textAlign='center';ctx.textBaseline='middle';const occupied=[];for(const a of this.labels){const [x,y]=this.screen(a.x,a.y),tw=ctx.measureText(a.name).width;if(x<0||x>w||y<0||y>h||occupied.some(b=>Math.abs(b.x-x)<(b.w+tw)/2+5&&Math.abs(b.y-y)<13))continue;occupied.push({x,y,w:tw});ctx.strokeStyle='#ffffffd9';ctx.lineWidth=2.6;ctx.strokeText(a.name,x,y);ctx.fillStyle='#344b54';ctx.fillText(a.name,x,y);}
 const chosen=this.rows.find(r=>r.c.id===this.selected);if(chosen){const [x,y]=this.screen(chosen.c.x,chosen.c.y);const s=Math.max(5,CELL*this.scale);ctx.strokeStyle='#fff';ctx.lineWidth=3;ctx.strokeRect(x-s/2,y-s/2,s,s);ctx.strokeStyle='#17343e';ctx.lineWidth=1.5;ctx.strokeRect(x-s/2,y-s/2,s,s);}
 }
}
root.AtlasMap=AtlasMap;root.AATPalette={status,region,palette,ramp,color,xy,lonlat};
})(globalThis);
