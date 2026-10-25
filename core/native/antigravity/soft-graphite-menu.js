'use strict';
// Adapter for the reviewed Antigravity 2.19.1 renderer contract.
const {ipcMain, BrowserWindow, Menu}=require('electron');
let installed=false;
exports.install=()=>{
 if(installed||process.platform!=='linux')return;
 installed=true;
 ipcMain.handle('soft-graphite:menu', (event, groups)=>{
  const win=BrowserWindow.fromWebContents(event.sender);
  if(!win||event.sender!==win.webContents||event.senderFrame!==event.sender.mainFrame)return false;
  if(!Array.isArray(groups)||groups.length<2||groups.length>12)return false;
  const valid=groups.every(g=>typeof g.title==='string'&&g.title.length<120&&Array.isArray(g.items)&&g.items.length<=60&&g.items.every(i=>typeof i.label==='string'&&i.label.length<240));
  if(!valid)return false;
  const template=groups.map((group,g)=>({label:group.title,submenu:group.items.map((item,i)=>({
   label:item.label,enabled:!item.disabled,
   click:()=>{if(win.isDestroyed())return;win.focus();win.webContents.send('soft-graphite:menu-action',{group:g,index:i,label:item.label});}
  }))}));
  // Keep native editing commands, also available in the original Electron menu.
  if(!template.some(i=>i.label==='Edit'))template.splice(Math.min(2,template.length),0,{role:'editMenu'});
  const menu=Menu.buildFromTemplate(template);win.setMenu(menu);
  // Only hide the custom row when Electron has handed its menu to the desktop.
  const exported=!win.isMenuBarVisible();
  if(!exported)win.setMenu(Menu.getApplicationMenu());
  return exported;
 });
};
