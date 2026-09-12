const fs=require('fs');
let raw=fs.readFileSync('.scratch/tablet-login/T3-layout-notices.json','utf8').replace(/^\uFEFF/,'');
const data=JSON.parse(raw.slice(raw.indexOf('['), raw.lastIndexOf(']')+1));
const rows=[];
function walk(n,d){ if(!n) return; const b=n.bounds; if(b) rows.push({d,type:n.type,x:b[0],y:b[1],w:b[2],h:b[3]}); (n.children||[]).forEach(c=>walk(c,d+1)); }
data.forEach(r=>walk(r,0));
console.log('nodes='+rows.length);
rows.filter(r=>r.d<=8).forEach(r=>console.log('  '.repeat(r.d)+r.type+' x='+r.x+' y='+r.y+' w='+r.w+' h='+r.h));