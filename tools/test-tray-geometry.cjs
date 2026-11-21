'use strict';
// Regression: a network height must never become the opening height of audio.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'../plasmoids/org.leonid.softgraphite.tray/contents/ui/ExpandedRepresentation.qml'),'utf8');
const start=source.indexOf('function rememberNaturalHeight('),end=source.indexOf('\n    }',start);
assert(start>=0&&end>start);
const state={naturalHeights:{},naturalHeightKey:'org.kde.plasma.networkmanagement',stableListViewport:true};
vm.createContext(state);vm.runInContext(source.slice(start,end+6),state);
state.rememberNaturalHeight(210);
assert.equal(state.naturalHeights[state.naturalHeightKey],undefined); // initial placeholder is not the settled size
state.rememberNaturalHeight(531);state.rememberNaturalHeight(575);state.rememberNaturalHeight(487);
assert.equal(state.naturalHeights[state.naturalHeightKey],531); // a changing list scrolls inside a stable viewport
state.naturalHeightKey='org.kde.plasma.volume';
assert.equal(state.naturalHeights[state.naturalHeightKey],undefined);
state.rememberNaturalHeight(370);state.rememberNaturalHeight(531);
assert.equal(state.naturalHeights[state.naturalHeightKey],370);
assert.equal(state.naturalHeights['org.kde.plasma.networkmanagement'],531);
state.stableListViewport=false;state.naturalHeightKey='other-applet';
state.rememberNaturalHeight(250);state.rememberNaturalHeight(400);
assert.equal(state.naturalHeights[state.naturalHeightKey],400); // other tray applets retain dynamic sizing
console.log('PASS: per-applet heights; initial placeholders skipped; network/audio viewport stable; other applets can resize.');
