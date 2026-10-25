function graphiteAntigravityMenu(){
 const api=window.softGraphiteMenu;if(!api||window.__softGraphiteMenuInstalled)return;
 window.__softGraphiteMenuInstalled=true;
 let bar=null,hiddenRow=null,lastSignature='',queued=false,ready=false;
 const selector='[data-testid="title-menu-bar"]';
 function propsFor(button){
  const name=Object.keys(button).find(k=>k.startsWith('__reactFiber$'));
  let f=name?button[name]:null;if(!f)return null;
  let root=f;while(root.return)root=root.return;
  if(root.stateNode?.current!==root&&f.alternate)f=f.alternate;
  for(let n=0;f&&n<18;f=f.return,n++){
   const p=f.memoizedProps;
   if(p&&typeof p.title==='string'&&Array.isArray(p.options))return p;
  }
  return null;
 }
 function groups(){
  if(!bar?.isConnected)return null;
  const result=Array.from(bar.querySelectorAll('[data-testid="title-menu-bar-item"]')).map(propsFor);
  return result.length>=2&&result.every(Boolean)?result:null;
 }
 function restore(){if(hiddenRow)hiddenRow.style.removeProperty('display');ready=false;lastSignature='';}
 async function publish(){
  queued=false;
  if(!bar?.isConnected){restore();observe();return;}
  const data=groups();if(!data){restore();return;}
  const model=data.map(g=>({title:g.title,items:g.options.map(i=>({label:i.label,disabled:!!i.nonSelectable}))}));
  const signature=JSON.stringify(model);if(signature===lastSignature)return;
  const target=bar;
  try{
   const accepted=await api.publish(model);
   if(target!==bar||!target.isConnected)return;
   if(accepted){hiddenRow=bar.parentElement;hiddenRow.style.display='none';ready=true;lastSignature=signature;}
   else restore();
  }catch{restore();}
 }
 function schedule(){if(!queued){queued=true;queueMicrotask(publish);}}
 const observer=new MutationObserver(schedule);
 function observe(){
  observer.disconnect();bar=document.querySelector(selector);
  if(!bar){observer.observe(document.body||document.documentElement,{childList:true,subtree:true});return;}
  // Watch only the menu subtree and ancestor child lists, not message/content updates.
  observer.observe(bar,{childList:true,subtree:true,characterData:true});
  for(let p=bar.parentElement;p;p=p.parentElement)observer.observe(p,{childList:true});
  schedule();
 }
 api.onAction(({group,index,label})=>{
  const current=groups(),item=current?.[group]?.options?.[index];
  if(ready&&item?.label===label&&!item.nonSelectable&&typeof item.onClick==='function')item.onClick();
  else{restore();schedule();}
 });
 observe();
}
graphiteAntigravityMenu();
