// Soft Graphite fullscreen behavior. No extra desktops or keep-above windows.
'use strict';
const initialState={}; // replaced by the session loader
const tracked = new Set();
const saved = new Map();
const busy = new Set();
const windowTimers = new Map();
let previous = '';
let pointerRegions=[];
let pointerKey='';
const pointerRefresh=new QTimer();pointerRefresh.singleShot=true;pointerRefresh.interval=180;
pointerRefresh.timeout.connect(()=>callDBus('org.leonid.SoftGraphite','/SoftGraphite','org.leonid.SoftGraphite','PointerConfig',receiveRegions));
function receiveRegions(data){try{pointerRegions=JSON.parse(data);pointerKey='';refreshColumnAreas();pointerReport();}catch(e){}}
const syncTimer=new QTimer();syncTimer.singleShot=true;syncTimer.interval=50;syncTimer.timeout.connect(report);
function sync(){if(!syncTimer.active)syncTimer.start();}
// Layer-shell overlays (logout screen and similar) are typed as normal windows; they live in
// KWin's OverlayLayer (9), where application windows never are. Shrinking them into a centred
// floating window fought their full-screen anchors (black logout screen for seconds).
function shellOverlay(w){return w.layer>=9;}
function captureApp(w){return String(w.resourceClass).toLowerCase()==='org.kde.spectacle';}
function captureWindow(w){return !w.deleted&&captureApp(w)&&String(w.tag)==='region-editor'&&!w.minimized&&!w.hidden;}
function nativeMediaViewer(w){return String(w.resourceClass).toLowerCase()==='org.telegram.desktop' && /^(Просмотр медиа|Media viewer)$/i.test(String(w.caption));}
// XWayland VS Code, ChatGPT and Antigravity can restore a black client buffer after
// real fullscreen is unmapped. Borderless native maximization preserves their
// renderer, menu export and restore geometry. Explicit application F11 is untouched.
function nativeMaxWindow(w){return /^(google-chrome(?:-(?:stable|beta|unstable))?|chromium(?:-browser)?|firefox|org[.]mozilla[.]firefox|brave-browser|microsoft-edge|vivaldi-stable|yandex-browser(?: \(.*\))?|ru[.]yandex[.]Browser|com[.]microsoft[.]VSCode(?:Insiders)?|code(?:-oss|-insiders)?|VSCodium|codium|chatgpt|antigravity)$/i.test(String(w.resourceClass));}
function expanded(w){return w.fullScreen||(nativeMaxWindow(w)&&w.maximizeMode===3);}
function leave(w){if(!w)return;if(w.fullScreen)w.fullScreen=false;else if(nativeMaxWindow(w))w.setMaximize(false,false);}
function key(w) { return String(w.internalId); }
function rect(w) { const g=w.frameGeometry; return {x:g.x,y:g.y,width:g.width,height:g.height}; }
function report() {
 const all=workspace.windowList();
 const screens=workspace.screens.map(s=>({name:s.name,fullscreen:'',front:'',appName:'',pid:0,capture:all.some(w=>captureWindow(w)&&w.output.name===s.name)}));
 const order=workspace.stackingOrder || all;
 for(const w of order) {
  if(w.deleted || String(w.resourceClass)==="soft-graphite-edge" || captureWindow(w) || !w.normalWindow || shellOverlay(w) || w.minimized || w.hidden || (w.desktops.length && !w.desktops.some(d=>String(d.id)===String(workspace.currentDesktopForScreen(w.output).id))))continue;
  const s=screens.find(s=>s.name===w.output.name);
  if(s){s.fullscreen=expanded(w)?key(w):'';s.front=key(w);s.appName=w.caption.split(' — ').pop();s.pid=w.pid;}
 }
 const state={screens,windows:all.filter(w=>(w.normalWindow&&!shellOverlay(w)) || w.dock).map(w=>({id:key(w),app:String(w.resourceClass),caption:w.caption,output:w.output.name,fullscreen:w.fullScreen,expanded:expanded(w),maximize:w.maximizeMode,minimized:w.minimized,active:w===workspace.activeWindow,keepAbove:w.keepAbove,geometry:rect(w),restore:saved.get(key(w))?.geometry,snapRestore:saved.get(key(w))?.snapRestore,columnReturn:saved.get(key(w))?.columnReturn,columnSide:isColumnTile(w.tile)?(w.tile===w.tile.parent.tiles[0]?"left":"right"):null}))};
 const data=JSON.stringify(state);
 if(data===previous)return;
 previous=data;
 callDBus('org.leonid.SoftGraphite','/SoftGraphite','org.leonid.SoftGraphite','Update',data,receiveRegions);
 pointerRefresh.start();
}
function enter(w) {
 if(!w || captureApp(w) || nativeMediaViewer(w) || !w.normalWindow || !w.fullScreenable || busy.has(key(w)))return;
 const k=key(w);busy.add(k);
 let data=saved.get(k)||{geometry:rect(w),entered:false};data.entered=!nativeMaxWindow(w);saved.set(k,data);detachColumn(w,true);
 // Preserve the client maximize transaction; clearing it here races GTK CSD.
 if(nativeMaxWindow(w)){data.nativeMax=true;w.setMaximize(true,true);}else w.fullScreen=true;
 busy.delete(k);sync();
}
// Saved geometry can span just one screen dimension (for example VS Code
// restores a fullscreen session as 1919 x 720). Fit each dimension separately.
function floatingGeometry(screen, candidate) {
 const defaultWidth=Math.min(1200,Math.round(screen.width*.72));
 const defaultHeight=Math.min(800,Math.round(screen.height*.76));
 let width=candidate&&candidate.width>200?candidate.width:defaultWidth;
 let height=candidate&&candidate.height>100?candidate.height:defaultHeight;
 if(width>=screen.width-40)width=Math.min(width,defaultWidth);
 if(height>=screen.height-60)height=Math.min(height,defaultHeight);
 return {x:screen.x+Math.round((screen.width-width)/2),y:screen.y+Math.round((screen.height-height)/2),width,height};
}
function validRestore(w, candidate) {
 const g=w.output.geometry;
 if(candidate && candidate.width>200 && candidate.height>100 && candidate.width<g.width-40 && candidate.height<g.height-60 && candidate.x>=g.x && candidate.x<g.x+g.width)return candidate;
 return floatingGeometry(g,candidate);
}
let activeDrag=null,previewKey='';
const COLUMN_LAYOUT='soft-graphite-columns';
const columnRoots=new WeakSet(),columnUpdating=new Set();
function columnArea(output){
 const g=output.geometry,regions=pointerRegions.find(o=>o.name===output.name);
 const panels=regions?[regions.left,regions.right].filter(r=>r&&r.width>0&&r.height>0&&Number.isFinite(r.y)&&r.y>=g.y&&r.y+r.height<g.y+g.height):[];
 const top=(panels.length?Math.max.apply(null,panels.map(r=>r.y+r.height)):g.y+52)-10+8;
 const dock=regions&&regions.dock;
 const bottom=(dock&&dock.width>0&&dock.height>0&&Number.isFinite(dock.y)&&dock.y>top+8&&dock.y<=g.y+g.height?dock.y+10:g.y+g.height-70)-8;
 return {x:g.x+8,y:top,width:g.width-16,height:Math.max(1,bottom-top)};
}
function columnRoot(output){return typeof workspace.rootTile==='function'?workspace.rootTile(output,workspace.currentDesktopForScreen(output)):null;}
function isColumnRoot(root){return root&&root.objectName===COLUMN_LAYOUT&&root.tiles.length===2;}
function isColumnTile(tile){return tile&&isColumnRoot(tile.parent);}
function columnInScope(w,output){
 return !w.deleted&&w.output&&output&&w.output.name===output.name&&!w.onAllDesktops&&w.desktops.some(d=>String(d.id)===String(workspace.currentDesktopForScreen(output).id));
}
function checkColumnScope(w){
 const tile=w.tile,data=saved.get(key(w));
 if(isColumnTile(tile)&&(!columnInScope(w,w.output)||tile.parent!==columnRoot(w.output))){
  if(data){data.columnResize=null;data.columnReturn=null;data.snapRestore=null;}
  tile.unmanage(w);
 }
 sync();
}
function columnLimits(w){
 if(!w)return {min:0,max:Infinity,minHeight:0,maxHeight:Infinity};
 const f=w.frameGeometry,c=w.clientGeometry||f,dw=Math.max(0,f.width-c.width),dh=Math.max(0,f.height-c.height);
 return {min:(w.minSize?.width||0)+dw,max:(w.maxSize?.width||Infinity)+dw,minHeight:(w.minSize?.height||0)+dh,maxHeight:(w.maxSize?.height||Infinity)+dh};
}
function columnPlan(output,candidate=null,side=-1,requestedSplit=null){
 const g=output.geometry,area=columnArea(output),root=columnRoot(output),limits=[];
 for(let i=0;i<2;++i){
  const windows=isColumnRoot(root)?root.tiles[i].windows.filter(w=>columnInScope(w,output)&&!expanded(w)&&w!==candidate):[];
  if(candidate&&i===side)windows.push(candidate);
  const all=windows.map(columnLimits);
  limits[i]={min:all.reduce((v,l)=>Math.max(v,l.min),0),max:all.reduce((v,l)=>Math.min(v,l.max),Infinity)};
  if(all.some(l=>l.minHeight>area.height||l.maxHeight<area.height))return null;
 }
 // Each native tile has 8 px on its outside and half the shared 8 px gap.
 const low=Math.max(12+limits[0].min,g.width-12-limits[1].max);
 const high=Math.min(g.width-12-limits[1].min,12+limits[0].max);
 if(low>high)return null;
 const previous=isColumnRoot(root)?root.tiles[0].relativeGeometry.width*g.width:Math.floor(g.width/2);
 const split=Math.max(low,Math.min(high,requestedSplit===null?previous:requestedSplit));
 return {area,low,high,split,left:{x:g.x+8,y:area.y,width:split-12,height:area.height},right:{x:g.x+split+4,y:area.y,width:g.width-split-12,height:area.height}};
}
function updateColumnRoot(output,root,plan){
 if(!plan||!isColumnRoot(root)||columnUpdating.has(root))return;
 columnUpdating.add(root);
 try{
  const g=output.geometry,area=plan.area;
  const base=workspace.clientArea(KWin.MaximizeArea,output,workspace.currentDesktopForScreen(output));
  // Native padding is halved on interior edges, including our cropped top/bottom.
  const r={x:(g.x-base.x)/base.width,y:(area.y-4-base.y)/base.height,width:g.width/base.width,height:(area.height+8)/base.height};
  const shape=root.relativeGeometry;
  const verticalChanged=Math.abs(shape.y-r.y)>0.00001||Math.abs(shape.height-r.height)>0.00001;
  if(verticalChanged){root.layoutDirection=0;root.relativeGeometry=r;}
  for(const tile of root.tiles){
   const v=tile.relativeGeometry;
   if(Math.abs(v.y-r.y)>0.00001||Math.abs(v.height-r.height)>0.00001){
    root.layoutDirection=0;tile.relativeGeometry={x:v.x,y:r.y,width:v.width,height:r.height};
   }
  }
  root.layoutDirection=1;
  root.padding=8;
  root.tiles[0].minimumSize={width:Math.max(.001,plan.low/g.width),height:.01};
  root.tiles[1].minimumSize={width:Math.max(.001,(g.width-plan.high)/g.width),height:.01};
  const left=root.tiles[0].relativeGeometry;
  if(Math.abs(left.width*g.width-plan.split)>.01)root.tiles[0].relativeGeometry={x:left.x,y:left.y,width:plan.split/g.width,height:left.height};
 }finally{columnUpdating.delete(root);}
}
function ensureColumns(output,w,side,split){
 const plan=columnPlan(output,w,side,split);if(!plan)return null;
 const root=columnRoot(output);if(!root)return null;
 if(!isColumnRoot(root)){
  // The theme has intentionally disabled stock multi-cell layouts.
  let count=0;while(root.tiles.length&&count++<64)root.tiles[0].remove();
  root.objectName=COLUMN_LAYOUT;root.minimumSize={width:.01,height:.01};root.padding=8;
  root.split(1); // KWin::Tile::LayoutDirection::Horizontal
 }
 updateColumnRoot(output,root,plan);
 watchColumnRoot(output,root);
 return root.tiles[side];
}
function watchColumnRoot(output,root){
 if(!columnRoots.has(root)){
  columnRoots.add(root);
  for(const tile of root.tiles){
   tile.windowsChanged.connect(()=>{if(isColumnRoot(root)&&!columnUpdating.has(root))updateColumnRoot(output,root,columnPlan(output));sync();});
   tile.relativeGeometryChanged.connect(()=>{if(isColumnRoot(root)&&!columnUpdating.has(root))updateColumnRoot(output,root,columnPlan(output));});
   tile.windowGeometryChanged.connect(sync);
  }
 }
}
function refreshColumnAreas(){
 for(const output of workspace.screens){const root=columnRoot(output);if(isColumnRoot(root)){watchColumnRoot(output,root);updateColumnRoot(output,root,columnPlan(output));}}
}
function startColumnResize(w){
 const data=saved.get(key(w)),tile=w.tile;if(!data||!isColumnTile(tile))return;
 refreshColumnAreas();
 const record={root:tile.parent,side:tile===tile.parent.tiles[0]?0:1,output:w.output.name,desktop:String(workspace.currentDesktopForScreen(w.output).id),geometry:rect(w),restore:data.snapRestore,started:Date.now(),commits:null,query:false};
 data.columnResize=record;
 // The existing outline effect cancels the native resize, then untile/commits it.
 // Read its commit counter only at input/geometry events; never poll the effect.
 callDBus('org.kde.KWin','/SoftGraphiteResize','org.leonid.GraphiteOutline','State',reply=>{
  try{if(data.columnResize===record)record.commits=JSON.parse(reply).commits;}catch(e){}
 });
}
function finishColumnResize(w){
 const data=saved.get(key(w)),record=data?.columnResize;
 if(!record||record.query||isColumnTile(w.tile))return;
 if(w.move||expanded(w)||Date.now()-record.started>120000||w.output.name!==record.output||String(workspace.currentDesktopForScreen(w.output).id)!==record.desktop){data.columnResize=null;return;}
 record.query=true;
 callDBus('org.kde.KWin','/SoftGraphiteResize','org.leonid.GraphiteOutline','State',reply=>{
  if(data.columnResize!==record)return;
  record.query=false;
  try{
   const state=JSON.parse(reply);if(state.active)return;
   const g=rect(w),old=record.geometry;
   const same=(a,b)=>['x','y','width','height'].every(k=>Math.abs(a[k]-b[k])<1.1);
   data.columnResize=null;
   if(record.commits===null||state.commits<=record.commits||!same(state.original,old)||!same(state.target,g))return;
   // Only the inner vertical edge links the pair; an outer/corner resize detaches.
   if(Math.abs(g.y-old.y)>1||Math.abs(g.height-old.height)>1||Math.abs((record.side===0?g.x:g.x+g.width)-(record.side===0?old.x:old.x+old.width))>1)return;
   if(!isColumnRoot(record.root)||w.move||expanded(w))return;
   const output=w.output,plan=columnPlan(output,w,record.side);if(!plan)return;
   const edge=record.side===0?g.x+g.width+4:g.x-4;
   plan.split=Math.max(plan.low,Math.min(plan.high,edge-output.geometry.x));
   updateColumnRoot(output,record.root,plan);
   data.snapRestore=record.restore;record.root.tiles[record.side].manage(w);data.geometry=rect(w);sync();
  }catch(e){data.columnResize=null;}
 });
}
function detachColumn(w,remember=false){
 const tile=w.tile;if(!isColumnTile(tile))return;
 const data=saved.get(key(w));
 if(remember&&data){
  data.columnReturn={output:w.output.name,desktop:String(workspace.currentDesktopForScreen(w.output).id),side:tile===tile.parent.tiles[0]?'left':'right'};
  data.snapRestore=Object.assign({},data.snapRestore||data.geometry,{columnReturn:data.columnReturn});
 }
 tile.unmanage(w);
}
function restoreColumn(w){
 const data=saved.get(key(w)),back=data?.columnReturn;if(!back||expanded(w))return;
 data.columnReturn=null;
 if(data.snapRestore){data.snapRestore=Object.assign({},data.snapRestore);delete data.snapRestore.columnReturn;}
 if(w.output.name!==back.output||String(workspace.currentDesktopForScreen(w.output).id)!==back.desktop)return;
 const g=w.output.geometry,target=snapTarget(w,{x:back.side==='left'?g.x:g.x+g.width-1,y:g.y+g.height/2},true);
 if(target)snapWindow(w,target,data.snapRestore||data.geometry);
}

function snapTarget(w,p,preserveSplit=false){
 const output=workspace.screens.find(o=>within(p,o.geometry));if(!output)return null;
 const g=output.geometry,regions=pointerRegions.find(o=>o.name===output.name);
 const top=Math.max(32,(regions?Math.max(regions.left.height,regions.right.height):52)-8);
 const side=12;
 if(p.y<=g.y+top)return {name:output.name,kind:'full',rect:{x:g.x,y:g.y,width:g.width,height:g.height}};
 if(p.x<g.x+side||p.x>=g.x+g.width-side){
  const left=p.x<g.x+side,plan=columnPlan(output,w,left?0:1,preserveSplit?null:Math.floor(g.width/2));
  return plan?{name:output.name,kind:left?'left':'right',rect:left?plan.left:plan.right}:null;
 }
 return null;
}
function showPreview(target){
 const value=target?JSON.stringify(target):'';if(value===previewKey)return;previewKey=value;
 const r=target?.rect||{x:0,y:0,width:0,height:0};
 callDBus('org.leonid.SoftGraphite','/SoftGraphite','org.leonid.SoftGraphite','Preview',target?.name||'',target?.kind||'',r.x,r.y,r.width,r.height);
}
function updateSnapPreview(){if(activeDrag)showPreview(snapTarget(activeDrag.window,workspace.cursorPos));}
function snapWindow(w,target,restore){
 if(!w||!target||captureApp(w)||nativeMediaViewer(w)||!w.normalWindow)return;
 const data=saved.get(key(w));if(!data)return;
 if(w.tile)w.tile.unmanage(w);
 if(target.kind==='full'){const output=workspace.screens.find(o=>o.name===target.name);if(output&&w.output!==output)workspace.sendClientToScreen(w,output);data.geometry=restore;data.snapRestore=null;enter(w);}
 else{
  const output=workspace.screens.find(o=>o.name===target.name),side=target.kind==='left'?0:1;
  if(!output||!w.resizeable||w.onAllDesktops)return;
  const split=(side===0?target.rect.x+target.rect.width+4:target.rect.x-4)-output.geometry.x;
  const tile=ensureColumns(output,w,side,split);if(!tile)return;
  w.setMaximize(false,false);data.snapRestore=restore;data.columnReturn=null;
  if(w.output!==output)workspace.sendClientToScreen(w,output);
  tile.manage(w);data.geometry=rect(w);sync();
 }
}
function watch(w,newWindow=false) {
 if(String(w.resourceClass)==="soft-graphite-edge")return;
 const k=key(w);if(tracked.has(k))return;tracked.add(k);
 if(captureWindow(w)||nativeMediaViewer(w)){
  w.tagChanged.connect(sync);w.fullScreenChanged.connect(sync);w.hiddenChanged.connect(sync);w.minimizedChanged.connect(sync);
  w.outputChanged.connect(sync);w.frameGeometryChanged.connect(sync);w.stackingOrderChanged.connect(sync);return;
 }
 if(w.normalWindow&&!shellOverlay(w)) {
  if(newWindow&&captureApp(w)){w.fullScreen=false;w.setMaximize(false,false);}
  let starting=newWindow,centerApplying=false;
  let startupOutput=w.output;
  if(newWindow&&!w.transient&&!w.transientFor){
   const curPos=workspace.cursorPos;
   const screenUnderCursor=workspace.screens.find(s=>within(curPos,s.geometry));
   if(screenUnderCursor){
    startupOutput=screenUnderCursor;
    if(w.output&&w.output.name!==startupOutput.name){
     if(w.fullScreen||w.maximizeMode===3){
      w.fullScreen=false;
      w.setMaximize(false,false);
      workspace.sendClientToScreen(w,startupOutput);
      if(nativeMaxWindow(w))w.setMaximize(true,true);
      else w.fullScreen=true;
     } else {
      workspace.sendClientToScreen(w,startupOutput);
     }
    }
   }
  }
  const old=initialState.windows?.find(v=>v.id===k);
  saved.set(k,{geometry:(w.fullScreen||w.maximizeMode===3)?validRestore(w,old?.restore):isColumnTile(w.tile)?rect(w):floatingGeometry(startupOutput.geometry,rect(w)),entered:w.fullScreen&&!nativeMaxWindow(w),nativeMax:nativeMaxWindow(w)&&w.maximizeMode===3,snapRestore:old?.snapRestore||null,columnReturn:old?.columnReturn||old?.snapRestore?.columnReturn||null});
  const centerTimer=new QTimer();centerTimer.singleShot=true;centerTimer.interval=0;
  const startupEnd=new QTimer();startupEnd.singleShot=true;startupEnd.interval=500;
  startupEnd.timeout.connect(()=>{starting=false;centerTimer.stop();});
  function centerNewWindow(){
   if(!tracked.has(k)||!starting||centerApplying||!startupOutput||w.fullScreen||w.maximizeMode!==0||w.move||w.resize||isColumnTile(w.tile))return;
   if(w.output&&w.output.name!==startupOutput.name)workspace.sendClientToScreen(w,startupOutput);
   const screen=startupOutput.geometry,g=rect(w),data=saved.get(k);
   const target=floatingGeometry(screen,g);
   if(JSON.stringify(target)!==JSON.stringify(g)){centerApplying=true;if(data)data.geometry=target;w.frameGeometry=target;centerApplying=false;}
  }
  centerTimer.timeout.connect(centerNewWindow);
  if(starting){centerNewWindow();startupEnd.start();}
  let dragStart=null;
  w.interactiveMoveResizeStarted.connect(()=>{
   starting=false;startupEnd.stop();centerTimer.stop();
   if(w.resize){if(isColumnTile(w.tile))startColumnResize(w);else saved.get(k).snapRestore=null;return;}
   if(!w.move||w.fullScreen)return;
   saved.get(k).columnResize=null;
   const g=rect(w),p=workspace.cursorPos,data=saved.get(k),restore=data.snapRestore||g;
   detachColumn(w);
   dragStart={geometry:restore,initialGeometry:g,x:p.x,y:p.y};
   if(data.snapRestore){
    const ratio=Math.min(.95,Math.max(.05,(p.x-g.x)/g.width));
    w.frameGeometry={x:Math.round(p.x-ratio*restore.width),y:Math.round(p.y-Math.min(32,p.y-g.y)),width:restore.width,height:restore.height};
    data.snapRestore=null;
   }
   activeDrag={window:w};updateSnapPreview();
  });
  w.interactiveMoveResizeStepped.connect(updateSnapPreview);
  w.interactiveMoveResizeFinished.connect(()=>{
   const record=saved.get(k)?.columnResize;
   if(record&&isColumnTile(w.tile)&&w.tile.parent===record.root){
    const plan=columnPlan(w.output);if(plan){
     plan.split=Math.max(plan.low,Math.min(plan.high,(record.side===0?record.geometry.x+record.geometry.width+4:record.geometry.x-4)-w.output.geometry.x));
     updateColumnRoot(w.output,record.root,plan);
    }
   }
   const start=dragStart;dragStart=null;activeDrag=null;showPreview(null);
   if(!start||w.fullScreen||!w.fullScreenable)return;
   const p=workspace.cursorPos;
   if(Math.abs(p.x-start.x)+Math.abs(p.y-start.y)<8)return;
   if(JSON.stringify(rect(w))===JSON.stringify(start.initialGeometry))return;
   snapWindow(w,snapTarget(w,p),start.geometry);
  });
  const geometryTimer=new QTimer();geometryTimer.singleShot=true;geometryTimer.interval=80;
  geometryTimer.timeout.connect(()=>{
   const data=saved.get(k);
   if(data&&!w.move&&!w.resize&&!busy.has(k)&&!w.fullScreen&&w.maximizeMode===0&&!data.entered&&!data.restoring)data.geometry=rect(w);
   sync();
  });
  w.frameGeometryChanged.connect(()=>{if(starting&&!centerApplying)centerTimer.start();finishColumnResize(w);geometryTimer.start();sync();});
  const enterTimer=new QTimer();enterTimer.singleShot=true;enterTimer.interval=0;
  enterTimer.timeout.connect(()=>{if(tracked.has(k)&&!nativeMaxWindow(w)&&w.maximizeMode===3&&!w.fullScreen&&!saved.get(k)?.restoring)enter(w);});
  const restoreTimer=new QTimer();restoreTimer.singleShot=true;restoreTimer.interval=200;
  windowTimers.set(k,[centerTimer,startupEnd,geometryTimer,enterTimer,restoreTimer]);
  restoreTimer.timeout.connect(()=>{const data=saved.get(k);if(data){data.restoring=false;geometryTimer.start();sync();}});
  w.maximizedChanged.connect(()=>{
   const data=saved.get(k);
   if(w.maximizeMode===3)detachColumn(w,true);
   if(starting&&startupOutput&&w.output&&w.output.name!==startupOutput.name){
    w.setMaximize(false,false);
    workspace.sendClientToScreen(w,startupOutput);
    w.setMaximize(true,true);
   }
   if(nativeMaxWindow(w)){
    if(w.maximizeMode===3){data.nativeMax=true;data.entered=false;}
    else if(data.nativeMax&&!w.fullScreen&&!busy.has(k)){
     data.nativeMax=false;
     if(!w.move){data.restoring=true;restoreTimer.start();restoreColumn(w);}
    }
    sync();return;
   }
   if(w.maximizeMode===3&&!w.fullScreen&&!busy.has(k)&&!data?.restoring)enterTimer.start();
  });
  w.fullScreenChanged.connect(()=>{
   const data=saved.get(k);
   if(w.fullScreen)detachColumn(w,true);
   if(!w.fullScreen&&data?.entered&&!busy.has(k)) {
    busy.add(k);data.entered=false;data.restoring=true;enterTimer.stop();w.setMaximize(false,false);w.frameGeometry=data.geometry;busy.delete(k);
    restoreTimer.start();
   }
   restoreColumn(w);sync();
  });
  w.captionChanged.connect(sync);w.minimizedChanged.connect(sync);w.outputChanged.connect(()=>checkColumnScope(w));w.desktopsChanged.connect(()=>checkColumnScope(w));
  w.hiddenChanged.connect(sync);w.stackingOrderChanged.connect(sync);
  if(w.maximizeMode===3&&!w.fullScreen)enterTimer.start();
 } else if(w.dock) { w.frameGeometryChanged.connect(sync); }
}
// Only region transitions cross D-Bus; no cursor polling, JSON parsing or disk writes per motion.
function within(p,r,extra=0){return r.width>0&&p.x>=r.x&&p.x<r.x+r.width&&p.y>=r.y&&p.y<r.y+r.height+extra;}
function pointerReport(){
 const raw=workspace.cursorPos;const p={x:Math.floor(raw.x),y:Math.floor(raw.y)};
 let signature='';
 for(const s of pointerRegions){
  const on=s.full&&within(p,s),x=p.x-s.x,y=p.y-s.y;
  const left=on&&x<16&&y<12,right=on&&x>=s.width-32&&y<24;
  const dock=s.dock;
  signature+=[s.name,left,on&&within(p,s.left,16),right,on&&within(p,s.right,16),on&&y>=s.height-12&&p.x>=dock.x+10&&p.x<dock.x+dock.width-10,on&&within(p,dock)].join(':');
 }
 if(signature===pointerKey)return;pointerKey=signature;
 callDBus('org.leonid.SoftGraphite','/SoftGraphite','org.leonid.SoftGraphite','Pointer',p.x,p.y);
}
workspace.cursorPosChanged.connect(()=>{updateSnapPreview();pointerReport();});
workspace.windowList().forEach(w=>watch(w,false));pointerReport();
workspace.windowAdded.connect(w=>{watch(w,true);sync();});
workspace.windowRemoved.connect(w=>{if(activeDrag?.window===w){activeDrag=null;showPreview(null);}const k=key(w);tracked.delete(k);saved.delete(k);busy.delete(k);
 for(const timer of windowTimers.get(k)||[]){timer.stop();}
 windowTimers.delete(k);sync();});
workspace.windowActivated.connect(report);
workspace.currentDesktopChanged.connect(sync);
workspace.screensChanged.connect(sync);
registerShortcut('Soft Graphite: Toggle fullscreen','Мягкий графит: полный экран / вернуть размер','Meta+Ctrl+F',()=>{const w=workspace.activeWindow;if(w&&expanded(w))leave(w);else enter(w);});
registerShortcut('Soft Graphite: Fullscreen','Мягкий графит: весь экран','Meta+Up',()=>enter(workspace.activeWindow));
registerShortcut('Soft Graphite: Tile left','Мягкий графит: левая половина','Meta+Left',()=>{const w=workspace.activeWindow;if(w&&!w.fullScreen)snapWindow(w,snapTarget(w,{x:w.output.geometry.x,y:w.output.geometry.y+200}),saved.get(key(w))?.snapRestore||rect(w));});
registerShortcut('Soft Graphite: Tile right','Мягкий графит: правая половина','Meta+Right',()=>{const w=workspace.activeWindow;if(w&&!w.fullScreen)snapWindow(w,snapTarget(w,{x:w.output.geometry.x+w.output.geometry.width-1,y:w.output.geometry.y+200}),saved.get(key(w))?.snapRestore||rect(w));});
registerUserActionsMenu(w=>({text:'Мягкий графит',items:[{text:expanded(w)?'Вернуть размер':'На весь экран',triggered:()=>{if(expanded(w))leave(w);else enter(w);}}]}));
sync();

// Remove the former Shift-drag custom columns as well as electric corner tiling.
function clearOtherLayouts(){for(const screen of workspace.screens){const root=workspace.rootTile(screen,workspace.currentDesktopForScreen(screen));if(root&&!isColumnRoot(root)){let count=0;while(root.tiles.length&&count++<64)root.tiles[0].remove();}}}
clearOtherLayouts();workspace.screensChanged.connect(clearOtherLayouts);workspace.currentDesktopChanged.connect(clearOtherLayouts);
