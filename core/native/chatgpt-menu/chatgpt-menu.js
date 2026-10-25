'use strict';
// Adapter for the SHA-256 reviewed ChatGPT 26.1002.52244 Electron menu model.
// One small, event-driven DBus exporter per main window, no timers in idle.
const {app, BrowserWindow, Menu, webContents}=require('electron');
const {spawn}=require('node:child_process');
const path=require('node:path');
const tracked=new Map();
const css='[role="menubar"]:has(#application-menu-trigger-file-menu){display:none!important}';
function attach(win){
 if(tracked.has(win)||win.isDestroyed()||win.getParentWindow()||!win.isResizable()||!win.isMinimizable())return;
 const state={child:null,css:null,ready:false,ids:new Map(),last:null,cssVersion:0,buffer:'',closed:false};tracked.set(win,state);
 function snapshot(items){return items.map(item=>{
  state.ids.set(item.commandId,item);
  const v={id:item.commandId,label:item.label,enabled:item.enabled,visible:item.visible,type:item.type,checked:item.checked,accelerator:item.accelerator};
  if(item.submenu)v.children=snapshot(item.submenu.items);
  return v;
 });}
 function update(){
  if(win.isDestroyed()||!state.child||state.closed)return;
  const menu=Menu.getApplicationMenu();if(!menu)return;
  state.ids.clear();const data=JSON.stringify({items:snapshot(menu.items)});
  if(data!==state.last){state.last=data;state.child.stdin.write(data+'\n');}
 }
 async function visibility(ready){
  const version=++state.cssVersion;state.ready=ready;if(win.isDestroyed())return;
  if(state.css){const key=state.css;state.css=null;await win.webContents.removeInsertedCSS(key).catch(()=>{});}
  if(ready&&!win.isDestroyed()){
   const key=await win.webContents.insertCSS(css).catch(()=>null);
   if(version===state.cssVersion)state.css=key;
   else if(key&&!win.isDestroyed())await win.webContents.removeInsertedCSS(key).catch(()=>{});
  }
 }
 const child=spawn(path.join(__dirname,'menu-bridge'),[String(win.getNativeWindowHandle().readUInt32LE(0))],{stdio:['pipe','pipe','ignore'],env:process.env});state.child=child;
 child.stdin.on('error',()=>{});
 child.stdout.on('data',data=>{state.buffer+=data;let end;while((end=state.buffer.indexOf('\n'))>=0){const line=state.buffer.slice(0,end);state.buffer=state.buffer.slice(end+1);let msg;try{msg=JSON.parse(line);}catch{continue;}
  if('ready'in msg)visibility(msg.ready);
  if('refresh'in msg){const item=state.ids.get(msg.refresh);item?.submenu?.emit('menu-will-show');update();}
  if('click'in msg){const item=state.ids.get(msg.click);if(!item||!item.enabled||!item.visible||win.isDestroyed())continue;
   const focused=webContents.getFocusedWebContents();const target=focused&&!focused.isDestroyed()&&(focused===win.webContents||focused.hostWebContents===win.webContents)?focused:win.webContents;
   win.focus();Reflect.apply(item.click,item,[{triggeredByAccelerator:false},win,target]);update();
  }
 }});
 child.on('error',()=>{state.closed=true;visibility(false);});
 child.on('exit',()=>{state.closed=true;visibility(false);});
 win.on('focus',update);
 win.webContents.on('did-finish-load',()=>{update();if(state.ready)visibility(true);});
 win.on('closed',()=>{state.closed=true;child.stdin.end();tracked.delete(win);});
 state.update=update;update();
}
exports.install=()=>{
 if(process.platform!=='linux'||app.__softGraphiteMenu)return;app.__softGraphiteMenu=true;
 // Preserve application-owned callbacks and menu rebuilding; inspect current items
 // after setApplicationMenu, window focus, or the native AboutToShow request.
 const original=Menu.setApplicationMenu;
 Menu.setApplicationMenu=function(menu){const result=Reflect.apply(original,this,[menu]);for(const s of tracked.values())s.update?.();return result;};
 app.on('browser-window-created',(_event,win)=>win.once('ready-to-show',()=>attach(win)));
 app.whenReady().then(()=>BrowserWindow.getAllWindows().filter(w=>w.isVisible()).forEach(attach));
};
