'use strict';
// No KWin loading, locking, or authentication. Check service-surface exclusions.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2]||path.join(__dirname,'../kwin/scripts/soft-graphite-fullscreen/contents/code/main.js'),'utf8');
const guard=source.match(/function shellOverlay\(w\)\{[^\n]+\}/)[0];
const ctx=vm.createContext({});vm.runInContext(guard,ctx);
const ordinary={layer:2,moveable:true,resizeable:true,resourceClass:'normal-app'};
for(const w of [{...ordinary,layer:9},{...ordinary,layer:5,moveable:false,resizeable:false},{...ordinary,moveable:false,resizeable:false,resourceClass:''},{...ordinary,resourceClass:'kscreenlocker_greet'},{...ordinary,resourceClass:'plasma-login-greeter'}])assert.equal(ctx.shellOverlay(w),true);
for(const w of [ordinary,{...ordinary,resizeable:false},{...ordinary,resourceClass:''},{...ordinary,moveable:false,resizeable:false,fullScreen:true},{...ordinary,moveable:false,resizeable:false,maximizeMode:3},{layer:2,resourceClass:'initializing-client'}])assert.equal(ctx.shellOverlay(w),false);
const start=source.indexOf('function centerNewWindow(){'),end=source.indexOf('centerTimer.timeout.connect(centerNewWindow)',start);assert(start>=0&&end>start);
let touched=0;
Object.assign(ctx,{tracked:new Set(['test']),k:'test',starting:true,centerApplying:false,startupOutput:{geometry:{x:0,y:0,width:1920,height:1080}},isColumnTile:()=>false,saved:new Map(),rect:()=>{++touched;return {x:0,y:0,width:1920,height:1080};},floatingGeometry:()=>({x:360,y:140,width:1200,height:800}),workspace:{}});
ctx.w={...ordinary,fullScreen:false,maximizeMode:0,move:false,resize:false,output:ctx.startupOutput};
vm.runInContext(source.slice(start,end),ctx);ctx.centerNewWindow();assert.equal(touched,1);
// Role can settle after windowAdded but before the deferred center callback.
touched=0;ctx.w.moveable=false;ctx.w.resizeable=false;ctx.centerNewWindow();assert.equal(touched,0);
console.log('PASS: fixed service surfaces and lock/login classes are excluded; movable dialogs and late-class clients remain eligible; deferred centering rechecks role.');
// Fullscreen clients may report the same fixed capabilities as layer-shell.
// They must still reach the fullscreen panel controller, for F11 and native-max.
const reportStart=source.indexOf('function report() {'),reportEnd=source.indexOf('function enter(w)',reportStart);
vm.runInContext(source.match(/function nativeMaxWindow\(w\)\{[^\n]+\}/)[0]+'\n'+source.match(/function expanded\(w\)\{[^\n]+\}/)[0],ctx);
let state;
const screen={name:'test',geometry:{x:0,y:0,width:1920,height:1080}},video={...ordinary,normalWindow:true,id:'video',resourceClass:'google-chrome',moveable:false,resizeable:false,fullScreen:true,maximizeMode:0,caption:'Test video',output:screen,desktops:[{id:'desk'}],frameGeometry:screen.geometry};
Object.assign(ctx,{previous:'',captureWindow:()=>false,rect:w=>w.frameGeometry,key:w=>w.id,callDBus:(...args)=>{state=JSON.parse(args[4]);},pointerRefresh:{start:()=>{}},receiveRegions:()=>{},workspace:{screens:[screen],windowList:()=>[video],stackingOrder:[video],currentDesktopForScreen:()=>({id:'desk'})}});
vm.runInContext(source.slice(reportStart,reportEnd),ctx);
for(const app of ['google-chrome','firefox','chromium','yandex-browser','other-browser']){
 video.resourceClass=app;
 for(const full of [true,false]){
  if(!full&&!ctx.nativeMaxWindow(video))continue;
  video.fullScreen=full;video.maximizeMode=full?0:3;ctx.previous='';ctx.report();assert.equal(state.screens[0].fullscreen,'video');assert.equal(state.windows[0].expanded,true);
 }
}
console.log('PASS: fullscreen and native-max clients with fixed capabilities remain in the panel controller report.');
