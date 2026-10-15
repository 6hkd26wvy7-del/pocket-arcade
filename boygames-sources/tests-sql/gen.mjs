import * as BB from "/home/claude/pocket-arcade/shared/boyblocks-engine.js";
let s=12345; const r=()=>{s=(s*1664525+1013904223)>>>0;return s/4294967296;};
const out=[];
for(let i=0;i<300;i++){
  const seed=Math.floor(r()*4294967296), ens=i%3!==0;
  const g=BB.newGame(seed,{ensureFit:ens}); const mv=[]; const stop=Math.floor(r()*80)+1;
  // biased: prefer moves clearing lines sometimes (greedy by gain on a copy)
  while(!g.over&&mv.length<stop){
    const o=[];
    for(let k=0;k<3;k++) if(g.pieces[k]){const sh=BB.PIECES[g.pieces[k].p]; for(let a=0;a<=8-sh.h;a++)for(let b=0;b<=8-sh.w;b++) if(BB.fits(g.grid,sh,a,b)) o.push([k,a,b]);}
    if(!o.length)break;
    let m=o[Math.floor(r()*o.length)];
    if(i%2){ let best=-1; for(const c of o){const cp=JSON.parse(JSON.stringify(g)); const x=BB.place(cp,c[0],c[1],c[2]); if(x.gain>best){best=x.gain;m=c;}}}
    BB.place(g,m[0],m[1],m[2]); mv.push(m);
  }
  out.push(`(${i},${seed},${ens},'${JSON.stringify(mv)}',${g.score},${g.lines},${g.best_streak},${g.over})`);
}
console.log("create table xt(i int,seed bigint,ens boolean,mv jsonb,score int,lines int,bs int,over boolean);insert into xt values\n"+out.join(",\n")+";");
