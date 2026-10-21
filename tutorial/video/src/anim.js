const T=__TIMES__;
const $=(s,r)=>(r||document).querySelector(s);
const mk=(h,p)=>{const d=document.createElement('div');d.innerHTML=h;const e=d.firstElementChild;p.appendChild(e);return e};
const tl=gsap.timeline({paused:true});
const L=(s,k)=>T[s].l[k], E=(s,k)=>T[s].e[k];
const FI=(sel,t,d=.55,y=28)=>tl.fromTo(sel,{opacity:0,y},{opacity:1,y:0,duration:d,ease:'power3.out'},t);
const FO=(sel,t,d=.4)=>tl.to(sel,{opacity:0,duration:d,ease:'power2.in'},t);
const DRAW=(sel,t,d=.6)=>tl.to(sel,{strokeDashoffset:0,duration:d,ease:'power2.out'},t);
const CNT=(el,from,to,t,d,fmt)=>{const o={v:from};tl.fromTo(o,{v:from},{v:to,duration:d,ease:'none',onUpdate:()=>{el.textContent=fmt?fmt(o.v):Math.round(o.v)}},t)};

// scene fades + captions
for(const k of Object.keys(T)){
  if(!/^S\d+$/.test(k))continue;
  const id='#s'+k.slice(1)+' .s';
  tl.fromTo(id,{opacity:0},{opacity:1,duration:.45,ease:'power2.out'},T[k].t0);
  tl.to(id,{opacity:0,duration:.4,ease:'power2.in'},T[k].t1-.45);
}
T.caps.forEach((c,i)=>{
  tl.fromTo('#cap'+i,{opacity:0,y:14},{opacity:1,y:0,duration:.2,ease:'power2.out'},c.s);
  tl.to('#cap'+i,{opacity:0,duration:.15},c.e-.2);
});

/* S01 */
{const s='S01';
 tl.fromTo('#s01-title',{opacity:0,y:40,scale:.94},{opacity:1,y:0,scale:1,duration:1,ease:'power3.out'},L(s,0));
 FI('#s01-sub',L(s,0)+.5);
 FI('#s01-n3',L(s,1)); tl.fromTo('#s01-n3',{borderColor:'#3a2f27'},{borderColor:'#f08a3c',duration:.4},L(s,1)+.3);
 FI('#s01-n2',L(s,2)-.2); FI('#s01-n1',L(s,2)+.2);
 DRAW('#s01-a1,#s01-a1h',L(s,2)+.8,.7); DRAW('#s01-a2,#s01-a2h',L(s,2)+1.4,.7);
 FI('#s01-n4',L(s,2)+1.9); DRAW('#s01-a3',L(s,2)+2.5,.5);
}
/* S02 */
{const s='S02';
 FI('#s02-link',L(s,0)); tl.fromTo('#s02-crop',{opacity:0,scale:.9},{opacity:1,scale:1,duration:.8,ease:'power3.out'},L(s,0)+.3);
 tl.fromTo('#s02-ring',{opacity:0,scale:1.15},{opacity:1,scale:1,duration:.5,ease:'back.out(2)'},L(s,1));
 FI('#s02-ok',L(s,1)+.2);
 const code=$('#s02-code'); const full='/sl Ich öffne die Tür.';
 const o={n:0};tl.fromTo(o,{n:0},{n:full.length,duration:1.6,ease:'none',onUpdate:()=>{const n=Math.round(o.n);code.innerHTML='<span class="gold">'+full.slice(0,Math.min(3,n))+'</span>'+(n>3?full.slice(3,n):'')}},L(s,1)+.4);
 FI('#s02-no',L(s,2)-.1);
}
/* S03 */
{const s='S03';
 FI('#s03-card',L(s,0)+.2);
 [1,2,3,4].forEach((n,i)=>{const t=L(s,2)+.2+i*1.5; tl.to('#s03-h'+n,{backgroundSize:'100% 100%',duration:.7,ease:'power2.out'},t); tl.fromTo('#s03-c'+n,{opacity:0,x:80},{opacity:1,x:0,duration:.6,ease:'power3.out'},t+.5)});
}
tl.fromTo('#s03-cmd',{opacity:0,y:20},{opacity:1,y:0,duration:.5},L('S03',3)+.2);
/* S04 */
{const s='S04'; const P=$('#s04-coins');
 for(let i=0;i<20;i++){mk(`<div class="coin pos" id="s04-c${i}" style="left:${192+(i%10)*84}px;top:${200+Math.floor(i/10)*84}px;opacity:0">1</div>`,P)}
 for(let i=0;i<6;i++){mk(`<div class="coin neg" id="s04-x${i}" style="left:${192+i*84}px;top:368px;opacity:0">+</div>`,P)}
 tl.fromTo('#s04-coins .pos',{opacity:0,scale:.2,y:-40},{opacity:1,scale:1,y:0,duration:.35,ease:'back.out(2)',stagger:.045},L(s,0)+.2);
 CNT($('#s04-num'),0,20,L(s,0)+.2,1.1);
 FI('#s04-v1',L(s,1)+.1);FI('#s04-v2',L(s,1)+1.9);
 tl.to('#s04-c19,#s04-c18',{opacity:.12,scale:.7,duration:.4,stagger:.15},L(s,1)+.9);CNT($('#s04-num'),20,18,L(s,1)+.9,.5);
 tl.to('#s04-c17,#s04-c16,#s04-c15,#s04-c14',{opacity:.12,scale:.7,duration:.35,stagger:.12},L(s,1)+2.7);CNT($('#s04-num'),18,14,L(s,1)+2.7,.7);
 FI('#s04-n1',L(s,2)+.2);FI('#s04-n2',L(s,2)+1.6);
 tl.fromTo('#s04-x0,#s04-x1',{opacity:0,scale:.2,y:60},{opacity:1,scale:1,y:0,duration:.4,ease:'back.out(2)',stagger:.12},L(s,2)+1.0);CNT($('#s04-num'),14,16,L(s,2)+1.0,.4);
 tl.fromTo('#s04-x2,#s04-x3,#s04-x4,#s04-x5',{opacity:0,scale:.2,y:60},{opacity:1,scale:1,y:0,duration:.4,ease:'back.out(2)',stagger:.1},L(s,2)+2.4);CNT($('#s04-num'),16,20,L(s,2)+2.4,.5);
 FI('#s04-warn',L(s,3));tl.fromTo('#s04-warn',{x:0},{x:12,duration:.07,yoyo:true,repeat:5},L(s,3)+.5);
}
/* S05 */
{const s='S05';const P=$('#s05-rows');
 const rows=[[1,'10 Taler','Startgeld','#e3b858'],[2,'1 Startgegenstand','normale Ausrüstung, keine Magie','#6fc08a'],[3,'+1 maximaler Schicksalspunkt','mehr Schicksal in der Hinterhand','#6aa8d8']];
 rows.forEach((r,i)=>{const y=190+i*215;let h=`<div id="s05-r${i}" style="opacity:0">`;
  for(let c=0;c<r[0];c++)h+=`<div class="coin" style="left:${192+c*76}px;top:${y+30}px">1</div>`;
  h+=`<div class="abs" style="left:480px;top:${y+22}px;font:700 64px 'Cinzel';color:#f08a3c">→</div><div class="card abs" style="left:620px;top:${y}px;width:1108px;height:130px;border-color:${r[3]}"><div class="b" style="font-size:44px;color:${r[3]}">${r[1]}</div><div class="t mute" style="font-size:30px">${r[2]}</div></div></div>`;
  mk(h,P)});
 FI('#s05-r0',L(s,1));FI('#s05-r1',L(s,2));FI('#s05-r2',L(s,3));
}
tl.fromTo('#s05-cmd',{opacity:0,y:20},{opacity:1,y:0,duration:.5},L('S05',4)+.2);
/* S06 */
{const s='S06';const P=$('#s06-cols');
 const cols=[['Kampf','#f08a3c','Nahkampf, Ausweichen, Schleichen',40],['Sozial','#6aa8d8','Überreden, Handeln, Auftreten',30],['Wissen','#6fc08a','Heilen, Lesen, Spuren deuten',50]];
 cols.forEach((c,i)=>{const x=192+i*516;mk(`<div id="s06-k${i}" style="opacity:0"><div class="card abs" style="left:${x}px;top:190px;width:504px;height:470px;border-color:${c[1]}"><div class="h2" style="color:${c[1]}">${c[0]}</div><div class="t mute" style="font-size:28px">${c[2]}</div></div><div class="bar" id="s06-b${i}" style="left:${x+40}px;bottom:430px;width:424px;height:0;background:${c[1]};opacity:.55;transform-origin:50% 100%"></div></div>`,P);
  mk(`<div id="s06-v${i}" class="abs" style="left:${x+152}px;top:560px;width:200px;height:200px;border-radius:50%;background:#2a1f18;border:5px solid ${c[1]};font:700 100px/190px 'Cinzel';text-align:center;color:#f1e7d6;opacity:0">${c[3]}</div>`,P)});
 tl.fromTo('#s06-k0,#s06-k1,#s06-k2',{opacity:0,y:40},{opacity:1,y:0,duration:.6,stagger:.2,ease:'power3.out'},L(s,0)+.3);
 const order=[1,0,2];
 order.forEach((ci,k)=>{
   tl.fromTo('#s06-v'+ci,{opacity:0,x:(k-ci)*516,y:70,scale:.5},{opacity:1,x:(k-ci)*516,y:70,scale:1,duration:.5,ease:'back.out(2)'},L(s,0)+1.3+k*.4);
   tl.to('#s06-v'+ci,{x:0,y:-300,scale:.62,duration:.9,ease:'power3.inOut'},L(s,1)+.4+k*.35);
   tl.to('#s06-b'+ci,{height:cols[ci][3]*4,duration:.8,ease:'power2.out'},L(s,1)+1.2+k*.35);
 });
}
/* S07 */
{const s='S07';
 FI('#s07-card',L(s,0)+.2);
 FI('#s07-A',L(s,1)+.2);
 FO('#s07-A',L(s,2)-.1);tl.fromTo('#s07-B',{opacity:0,scale:.9},{opacity:1,scale:1,duration:.7,ease:'back.out(1.6)'},L(s,2)+.3);
 const P=$('#s07-split');const segs=[[3,'+1 SP','#6aa8d8'],[2,'Armbrust','#6fc08a'],[2,'Leder-wams','#6fc08a'],[5,'50 Taler','#e3b858']];let x=880;
 segs.forEach((g,i)=>{const w=g[0]*66;mk(`<div id="s07-g${i}" class="bar" style="left:${x}px;top:610px;width:${w-6}px;height:120px;background:${g[2]};opacity:0;text-align:center;color:#101010;font:700 26px/1.2 'Lora';padding-top:18px">${g[1]}<div style="font-size:24px;font-weight:600;margin-top:6px">${g[0]} Pkt</div></div>`,P);x+=w});
 tl.fromTo('#s07-g0,#s07-g1,#s07-g2,#s07-g3',{opacity:0,y:-60},{opacity:1,y:0,duration:.5,stagger:.35,ease:'back.out(1.8)'},L(s,3)+.2);
 tl.to('#s07-sp',{opacity:1,duration:.4},L(s,3)+.6);tl.to('#s07-it',{opacity:1,duration:.4},L(s,3)+1.6);tl.to('#s07-ta',{opacity:1,duration:.4},L(s,3)+2.6);
}
/* S08 */
{const s='S08';
 FI('#s08-top',L(s,0)+.1);
 FI('#s08-f1',L(s,1)+.1);FI('#s08-o1',L(s,1)+.7);FI('#s08-f2',L(s,1)+1.0);FI('#s08-o2',L(s,1)+1.5);FI('#s08-f3',L(s,1)+1.8);FI('#s08-o3',L(s,1)+2.3);
 tl.fromTo('#s08-f4',{opacity:0,scale:.7},{opacity:1,scale:1,duration:.6,ease:'back.out(2)'},L(s,1)+2.8);
 const P=$('#s08-diff');
 [['leicht +20','#6fc08a'],['normal ±0','#6aa8d8'],['schwer −20','#f08a3c'],['sehr schwer −30','#e5675a']].forEach((d,i)=>{mk(`<div id="s08-d${i}" class="chip" style="left:${192+i*390}px;top:480px;border-color:${d[1]};opacity:0">${d[0]}</div>`,P)});
 tl.fromTo('#s08-d0,#s08-d1,#s08-d2,#s08-d3',{opacity:0,y:30},{opacity:1,y:0,duration:.45,stagger:.5},L(s,2)+.1);
 FI('#s08-bar',L(s,3)+.1);tl.fromTo('#s08-zone',{width:0},{width:922,duration:1.2,ease:'power2.out'},L(s,3)+.5);
 tl.fromTo('#s08-tl',{opacity:0},{opacity:1,duration:.4},L(s,3)+1.4);
}
/* S09 */
{const s='S09';
 const bar=$('#s09-bar');let h='';const U=1536/100;
 h+=`<div class="bar" style="left:0;top:0;width:1536px;height:120px;background:#3a1d1a"></div>`;
 for(let k=0;k<6;k++){const hi=60-10*k,lo=hi-10;h+=`<div class="bar" id="s09-s${k}" style="left:${lo*U}px;top:0;width:${10*U-4}px;height:120px;background:#2f7a4a;opacity:0;text-align:center;font:700 44px/116px 'Cinzel';color:#fff;border:2px solid #6fc08a">${k+1}</div>`}
 h+=`<div class="bar" id="s09-bo" style="left:0;top:-14px;width:${5*U}px;height:148px;border:4px solid #6fc08a;opacity:0"></div><div class="bar" id="s09-bx" style="left:${95*U}px;top:-14px;width:${5*U}px;height:148px;border:4px solid #e5675a;opacity:0"></div>`;
 h+=`<div class="abs gold b" id="s09-tz" style="left:${60*U-120}px;top:128px;width:240px;text-align:center;font-size:30px;opacity:0">Zielzahl 60</div>`;
 h+=`<div id="s09-ball" class="abs" style="left:${34*U-35}px;top:-80px;width:70px;height:70px;border-radius:50%;background:#f1e7d6;color:#151010;font:700 34px/70px 'Cinzel';text-align:center;opacity:0">34</div>`;
 bar.innerHTML=h;
 tl.to('#s09-g1',{opacity:1,duration:.5},L(s,0)+.1);
 tl.fromTo('#s09-s5,#s09-s4,#s09-s3,#s09-s2,#s09-s1,#s09-s0',{opacity:0,y:30},{opacity:1,y:0,duration:.4,stagger:.35,ease:'power2.out'},L(s,0)+.5);
 tl.to('#s09-tz',{opacity:1,duration:.4},L(s,0)+2.4);
 tl.fromTo('#s09-ball',{opacity:0,y:-120},{opacity:1,y:0,duration:.7,ease:'bounce.out'},L(s,1)+.3);
 tl.to('#s09-s2',{backgroundColor:'#f08a3c',duration:.3},L(s,1)+1.1);
 tl.fromTo('#s09-res',{opacity:0,scale:.8},{opacity:1,scale:1,duration:.6,ease:'back.out(2)'},L(s,1)+1.6);
 tl.to('#s09-res',{opacity:0,duration:.3},L(s,2)-.1);
 tl.to('#s09-bo,#s09-b1',{opacity:1,duration:.4},L(s,2)+.1);tl.to('#s09-bx,#s09-b2',{opacity:1,duration:.4},L(s,2)+1.7);
 tl.to('#s09-g1',{opacity:0,duration:.4},L(s,3)-.15);
 const tiles=$('#s09-tiles');[11,22,33,44,55,66,77,88,99,100].forEach((n,i)=>mk(`<div id="s09-t${i}" class="sq" style="left:${192+i*154}px;top:300px;width:136px;opacity:0;border-color:#e3b858;color:#e3b858">${n}</div>`,tiles));
 tl.to('#s09-g2',{opacity:1,duration:.4},L(s,3));
 tl.fromTo('#s09-tiles .sq',{opacity:0,scale:.4},{opacity:1,scale:1,duration:.35,stagger:.14,ease:'back.out(2)'},L(s,3)+.4);
 tl.fromTo('#s09-ck,#s09-cf',{opacity:0,y:40},{opacity:1,y:0,duration:.5,stagger:1.8,ease:'power3.out'},L(s,3)+3.2);
 tl.to('#s09-g2',{opacity:0,duration:.4},L(s,4)-.15);
 tl.to('#s09-g3',{opacity:1,duration:.4},L(s,4));
 tl.fromTo('#s09-m',{scale:.3},{scale:1,duration:.6,ease:'back.out(2)'},L(s,4)+.5);tl.fromTo('#s09-w',{scale:.3},{scale:1,duration:.6,ease:'back.out(2)'},L(s,4)+1.2);
 tl.fromTo('#s09-win',{opacity:0},{opacity:1,duration:.5},L(s,4)+2.6);
}
/* S10 */
{const s='S10';
 FI('#s10-a',L(s,0)+.2);
 const eq=$('#s10-eq');
 [['Waffe 3','#f1e7d6',0],['+',null,285],['DoS 2','#6fc08a',355],['−',null,625],['Rüstung 1','#6aa8d8',695],['=',null,1010],['Schaden 4','#f08a3c',1085]].forEach((e,i)=>{
  mk(e[1]?`<div id="s10-e${i}" class="node" style="left:${e[2]}px;top:0;width:${i==6?360:(i==2?260:i==4?300:270)}px;font-size:38px;padding:30px 4px;border-color:${e[1]};color:${e[1]};opacity:0">${e[0]}</div>`:`<div id="s10-e${i}" class="abs t" style="left:${e[2]}px;top:26px;width:60px;text-align:center;font-size:64px;opacity:0">${e[0]}</div>`,eq)});
 FO('#s10-a',L(s,1)-.1);
 tl.set('#s10-eq',{opacity:1},L(s,1));
 tl.fromTo('#s10-e0,#s10-e1,#s10-e2,#s10-e3,#s10-e4,#s10-e5,#s10-e6',{opacity:0,y:30},{opacity:1,y:0,duration:.45,stagger:.5,ease:'power3.out'},L(s,1)+.2);
 const wl=$('#s10-wl');
 for(let i=1;i<=10;i++)mk(`<div id="s10-w${i}" class="sq" style="left:${(i-1)*154}px;top:20px;width:136px;height:90px;border-color:${i<=3?'#f08a3c':'#6fc08a'};background:${i<=3?'#4a2a14':'#1f3a29'};color:#f1e7d6;line-height:82px">${i}</div>`,wl);
 mk(`<div class="abs mute" style="left:0;top:130px;font-size:30px">Wunden</div>`,wl);
 mk(`<div class="abs b" id="s10-th" style="left:0;top:170px;width:700px;font-size:32px;color:#f08a3c;opacity:0">1–3: −10 auf alle Proben</div>`,wl);
 tl.fromTo('#s10-wl',{opacity:0,y:30},{opacity:1,y:0,duration:.5},L(s,2)+.1);
 const D=(sel,t)=>tl.to(sel,{backgroundColor:'#201210',borderColor:'#3a2f27',color:'#5a4a3c',duration:.35,stagger:.2},t);
 D('#s10-w10,#s10-w9,#s10-w8,#s10-w7,#s10-w6',L(s,2)+1.2);
 tl.to('#s10-th',{opacity:1,duration:.4},L(s,2)+2.6);
 D('#s10-w5,#s10-w4',L(s,3)-.4);
 D('#s10-w3,#s10-w2,#s10-w1',L(s,3)+.3);
 $('#s10-t1').innerHTML='<span class="bad">0 Wunden: zu Boden</span> · <span class="gold">1 SP: du lebst</span>';
 tl.fromTo('#s10-t1',{opacity:0,y:20},{opacity:1,y:0,duration:.5},L(s,3)+1.4);
}
function pips(P,id,x0,y,n){for(let i=0;i<n;i++)mk(`<div id="${id}${i+1}" class="pip" style="left:${x0+i*124}px;top:${y}px;border-color:#e3b858;background:#e3b858;color:#2a1c05;opacity:0">${i+1}</div>`,P)}
const dim=(sel,t,d=.35)=>tl.to(sel,{backgroundColor:'#1d1713',borderColor:'#3a2f27',color:'#5a4a3c',duration:d},t);
const lit=(sel,t,d=.35,c='#e3b858')=>tl.to(sel,{backgroundColor:c,borderColor:c,color:'#2a1c05',duration:d},t);
/* S11 */
{const s='S11';const P=$('#s11-pips');pips(P,'s11-p',192,190,5);
 tl.fromTo('#s11-pips .pip',{opacity:0,scale:.3},{opacity:1,scale:1,duration:.4,stagger:.15,ease:'back.out(2)'},L(s,0)+.2);FI('#s11-n',L(s,0)+.6);
 const C=$('#s11-cards');
 const cards=[['1 SP','±10 auf eine Probe','auch auf die eines Gegners · höchstens 3 SP je Probe','#6fc08a'],['1 SP','Orakel-Chancen','um eine Stufe verschieben','#6aa8d8'],['2 SP','Neuwurf','das zweite Ergebnis zählt','#f08a3c'],['1 SP','Überleben bei 0 Wunden','du bleibst am Boden, aber du lebst','#e5675a']];
 cards.forEach((c,i)=>mk(`<div id="s11-c${i}" class="card abs" style="left:${192+(i%2)*780}px;top:${400+Math.floor(i/2)*200}px;width:756px;height:176px;border-color:${c[3]};opacity:0"><div class="b" style="font-size:44px;color:${c[3]}">${c[0]} · ${c[1]}</div><div class="t mute" style="font-size:28px;margin-top:6px">${c[2]}</div></div>`,C));
 const tt=[L(s,1)+.3,L(s,2)+.2,L(s,2)+2.2,L(s,3)+.2];
 tt.forEach((t,i)=>FI('#s11-c'+i,t));
 tl.fromTo('#s11-p5',{scale:1},{scale:1.2,duration:.25,yoyo:true,repeat:1},tt[0]+.4);
 tl.fromTo('#s11-p4',{scale:1},{scale:1.2,duration:.25,yoyo:true,repeat:1},tt[1]+.3);
 tl.fromTo('#s11-p3,#s11-p2',{scale:1},{scale:1.2,duration:.25,yoyo:true,repeat:1,stagger:.15},tt[2]+.3);
 tl.fromTo('#s11-p1',{scale:1},{scale:1.2,duration:.25,yoyo:true,repeat:1},tt[3]+.3);
}
/* S12 */
{const s='S12';const P=$('#s12-pips');pips(P,'s12-p',192,190,5);const n=$('#s12-n');
 tl.fromTo('#s12-pips .pip',{opacity:0,scale:.3},{opacity:1,scale:1,duration:.4,stagger:.1},L(s,0)-.2);
 dim('#s12-p5',L(s,0)+.5);dim('#s12-p4',L(s,0)+1.1);dim('#s12-p3',L(s,0)+1.7);dim('#s12-p2',L(s,0)+2.3);CNT(n,5,1,L(s,0)+.5,1.8);
 const st=$('#s12-st1');
 st.innerHTML='<span class="ember">1 SP: schicksalsmüde · −10 auf alle Proben</span>';
 tl.fromTo('#s12-st',{opacity:0,y:20},{opacity:1,y:0,duration:.5},L(s,0)+2.4);
 dim('#s12-p1',L(s,1)+.2);CNT(n,1,0,L(s,1)+.2,.4);
 tl.call(()=>{st.innerHTML='<span class="bad">0 SP: −20 · Orakel zu euren Gunsten eine Stufe schlechter</span>'},null,L(s,1)+.5);
 tl.call(()=>{st.innerHTML='<span class="ember">1 SP: schicksalsmüde · −10 auf alle Proben</span>'},null,L(s,1)+.45);
 tl.fromTo('#s12-n',{color:'#e3b858'},{color:'#e5675a',duration:.4},L(s,1)+.3);
 const R=$('#s12-rec');[['Rast 1 Std. +1'],['Nacht +3'],['Fest +2'],['Strang +2']].forEach((r,i)=>mk(`<div id="s12-r${i}" class="chip pos" style="left:${192+i*385}px;top:600px;opacity:0;border-color:#6fc08a">${r[0]}</div>`,R));
 tl.to('#s12-st',{opacity:0,duration:.3},L(s,2)-.2);
 tl.fromTo('#s12-r0,#s12-r1,#s12-r2,#s12-r3',{opacity:0,y:30},{opacity:1,y:0,duration:.45,stagger:.9},L(s,2)+.1);
 tl.fromTo('#s12-n',{color:'#e5675a'},{color:'#e3b858',duration:.4},L(s,2)+.6);
 [1,2,3,4,5].forEach((k,i)=>lit('#s12-p'+k,L(s,2)+.8+i*.55));
 CNT(n,0,5,L(s,2)+.8,2.4);
}
/* S13 */
{const s='S13';
 tl.fromTo('#s13-crop',{opacity:0,scale:.92},{opacity:1,scale:1,duration:.7,ease:'power3.out'},L(s,0)+.2);
 FI('#s13-lad',L(s,1)+.2);FI('#s13-q',L(s,2)-.3);
 const B=$('#s13-bar');const U=1536/100;
 [[0,8,'JA+','#2f7a4a'],[8,50,'JA','#2a6b9c'],[50,92,'NEIN','#b8541a'],[92,100,'NEIN+','#a8302a']].forEach((g,i)=>mk(`<div id="s13-s${i}" class="bar" style="left:${g[0]*U}px;top:0;width:${(g[1]-g[0])*U-4}px;height:90px;background:${g[3]};color:#fff;font:700 38px/90px 'Cinzel';text-align:center;opacity:0">${g[2]}</div>`,B));
 mk(`<div id="s13-ball" class="abs" style="left:${41*U-32}px;top:-76px;width:64px;height:64px;border-radius:50%;background:#f1e7d6;color:#151010;font:700 30px/64px 'Cinzel';text-align:center;opacity:0">41</div>`,B);
 tl.fromTo('#s13-bar',{opacity:0},{opacity:1,duration:.3},L(s,2)+.2);
 tl.fromTo('#s13-s0,#s13-s1,#s13-s2,#s13-s3',{opacity:0,scaleY:.2},{opacity:1,scaleY:1,duration:.4,stagger:.5,ease:'power2.out'},L(s,2)+.5);
 tl.fromTo('#s13-ball',{opacity:0,y:-100},{opacity:1,y:0,duration:.7,ease:'bounce.out'},E(s,2)-.2);
}
/* S14 */
{const s='S14';const P=$('#s14-tl');
 [['Du schreibst','#3a2f27',0,340],['sl denkt: 4 bis 12 s','#f08a3c',350,560],['Erzählung','#6fc08a',920,290],['Nächster Zug','#6aa8d8',1220,316]].forEach((g,i)=>mk(`<div id="s14-g${i}" class="bar" style="left:${192+g[2]}px;top:190px;width:${g[3]-8}px;height:110px;border:3px solid ${g[1]};background:#1d1713;text-align:center;font:600 30px/104px 'Lora';opacity:0">${g[0]}</div>`,P));
 tl.fromTo('#s14-g0,#s14-g1,#s14-g2,#s14-g3',{opacity:0,y:30},{opacity:1,y:0,duration:.45,stagger:.35},L(s,0)+.2);
 tl.fromTo('#s14-timer',{opacity:0},{opacity:1,duration:.4},L(s,0)+1.6);CNT($('#s14-timer'),0,12,L(s,0)+1.8,E(s,0)-L(s,0)-.4,v=>Math.round(v)+' s');
 tl.fromTo('#s14-dots',{opacity:0},{opacity:1,duration:.4},L(s,0)+2.5);
 FI('#s14-ok',L(s,1)+.2);FI('#s14-no',L(s,1)+1.8);
}
/* S15 */
{const s='S15';
 tl.fromTo('#s15-doc',{opacity:0,rotation:-4,y:40},{opacity:1,rotation:-2,y:0,duration:.8,ease:'power3.out'},L(s,0)+.2);
 FI('#s15-t1',L(s,1)+.1);
 tl.fromTo('#s15-big',{opacity:0,scale:.85},{opacity:1,scale:1,duration:.9,ease:'back.out(1.6)'},L(s,2)+.2);
}
window.__timelines["main"]=tl;
