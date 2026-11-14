const fs = require('fs');
const vm = require('vm');
const path = require('path');

class StubElement {
  constructor(id='') { this.id=id; this.listeners={}; this.style={}; this.children=[]; this.className=''; this.textContent=''; this.value=''; this.disabled=false; this._html=''; this.classList={set:new Set(),toggle:(name,force)=>{if(force===undefined){if(this.classList.set.has(name))this.classList.set.delete(name);else this.classList.set.add(name)}else if(force)this.classList.set.add(name);else this.classList.set.delete(name)},add:n=>this.classList.set.add(n),remove:n=>this.classList.set.delete(n),contains:n=>this.classList.set.has(n)}; }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  dispatch(type, event={}) { for (const fn of this.listeners[type]||[]) fn({target:this, ...event}); }
  appendChild(el) { this.children.push(el); return el; }
  querySelector(sel) { if(sel==='button'){ this._button ||= new StubElement('upgrade-button'); return this._button; } return null; }
  set innerHTML(value) { this._html=value; }
  get innerHTML() { return this._html; }
  getContext() { return context2d; }
}
const methods=['beginPath','moveTo','lineTo','closePath','fill','stroke','fillRect','clearRect','save','restore','translate','scale','rotate','ellipse','arc','roundRect','setTransform','strokeRect'];
const context2d={}; for(const m of methods)context2d[m]=()=>{};
context2d.createLinearGradient=()=>({addColorStop:()=>{}});
context2d.createRadialGradient=()=>({addColorStop:()=>{}});
const ids=[...fs.readFileSync(path.join(__dirname,'../preview/index.html'),'utf8').matchAll(/id="([^"]+)"/g)].map(m=>m[1]);
const elements={}; for(const id of ids)elements[id]=new StubElement(id);
elements.game.getContext=()=>context2d;
const document={getElementById:id=>elements[id] ||= new StubElement(id),createElement:tag=>new StubElement(tag)};
const window={innerWidth:430,innerHeight:932,devicePixelRatio:1,AudioContext:undefined,webkitAudioContext:undefined,addEventListener:()=>{}};
let raf=null;
const localData={};
const localStorage={getItem:k=>localData[k]||null,setItem:(k,v)=>{localData[k]=v}};
class FakeAudio {constructor(src){this.src=src;this.paused=true;this.volume=1;this.loop=false;}play(){this.paused=false;return Promise.resolve();}}
const sandbox={document,window,localStorage,Audio:FakeAudio,requestAnimationFrame:fn=>{raf=fn},console,Math,Date,JSON,Number,String,Array,Object,Boolean,parseInt,parseFloat,structuredClone,performance:{now:()=>0},
  innerWidth:430,innerHeight:932};
const html=fs.readFileSync(path.join(__dirname,'../preview/index.html'),'utf8');
const js=html.match(/<script>(.*?)<\/script>/s)[1];
vm.runInNewContext(js,sandbox,{timeout:2000});
function click(id){if(!elements[id])throw new Error('missing element '+id);elements[id].dispatch('click');}
click('play');
if(elements.hud.classList.contains('hidden'))throw new Error('HUD did not appear after starting');
if(!raf)throw new Error('render loop not scheduled');
click('pauseBtn');
if(elements.pause.classList.contains('hidden'))throw new Error('pause overlay did not appear');
click('resume');
if(elements.hud.classList.contains('hidden'))throw new Error('resume did not restore HUD');
click('home1');
click('shop');
if(elements.shopScreen.classList.contains('hidden'))throw new Error('shop did not open');
click('shopBack');
click('settings');
if(elements.settingsScreen.classList.contains('hidden'))throw new Error('settings did not open');
click('settingsBack');
// Continue a fresh run to exercise moving obstacles, pickups, collision, result and local save.
click('play');
for(let i=1;i<=1700 && elements.result.classList.contains('hidden');i++){const callback=raf;raf=null;callback(i*50);}
if(elements.result.classList.contains('hidden'))throw new Error('long run did not reach a result state');
if(!localData['afterlight-preview'])throw new Error('progress was not persisted');
console.log('preview runtime passed: start, HUD, pause/resume, shop, settings, endless simulation, result and local save');
