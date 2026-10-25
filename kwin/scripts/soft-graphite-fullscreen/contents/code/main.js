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
function receiveRegions(data){try{pointerRegions=JSON.parse(data);pointerKey='';pointerReport();}catch(e){}}
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
 const state={screens,windows:all.filter(w=>(w.normalWindow&&!shellOverlay(w)) || w.dock).map(w=>({id:key(w),app:String(w.resourceClass),caption:w.caption,output:w.output.name,fullscreen:w.fullScreen,expanded:expanded(w),maximize:w.maximizeMode,minimized:w.minimized,active:w===workspace.activeWindow,keepAbove:w.keepAbove,geometry:rect(w),restore:saved.get(key(w))?.geometry,snapRestore:saved.get(key(w))?.snapRestore}))};
 const data=JSON.stringify(state);
 if(data===previous)return;
 previous=data;
 callDBus('org.leonid.SoftGraphite','/SoftGraphite','org.leonid.SoftGraphite','Update',data,receiveRegions);
 pointerRefresh.start();
}
function enter(w) {
 if(!w || captureApp(w) || nativeMediaViewer(w) || !w.normalWindow || !w.fullScreenable || busy.has(key(w)))return;
 const k=key(w);busy.add(k);
 let data=saved.get(k)||{geometry:rect(w),entered:false};data.entered=!nativeMaxWindow(w);saved.set(k,data);
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
function snapTarget(w,p){
 const output=workspace.screens.find(o=>within(p,o.geometry));if(!output)return null;
 const g=output.geometry,regions=pointerRegions.find(o=>o.name===output.name);
 const top=Math.max(32,(regions?Math.max(regions.left.height,regions.right.height):52)-8);
 const side=12;
 if(p.y<=g.y+top)return {name:output.name,kind:'full',rect:{x:g.x,y:g.y,width:g.width,height:g.height}};
 if(p.x<g.x+side||p.x>=g.x+g.width-side){
  const left=p.x<g.x+side,width=Math.floor(g.width/2);
  return {name:output.name,kind:left?'left':'right',rect:{x:g.x+(left?0:width),y:g.y+top,width:left?width:g.width-width,height:g.height-top}};
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
 else{w.setMaximize(false,false);data.snapRestore=restore;data.geometry=target.rect;w.frameGeometry=target.rect;sync();}
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
  saved.set(k,{geometry:(w.fullScreen||w.maximizeMode===3)?validRestore(w,old?.restore):floatingGeometry(startupOutput.geometry,rect(w)),entered:w.fullScreen&&!nativeMaxWindow(w),nativeMax:nativeMaxWindow(w)&&w.maximizeMode===3,snapRestore:old?.snapRestore||null});
  const centerTimer=new QTimer();centerTimer.singleShot=true;centerTimer.interval=0;
  const startupEnd=new QTimer();startupEnd.singleShot=true;startupEnd.interval=500;
  startupEnd.timeout.connect(()=>{starting=false;centerTimer.stop();});
  function centerNewWindow(){
   if(!tracked.has(k)||!starting||centerApplying||!startupOutput||w.fullScreen||w.maximizeMode!==0||w.move||w.resize)return;
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
   if(w.resize){saved.get(k).snapRestore=null;return;}
   if(!w.move||w.fullScreen)return;
   const g=rect(w),p=workspace.cursorPos,data=saved.get(k),restore=data.snapRestore||g;
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
  w.frameGeometryChanged.connect(()=>{if(starting&&!centerApplying)centerTimer.start();geometryTimer.start();sync();});
  const enterTimer=new QTimer();enterTimer.singleShot=true;enterTimer.interval=0;
  enterTimer.timeout.connect(()=>{if(tracked.has(k)&&!nativeMaxWindow(w)&&w.maximizeMode===3&&!w.fullScreen&&!saved.get(k)?.restoring)enter(w);});
  const restoreTimer=new QTimer();restoreTimer.singleShot=true;restoreTimer.interval=200;
  windowTimers.set(k,[centerTimer,startupEnd,geometryTimer,enterTimer,restoreTimer]);
  restoreTimer.timeout.connect(()=>{const data=saved.get(k);if(data){data.restoring=false;geometryTimer.start();sync();}});
  w.maximizedChanged.connect(()=>{
   const data=saved.get(k);
   if(starting&&startupOutput&&w.output&&w.output.name!==startupOutput.name){
    w.setMaximize(false,false);
    workspace.sendClientToScreen(w,startupOutput);
    w.setMaximize(true,true);
   }
   if(nativeMaxWindow(w)){
    if(w.maximizeMode===3){data.nativeMax=true;data.entered=false;}
    else if(data.nativeMax&&!w.fullScreen&&!busy.has(k)){
     data.nativeMax=false;
     if(!w.move){data.restoring=true;restoreTimer.start();}
    }
    sync();return;
   }
   if(w.maximizeMode===3&&!w.fullScreen&&!busy.has(k)&&!data?.restoring)enterTimer.start();
  });
  w.fullScreenChanged.connect(()=>{
   const data=saved.get(k);
   if(!w.fullScreen&&data?.entered&&!busy.has(k)) {
    busy.add(k);data.entered=false;data.restoring=true;enterTimer.stop();w.setMaximize(false,false);w.frameGeometry=data.geometry;busy.delete(k);
    restoreTimer.start();
   }
   sync();
  });
  w.captionChanged.connect(sync);w.minimizedChanged.connect(sync);w.outputChanged.connect(sync);w.desktopsChanged.connect(sync);
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
function clearOtherLayouts(){for(const screen of workspace.screens){const root=workspace.rootTile(screen,workspace.currentDesktopForScreen(screen));if(root){let count=0;while(root.tiles.length&&count++<64)root.tiles[0].remove();}}}
clearOtherLayouts();workspace.screensChanged.connect(clearOtherLayouts);workspace.currentDesktopChanged.connect(clearOtherLayouts);
