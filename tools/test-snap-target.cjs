'use strict';
// Pure geometry regression test; never loads a script into KWin.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2] || path.join(__dirname, '../kwin/scripts/soft-graphite-fullscreen/contents/code/main.js'), 'utf8');
const start = source.indexOf('function snapTarget(');
const end = source.indexOf('function updateSnapPreview(', start);
assert(start >= 0 && end > start);
let calls = [];
const context = vm.createContext({workspace: {screens: []}, pointerRegions: [], previewKey: '',
  within: (p, r) => r.width > 0 && p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height,
  callDBus: (...args) => calls.push(args)});
vm.runInContext(source.slice(start, end), context);
let count = 0;
function check(g, dock, bottom) {
  context.workspace.screens = [{name: 'test', geometry: g}];
  context.pointerRegions = dock === undefined ? [] : [{name: 'test', left: {y: g.y, width: 200, height: 52}, right: {y: g.y, width: 200, height: 52}, dock}];
  for (const left of [true, false]) {
    const p = {x: left ? g.x : g.x + g.width - 1, y: g.y + 200};
    const target = context.snapTarget(null, p), r = target.rect;
    assert.equal(target.kind, left ? 'left' : 'right');
    assert.equal(r.y, g.y + 50);
    assert.equal(r.y + r.height, bottom);
    assert.equal(r.x, g.x + (left ? 0 : Math.floor(g.width / 2)));
    assert.equal(r.width, left ? Math.floor(g.width / 2) : g.width - Math.floor(g.width / 2));
    assert(r.height > 0);
    calls = []; context.previewKey = ''; context.showPreview(target);
    assert.deepEqual(calls[0].slice(-4), [r.x, r.y, r.width, r.height]);
    ++count;
  }
  const full = context.snapTarget(null, {x: g.x + 50, y: g.y});
  assert.equal(full.kind, 'full');
  assert.equal(JSON.stringify(full.rect), JSON.stringify(g));
  assert.equal(context.snapTarget(null, {x: g.x + g.width / 2, y: g.y + 200}), null);
}
check({x: 1536, y: 0, width: 1920, height: 1080}, {x: 2196, y: 1000, width: 600, height: 80}, 1002);
check({x: 0, y: 108, width: 1536, height: 864}, {x: 468, y: 892, width: 600, height: 80}, 894);
check({x: -1707, y: -200, width: 1707, height: 960}, {x: -1200, y: 640, width: 600, height: 120}, 642);
check({x: 0, y: 0, width: 1280, height: 720}, {x: 300, y: 600.5, width: 600, height: 100}, 602.5);
check({x: 600, y: 800, width: 1280, height: 720}, undefined, 1442);
for (const dock of [null, {}, {width: 0, height: 80, y: 600}, {width: 600, height: 0, y: 600}, {width: 600, height: 80, y: NaN}, {width: 600, height: 80, y: 10}, {width: 600, height: 80, y: 2000}]) {
  check({x: 0, y: 0, width: 1280, height: 720}, dock, 642);
}
context.workspace.screens = [];
assert.equal(context.snapTarget(null, {x: 0, y: 0}), null);
console.log(`PASS: ${count} left/right targets and matching previews; fullscreen, fallback, offsets, fractional logical geometry, odd widths.`);
