// Run: node tools/test-linked-resize.cjs [effect-main.js]
'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const source=fs.readFileSync(process.argv[2]||path.join(__dirname,'../kwin/effects/softgraphite-resize/contents/code/main.js'),'utf8');
function signal(){const f=[];return {connect:fn=>f.push(fn),emit:(...a)=>f.forEach(fn=>fn(...a))};}
function scenario({gap=8,screen='one',cancel=false,elapsed=20}={}){
 let now=1000;const animations=[],effects={stackingOrder:[],hasActiveFullScreenEffect:false,windowAdded:signal(),windowClosed:signal(),windowDataChanged:signal()};
 function window(x,width,name){
  const w={normalWindow:true,windowClass:'test',caption:name,geometry:{x,y:50,width,height:900},screen:{name:'one'},visible:true,onCurrentDesktop:true,minimized:false,move:false,resize:false,fullScreen:false,flag:false,data(){return this.flag;}};
  for(const k of ['windowMaximizedStateAboutToChange','windowMaximizedStateChanged','windowFullScreenChanged','windowFrameGeometryChanged','windowStartUserMovedResized','windowFinishUserMovedResized','minimizedChanged'])w[k]=signal();return w;
 }
 const a=window(8,948,'left'),b=window(956+gap,948,'right');b.screen.name=screen;effects.stackingOrder=[a,b];
 vm.runInNewContext(source,{effects,effect:{animationEnded:signal()},animationTime:t=>t,Date:{now:()=>now},QEasingCurve:{OutCubic:3},Effect:{Size:1,Position:2},animate:o=>{animations.push(o);return [animations.length];},cancel:()=>{},Promise});
 a.resize=true;a.windowStartUserMovedResized.emit();a.resize=false;
 if(cancel)return {animations,a,b};
 a.flag=true;effects.windowDataChanged.emit(a,120901);
 let old=a.geometry;a.geometry={...old,width:1048};a.windowFrameGeometryChanged.emit(a,old);
 now+=elapsed;old=b.geometry;b.geometry={...old,x:old.x+100,width:848};b.windowFrameGeometryChanged.emit(b,old);
 return {animations,a,b};
}
let r=scenario();assert.equal(r.animations.length,2);assert.equal(r.animations[0].duration,240);assert.equal(r.animations[1].duration,220);assert.equal(r.b.graphiteResize.motion.end,r.a.graphiteResize.motion.end);assert.equal(r.animations[1].curve,3);
for(const opts of [{gap:20},{screen:'two'},{elapsed:300}])assert.equal(scenario(opts).animations.length,1);
assert.equal(scenario({cancel:true}).animations.length,0);
console.log('PASS: paired windows share the 240ms OutCubic endpoint; other screens, unrelated geometry, stale commits and cancellation do not animate peers.');
