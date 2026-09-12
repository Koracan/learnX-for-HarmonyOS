const fs = require('fs');
let raw = fs.readFileSync('.scratch/tablet-login/T1-layout.json', 'utf8');
raw = raw.replace(/^\uFEFF/, '');
const i = raw.indexOf('[');
const j = raw.lastIndexOf(']');
const data = JSON.parse(raw.slice(i, j + 1));
const rows = [];
function walk(n, d) {
  if (!n) return;
  const b = n.bounds;
  if (b) rows.push({ d: d, type: n.type, attrs: n.attributes || n.attr || {}, x: b[0], y: b[1], w: b[2], h: b[3] });
  (n.children || []).forEach(c => walk(c, d + 1));
}
data.forEach(r => walk(r, 0));
console.log('nodes=' + rows.length);
const wide = rows.filter(r => r.w > 1000);
console.log('--- nodes wider than 1000px (screen is 2880) ---');
wide.slice(0, 25).forEach(r => console.log('  '.repeat(r.d) + r.type + ' x=' + r.x + ' y=' + r.y + ' w=' + r.w + ' h=' + r.h));
const texts = rows.filter(r => JSON.stringify(r.attrs).length > 2);
console.log('--- nodes carrying attributes (first 20) ---');
texts.slice(0, 20).forEach(r => console.log(r.type + ' ' + JSON.stringify(r.attrs).slice(0, 200)));