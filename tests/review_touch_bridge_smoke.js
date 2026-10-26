const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const swift = fs.readFileSync('ios/AnkiPad/ReviewerWebView.swift', 'utf8');
const source = swift.match(/static let reviewTapScript = #"""\n([\s\S]*?)\n\s*"""#/)[1];
const listeners = {}, timers = new Map(), delivered = [];
let nextTimer = 0, collapsed = true;
class Element {
  constructor(interactive = false) { this.interactive = interactive; }
  matches() { return this.interactive; }
}
const context = {
  Element, innerWidth: 1000, innerHeight: 500,
  document: {addEventListener(name, handler) { listeners[name] = handler; }},
  getSelection: () => ({isCollapsed: collapsed}),
  clearTimeout: id => timers.delete(id),
  setTimeout: callback => { timers.set(++nextTimer, callback); return nextTimer; },
  window: {__ankiPadTapToken: 'first', webkit: {messageHandlers: {reviewTap: {postMessage: body => delivered.push(body)}}}},
};
vm.runInNewContext(source, context);
const click = (overrides = {}) => listeners.click({
  isTrusted: true, defaultPrevented: false, detail: 1, button: 0,
  clientX: 250, clientY: 400, composedPath: () => [new Element()], ...overrides,
});
const flush = () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); };
click(); flush();
assert.equal(delivered.length, 1);
assert.equal(delivered[0].x, 0.25); assert.equal(delivered[0].y, 0.8);
for (const event of [{isTrusted:false}, {defaultPrevented:true}, {detail:2}, {button:1}, {composedPath:()=>[new Element(true)]}]) {
  click(event); flush();
}
assert.equal(delivered.length, 1);
collapsed = false; click(); flush(); collapsed = true;
click(); collapsed = false; flush(); collapsed = true;
click(); listeners.pointerdown(); flush();
click(); context.window.__ankiPadTapToken = 'second'; flush();
assert.equal(delivered.length, 1);
click(); click({detail:2}); click({detail:3}); flush();
assert.equal(delivered.length, 1);
console.log('PASS: actual touch bridge filtering, selection, delayed cancellation and render token');
