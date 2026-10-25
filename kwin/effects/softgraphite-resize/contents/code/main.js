/*
 * Based on KDE's fullscreen and maximize effects.
 * SPDX-FileCopyrightText: 2012 Martin Gräßlin <mgraesslin@kde.org>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
'use strict';
// Use the compositor's normal blur policy for transformed windows. Forced
// decoration blur can shrink to a zero-sized framebuffer during large resizes.
const duration = w => animationTime(w.data(120901) ? 240 : 320);
const copy = r => ({x:r.x,y:r.y,width:r.width,height:r.height});
const equal = (a,b) => a.x===b.x&&a.y===b.y&&a.width===b.width&&a.height===b.height;
const center = r => ({value1:r.x+r.width/2,value2:r.y+r.height/2});
const size = r => ({value1:r.width,value2:r.height});
function stop(w) {
 const s=w.graphiteResize;if(!s)return;
 if(s.ids){cancel(s.ids);s.ids=null;}
 s.motion=null;s.pending=null;s.previous=null;
}
function visual(m,now) {
 const t=Math.min(1,Math.max(0,(now-m.start)/m.duration)),p=1-Math.pow(1-t,3),r={};
 for(const k of ['x','y','width','height'])r[k]=m.from[k]+(m.to[k]-m.from[k])*p;
 return r;
}
function transition(w,from) {
 const s=w.graphiteResize,to=copy(w.geometry),now=Date.now();
 if(!w.visible||w.minimized||w.resize||effects.hasActiveFullScreenEffect){stop(w);return;}
 if(s.motion&&now<s.motion.end){
  // State and geometry signals can describe the same destination.
  if(equal(s.motion.to,to)){s.pending=null;return;}
  // Client configure acknowledgements may arrive separately. Continue the same
  // visual path to the final rectangle without a second resize animation.
  from=visual(s.motion,now);
 } else s.motion=null;
 if(equal(from,to)){s.pending=null;return;}
 const remaining=s.motion?Math.max(1,s.motion.end-now):duration(w);
 if(s.ids){cancel(s.ids);s.ids=null;}
 s.pending=null;s.motion={from,to,start:now,duration:remaining,end:now+remaining};
 s.ids=animate({window:w,duration:remaining,curve:QEasingCurve.OutCubic,keepAlive:false,animations:[
  {type:Effect.Size,from:size(from),to:size(to)},
  {type:Effect.Position,from:center(from),to:center(to)}
 ]});
}
function manage(w) {
 if(!w.normalWindow||String(w.windowClass).toLowerCase().includes('spectacle'))return;
 const s={last:copy(w.geometry),previous:null,full:w.fullScreen,ids:null,motion:null,pending:null};w.graphiteResize=s;
 w.windowMaximizedStateAboutToChange.connect(()=>{if(!s.pending)s.pending=copy(w.geometry);});
 w.windowMaximizedStateChanged.connect(()=>{if(s.pending)transition(w,s.pending);});
 w.windowFullScreenChanged.connect(()=>{
  if(s.full===w.fullScreen)return;s.full=w.fullScreen;
  // Wayland may report geometry just before the fullscreen state in one
  // commit. Only reuse that commit's rectangle, never an old maximize/resize.
  const from=s.pending||(!equal(s.last,w.geometry)?s.last:s.previous||copy(w.geometry));
  if(!equal(from,w.geometry))transition(w,from);
  else if(!s.motion)s.pending=copy(w.geometry);
 });
 w.windowFrameGeometryChanged.connect((window,old)=>{
  const changedFull=s.full!==w.fullScreen;
  s.last=copy(w.geometry);
  if(w.move||w.resize){stop(w);s.full=w.fullScreen;return;}
  const previous=copy(old);s.previous=previous;
  // Clear at the end of this event-loop turn. No timer or per-frame polling.
  Promise.resolve().then(()=>{if(s.previous===previous)s.previous=null;});
  if(w.data(120901)||s.pending||changedFull||(s.motion&&Date.now()<s.motion.end)){
   s.full=w.fullScreen;transition(w,s.pending||copy(old));
  }
 });
 w.windowStartUserMovedResized.connect(()=>stop(w));
 w.minimizedChanged.connect(()=>stop(w));
}
effect.animationEnded.connect(w=>{
 const s=w.graphiteResize;if(!s)return;
 // Both attributes finish together. A later native configure starts cleanly.
 if(s.motion&&Date.now()+20>=s.motion.end){s.ids=null;s.motion=null;}
});
effects.windowAdded.connect(manage);
for(const w of effects.stackingOrder)manage(w);
