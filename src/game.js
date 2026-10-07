import {createXR} from './xr.js';
import * as THREE from '../vendor/three.module.js';
const canvas=document.getElementById('scene');
const scene=new THREE.Scene();scene.background=new THREE.Color('#526d8b');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,alpha:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.15;
const camera=new THREE.OrthographicCamera(-8,8,6,-6,.1,100);
const world=new THREE.Group();scene.add(world);
const mat=(color,roughness=.78)=>new THREE.MeshStandardMaterial({color,roughness,metalness:0});
const teal=mat('#6c999e'),tealTop=mat('#82a8ab'),cream=mat('#e9d9b9'),orange=mat('#ff9c3f'),crateMat=mat('#e99a58'),cratePanel=mat('#dc8f4e'),gold=mat('#edbc40',.5),goldDark=mat('#ae8024'),white=mat('#fff7de'),black=mat('#201e1a',.34),bagMat=mat('#44898d');
const roundedCache=new Map();
function rounded(w,h,d,r=.07){const key=[w,h,d,r].join(',');if(roundedCache.has(key))return roundedCache.get(key);const g=new THREE.BoxGeometry(1,1,1,7,7,7);const p=g.attributes.position,n=g.attributes.normal;const inner=new THREE.Vector3(w/2-r,h/2-r,d/2-r),v=new THREE.Vector3(),normal=new THREE.Vector3();for(let i=0;i<p.count;i++){v.fromBufferAttribute(p,i);normal.copy(v);normal.x-=Math.sign(v.x)/14;normal.y-=Math.sign(v.y)/14;normal.z-=Math.sign(v.z)/14;normal.normalize();n.setXYZ(i,normal.x,normal.y,normal.z);p.setXYZ(i,Math.sign(v.x)*inner.x+normal.x*r,Math.sign(v.y)*inner.y+normal.y*r,Math.sign(v.z)*inner.z+normal.z*r);}roundedCache.set(key,g);return g;}
function mesh(geo,material,x=0,y=0,z=0,parent=world){const m=new THREE.Mesh(geo,material);m.position.set(x,y,z);m.castShadow=true;m.receiveShadow=true;parent.add(m);return m;}
function box(w,h,d,x,y,z,material=teal,r=.06,parent=world){return mesh(rounded(w,h,d,Math.min(r,w/2-.001,h/2-.001,d/2-.001)),material,x,y,z,parent);}
function oval(x,y,z,sx,sy,sz,material,parent=world){const m=mesh(new THREE.SphereGeometry(1,32,24),material,x,y,z,parent);m.scale.set(sx,sy,sz);return m;}
const floorY=.06;
box(8.55,.42,7.55,0,-.2,0,teal,.16);
for(let x=0;x<8;x++)for(let z=0;z<7;z++){const m=mat(new THREE.Color('#eadcbe').multiplyScalar(1+((x*17+z*13)%7-3)*.006));box(.989,.15,.989,x-3.5,floorY-.075,z-3,m,.027);}
// Modular perimeter: straight segments terminate at four independent curved corner pieces.
const cornerCenters={x:3.805,z:3.305};
function straightSpan(center,halfExtent,limit){const lo=Math.max(center-halfExtent,-limit),hi=Math.min(center+halfExtent,limit);return {length:hi-lo,center:(lo+hi)/2};}
for(let x=0;x<8;x++){const span=straightSpan(x-3.5,.496,cornerCenters.x-.044);box(span.length,.72,.27,span.center,.36,3.59);if(x<5||x>6)box(span.length,.72,.27,span.center,.36,-3.59);}
for(let z=0;z<7;z++){const span=straightSpan(z-3,.496,cornerCenters.z-.044);box(.27,.72,span.length,-4.09,.36,span.center);box(.27,.72,span.length,4.09,.36,span.center);}
function makeCorner(sx,sz){
  // One watertight quarter-ring mesh; bevel supplies rounded top and bottom edges.
  const shape=new THREE.Shape(),outer=.385,inner=.185,steps=24;
  for(let i=0;i<=steps;i++){const a=i/steps*Math.PI/2,x=sx*outer*Math.cos(a),y=-sz*outer*Math.sin(a);if(i===0)shape.moveTo(x,y);else shape.lineTo(x,y);}
  for(let i=steps;i>=0;i--){const a=i/steps*Math.PI/2;shape.lineTo(sx*inner*Math.cos(a),-sz*inner*Math.sin(a));}
  shape.closePath();
  const geometry=new THREE.ExtrudeGeometry(shape,{depth:.64,steps:1,bevelEnabled:true,bevelSize:.035,bevelThickness:.04,bevelSegments:4,curveSegments:24});
  // Smooth only coincident surfaces with similar normals, retaining the flat end caps.
  const positions=geometry.attributes.position,normals=geometry.attributes.normal,buckets=new Map();
  for(let i=0;i<positions.count;i++){const key=[positions.getX(i),positions.getY(i),positions.getZ(i)].map(v=>Math.round(v*1e5)).join(',');if(!buckets.has(key))buckets.set(key,[]);buckets.get(key).push(i);}
  const original=normals.array.slice();
  for(const ids of buckets.values())for(const i of ids){const n=new THREE.Vector3().fromArray(original,i*3),sum=new THREE.Vector3();for(const j of ids){const v=new THREE.Vector3().fromArray(original,j*3);if(n.dot(v)>.72)sum.add(v);}sum.normalize();normals.setXYZ(i,sum.x,sum.y,sum.z);}
  const corner=mesh(geometry,teal,sx*cornerCenters.x,.04,sz*cornerCenters.z);corner.rotation.x=-Math.PI/2;corner.name='perimeter-corner-'+sx+'-'+sz;corner.userData.modularCorner=true;return corner;
}
for(const sx of [-1,1])for(const sz of [-1,1])makeCorner(sx,sz);
const dividerA=box(3.05,.85,.29,-.9,.485,-.7,teal,.07);const dividerB=box(1.42,.75,.29,-3.25,.435,1.15,teal,.065);
// Floor contact occlusion: generated radial texture, not downloaded artwork.
const aoCanvas=document.createElement('canvas');aoCanvas.width=aoCanvas.height=128;const ctx=aoCanvas.getContext('2d');const grad=ctx.createRadialGradient(64,64,0,64,64,64);grad.addColorStop(0,'rgba(35,32,28,.48)');grad.addColorStop(.4,'rgba(35,32,28,.25)');grad.addColorStop(1,'rgba(35,32,28,0)');ctx.fillStyle=grad;ctx.fillRect(0,0,128,128);const aoTexture=new THREE.CanvasTexture(aoCanvas);
function contact(x,z,w,d,opacity=.5,y=.065){const m=new THREE.Mesh(new THREE.PlaneGeometry(w,d),new THREE.MeshBasicMaterial({map:aoTexture,transparent:true,opacity,depthWrite:false,polygonOffset:true,polygonOffsetFactor:-1}));m.rotation.x=-Math.PI/2;m.position.set(x,y,z);world.add(m);return m;}
const dividerShadowA=contact(-.9,-.7,3.5,.95,.5),dividerShadowB=contact(-3.25,1.15,1.8,.95,.5);
for(let z=-3;z<=3;z++){contact(-3.94,z,.5,1.7,.22);contact(3.94,z,.5,1.7,.22);}for(let x=-3.5;x<=3.5;x++){contact(x,3.46,1.7,.5,.22);contact(x,-3.46,1.7,.5,.22);}
// Pressure plate and inset line to the gate.
const plateStart=world.children.length;
const px=1.75,pz=1.35;
box(.91,.075,.91,px,.102,pz,goldDark,.055);box(.84,.09,.84,px,.145,pz,gold,.06);box(.64,.022,.64,px,.2,pz,mat('#f7da7a'),.025);
function triangle(size,material){const s=new THREE.Shape();s.moveTo(-size/2,-size*.36);s.lineTo(size/2,-size*.36);s.lineTo(0,size*.5);s.closePath();return new THREE.Mesh(new THREE.ExtrudeGeometry(s,{depth:.025,bevelEnabled:true,bevelThickness:.007,bevelSize:.009,bevelSegments:2,steps:1}),material);}
const plateIcon=triangle(.39,goldDark.clone());plateIcon.rotation.x=-Math.PI/2;plateIcon.position.set(px,.22,pz);world.add(plateIcon);
box(.115,.025,4.13,px,.078,-1.1,gold,.01);contact(px,pz,1.2,1.2,.3);
const firstPlateParts=world.children.slice(plateStart);
// Crate: solid bevelled frame and recessed panels on all visible faces.
const crate=new THREE.Group();crate.position.set(.36,.61,1.35);world.add(crate);box(1.04,1.09,1.04,0,0,0,crateMat,.08,crate);
function panel(axis,sign){const frameMat=mat('#efaa6d');if(axis==='z'){box(.77,.78,.025,0,0,sign*.526,cratePanel,.022,crate);for(const a of [-1,1]){box(.08,.88,.045,a*.43,0,sign*.533,frameMat,.022,crate);box(.88,.08,.045,0,a*.44,sign*.533,frameMat,.022,crate);}}else if(axis==='x'){box(.025,.78,.77,sign*.526,0,0,cratePanel,.022,crate);for(const a of [-1,1]){box(.045,.88,.08,sign*.533,0,a*.43,frameMat,.022,crate);box(.045,.08,.88,sign*.533,a*.44,0,frameMat,.022,crate);}}else{box(.77,.025,.77,0,sign*.551,0,cratePanel,.02,crate);for(const a of [-1,1]){box(.08,.045,.88,a*.43,sign*.557,0,frameMat,.02,crate);box(.88,.045,.08,0,sign*.557,a*.43,frameMat,.02,crate);}}}
panel('z',1);panel('z',-1);panel('x',1);panel('x',-1);panel('y',1);
// Capsule hero, all generated geometry, no external models.
const hero=new THREE.Group();hero.position.set(-.76,.07,1.35);hero.rotation.y=Math.PI/2;world.add(hero);
mesh(new THREE.CapsuleGeometry(.285,.58,12,32),orange,0,.8,0,hero);
oval(-.16,.105,.045,.14,.105,.195,orange,hero);oval(.16,.105,.045,.14,.105,.195,orange,hero);
box(.43,.54,.19,0,.68,-.28,bagMat,.075,hero);box(.33,.34,.06,0,.61,-.4,teal,.035,hero);
for(const x of [-.122,.122]){const eye=oval(x,1.02,.251,.088,.134,.045,white,hero);eye.rotation.y=x*.8;oval(x+.02,1.025,.294,.036,.071,.022,black,hero);oval(x+.013,1.053,.313,.009,.016,.006,white,hero);}
const smilePts=[];for(let i=0;i<=20;i++){let t=i/20;const x=(t-.5)*.16;smilePts.push(new THREE.Vector3(x,.83-.045*Math.sin(t*Math.PI),Math.sqrt(.285*.285-x*x)+.006));}
mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(smilePts),24,.01,8,false),black,0,0,0,hero);
function limb(a,b,r,material,parent){const va=new THREE.Vector3(...a),vb=new THREE.Vector3(...b);const m=mesh(new THREE.CapsuleGeometry(r,va.distanceTo(vb),6,16),material,0,0,0,parent);m.position.copy(va).add(vb).multiplyScalar(.5);m.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),vb.sub(va).normalize());return m;}
limb([-.235,.67,.03],[-.24,.58,.38],.079,orange,hero);limb([.235,.67,.03],[.24,.58,.38],.079,orange,hero);oval(-.24,.6,.435,.098,.093,.095,orange,hero);oval(.24,.6,.435,.098,.093,.095,orange,hero);
const exitStart=world.children.length;
// Walk-through arch cross-section, extruded with real opening.
function archShape(R,r,s){const shape=new THREE.Shape();shape.moveTo(-R,0);shape.lineTo(-R,s);shape.absarc(0,s,R,Math.PI,0,true);shape.lineTo(R,0);shape.lineTo(r,0);shape.lineTo(r,s);shape.absarc(0,s,r,0,Math.PI,false);shape.lineTo(-r,0);shape.closePath();return shape;}
const archX=1.75,frontZ=-3.46;
for(let i=0;i<4;i++){const g=new THREE.ExtrudeGeometry(archShape(.91,.63,.91),{depth:i===0?.35:.49,steps:1,curveSegments:24,bevelEnabled:true,bevelSegments:3,bevelSize:.045,bevelThickness:.04});const part=mesh(g,i===0?tealTop:teal,archX,.06,frontZ-i*.56);part.userData.exitTunnel=true;}
// A shadowed far end makes the exit read as a tunnel, not a portal.
box(1.24,1.51,.03,archX,.8,frontZ-1.75,mat('#293e43'),.012);
box(1.35,.15,2.1,archX,-.012,frontZ-.8,cream,.02);
const gate=new THREE.Group();world.add(gate);for(let i=-1;i<=1;i++)mesh(new THREE.CylinderGeometry(.038,.038,1.35,16),gold,archX+i*.34,.76,frontZ+.12,gate);
box(1.32,.09,.09,archX,.61,frontZ+.12,gold,.035,gate);
const gateIcon=triangle(.28,gold);gateIcon.position.set(archX,1.6,frontZ+.43);world.add(gateIcon);contact(archX,-3.26,2.35,1.1,.65);
const exitPieces=world.children.slice(exitStart).map(object=>({object,y:object.position.y}));
// Lighting is realtime, with soft contact shading generated above.
const hemisphere=new THREE.HemisphereLight('#fff6df','#738399',2.05);scene.add(hemisphere);
const key=new THREE.DirectionalLight('#fff1d8',3.3);key.position.set(-3,10,5);key.castShadow=true;key.shadow.mapSize.set(2048,2048);Object.assign(key.shadow.camera,{left:-8,right:8,top:8,bottom:-8,near:.5,far:30});key.shadow.normalBias=.025;key.shadow.bias=-.00015;key.shadow.radius=3;scene.add(key);
const fill=new THREE.DirectionalLight('#b6d3f1',.6);fill.position.set(6,5,-7);scene.add(fill);
const ground=mesh(new THREE.PlaneGeometry(200,200),mat('#526d8b'),0,-.425,0,scene);ground.rotation.x=-Math.PI/2;ground.castShadow=false;
const sceneBounds=new THREE.Box3().setFromObject(world);
const target=new THREE.Vector3(0,.15,-.65);let azimuth=.57,elevation=.76,zoom=1,dirty=true;
function fit(){if(renderer.xr.isPresenting)return;const width=canvas.clientWidth||innerWidth,height=canvas.clientHeight||innerHeight;renderer.setSize(width,height,false);camera.position.set(target.x+20*Math.sin(azimuth)*Math.cos(elevation),target.y+20*Math.sin(elevation),target.z+20*Math.cos(azimuth)*Math.cos(elevation));camera.lookAt(target);camera.updateMatrixWorld();const bounds=sceneBounds;let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;for(let i=0;i<8;i++){const p=new THREE.Vector3(i&1?bounds.max.x:bounds.min.x,i&2?bounds.max.y:bounds.min.y,i&4?bounds.max.z:bounds.min.z).applyMatrix4(camera.matrixWorldInverse);minX=Math.min(minX,p.x);maxX=Math.max(maxX,p.x);minY=Math.min(minY,p.y);maxY=Math.max(maxY,p.y);}const aspect=width/height;const half=Math.max((maxY-minY)/2,(maxX-minX)/aspect/2)*1.085/zoom;const centerY=(minY+maxY)/2,centerX=(minX+maxX)/2;camera.left=centerX-half*aspect;camera.right=centerX+half*aspect;camera.top=centerY+half;camera.bottom=centerY-half;camera.updateProjectionMatrix();dirty=true;}
// Level one: tap to walk, tap the crate to push, enter the unlocked tunnel.
const heroShadow=contact(hero.position.x,hero.position.z,1.1,.9,.65);
const crateShadow=contact(crate.position.x,crate.position.z,1.7,1.7,.65);
const feet=[hero.children[1],hero.children[2]];
const armMeshes=[hero.children[12],hero.children[13]];
const hands=hero.children.filter(o=>o.isMesh&&o.position.z>.37&&o.position.y<.75);
const plateMeshes=world.children.filter(o=>o.isMesh&&Math.abs(o.position.x-px)<.01&&Math.abs(o.position.z-pz)<.01&&o.position.y>.09&&o.position.y<.21);
const initialPlate=plateMeshes.map(m=>m.position.y);
const gateBaseMaterial=gateIcon.material.clone();gateIcon.material=gateBaseMaterial;
const successColor=new THREE.Color('#b9df85');
const raycaster=new THREE.Raycaster(),pointer=new THREE.Vector2(),floorPlane=new THREE.Plane(new THREE.Vector3(0,1,0),-.065);
let route=[],afterRoute=null,mode='idle',solved=false,gateOpen=0,finishedAt=0,elapsed=0,pushStart=null;

// The second room reuses the same small procedural pieces.
const secondCrate=crate.clone(true);world.add(secondCrate);secondCrate.visible=false;
const secondShadow=contact(0,0,1.7,1.7,.65);secondShadow.visible=false;
const levelTwoDecor=new THREE.Group();world.add(levelTwoDecor);levelTwoDecor.visible=false;
const secondPlates=[];
for(const x of [-1.65,1.75]){
 const group=new THREE.Group();group.position.set(x,0,-1.7);levelTwoDecor.add(group);
 box(.91,.075,.91,0,.102,0,goldDark,.055,group);
 const top=box(.84,.09,.84,0,.145,0,gold.clone(),.06,group);
 box(.64,.022,.64,0,.2,0,mat('#f7da7a'),.025,group);
 const icon=triangle(.39,goldDark.clone());icon.rotation.x=-Math.PI/2;icon.position.set(0,.22,0);group.add(icon);
 secondPlates.push({group,top,icon});
 box(.09,.024,1.14,x,.078,-2.73,gold,.01,levelTwoDecor);
}
box(3.4,.024,.09,.05,.078,-3.25,gold,.01,levelTwoDecor);
let level=1,puzzles=[],activePuzzle=null;
// Rooms 3–10: reusable mechanisms; every action requires reaching its object.
const puzzleColors=['#e8b74f','#75b9d3','#bd91ce','#df8b78'];
const challengeRoot=new THREE.Group();world.add(challengeRoot);
let challenge=null,interactionObjects=[],mechanisms=[],challengeRects=[],beamParts=[];
const roomDefs={
 1:{start:[-.76,1.35],walls:[],keys:[[-2.7,-2,0]],needKeys:1},
 2:{start:[-1.65,2.4],walls:[],sequence:{pads:[[-2.7,-2.35],[2.8,2.6],[-2.8,2.6]],order:[1,0,2,1]},needSequence:true},
 3:{start:[-2.5,2.45],walls:[[-3.63,0,.86,.3],[1.075,0,5.55,.3],[0,-2.08,.28,1.85],[0,1.9,.28,1.15]],
    keys:[[2.5,2.1,0]],doors:[[-2.45,0,1.5,.3,'lock',0]],gems:[[2.7,-1.8,0]],goalGems:1},
 4:{start:[0,2.6],walls:[[0,-2.02,.28,2.76]],moat:true,
    bridges:[[-2.3,'choice',0],[2.3,'choice',1]],levers:[[0,1.5,0]],gems:[[-2.3,-2,0],[2.3,-2,1]],goalGems:3},
 5:{start:[0,2.65],walls:[[-1.55,-1,4.9,.3],[3.32,-1,1.35,.3],[0,1.8,.3,1.05]],
    circuit:{count:3,masks:[3,5,1],positions:[[-2.6,.7],[0,.4],[2.6,.7]]},doors:[[1.75,-1,1.6,.3,'circuit',0]],gems:[[-2.7,-2.2,0]],goalGems:1,needCircuit:true},
 6:{start:[-.1,2.65],walls:[[.15,0,2.45,.32]],
    optics:{source:[-3.35,1.8,1,0],mirrors:[[-1.8,1.8,1],[-1.8,-1.7,0],[2,-1.7,0],[-3.1,-1.7,0]],receiver:[2,1.8]},needLight:true},
 7:{start:[0,2.6],walls:[[0,0,5.15,.32]],sequence:{pads:[[-2.6,1.8],[2.6,1.8],[-2.6,-1.7],[2.6,-1.7]],order:[2,0,3,1,2]},needSequence:true},
 8:{start:[1.4,2.5],walls:[[-.6,-1.91,.3,3.08],[-2.3,-.3,3.4,.3],[.3,0,1.8,.3],[3.6,0,.8,.3]],
    portals:[[-2.5,1.8,-2.6,-1.6]],keys:[[-1.4,-2.5,0]],doors:[[2.2,0,1.8,.3,'lock',0]],gems:[[2.5,-1.7,0]],goalGems:1},
 9:{start:[-.1,2.7],walls:[[0,-2.02,.28,2.76]],moat:true,
    bridges:[[-2.3,'choice',0],[2.3,'litChoice',1]],levers:[[0,1.4,0]],keys:[[-2.3,-2,0]],gems:[[2.3,-2,0]],goalGems:1,needKeys:1,needLight:true,
    optics:{source:[-3.35,2.45,1,0],mirrors:[[-1.8,2.45,0],[-1.8,1.05,1],[2.55,1.05,0]],receiver:[2.55,2.65]}},
 10:{start:[0,2.95],walls:[[0,-2.02,.28,2.76]],moat:true,
    bridges:[[-2.3,'circuit',0],[2.3,'final',0]],keys:[[-2.3,-2,0]],gems:[[2.3,-2,0]],goalGems:1,needCircuit:true,needSequence:true,needKeys:1,
    circuit:{count:4,masks:[3,5,9,14],positions:[[-3,1.1],[-1,1.1],[1,1.1],[3,1.1]]},
    sequence:{pads:[[-2.65,2.5],[0,2.5],[2.65,2.5]],order:[2,0,1,2,1]}}
};
// More advanced rooms retain the same touch vocabulary and introduce linked mechanisms.
Object.assign(roomDefs,{
 11:{start:[0,2.7],walls:[[-1.6,-.85,4.8,.3],[3.35,-.85,1.3,.3]],dials:{positions:[[-2.5,1.15],[0,2],[2.5,1.15]],links:[[1,1,0],[0,1,1],[1,0,1]],target:[2,1,3]},doors:[[1.7,-.85,1.8,.3,'dials',0]],keys:[[-2.7,-2.1,0]],needKeys:1,needDials:true},
 12:{start:[0,2.8],walls:[[-1.6,-1.2,4.8,.3],[3.35,-1.2,1.3,.3]],balance:{at:[0,0],weights:[[-3,1.9,1],[-1,1.9,2],[1,1.9,3],[3,1.9,4]]},doors:[[1.7,-1.2,1.8,.3,'balance',0]],gems:[[-2.6,-2.3,0]],goalGems:1,needBalance:true},
 13:{storeys:true,start:[0,2.8],walls:[],stairs:[[-2.9,'circuit',0]],circuit:{count:4,masks:[3,5,9,14],positions:[[-3,2.25],[-1,2.25],[1,2.25],[3,2.25]]},keys:[[2.7,-1.9,0]],needKeys:1,needCircuit:true},
 14:{storeys:true,start:[0,2.8],walls:[],stairs:[[-2.9,'always',0]],dials:{positions:[[-1.2,2.2],[1.2,2.2],[.6,-1.8]],links:[[1,1,0],[0,1,1],[1,0,1]],target:[3,2,1]},needDials:true},
 15:{storeys:true,start:[0,2.8],walls:[],stairs:[[-2.9,'always',0]],balance:{at:[1.1,-1.9],weights:[[-1.3,2.1,1],[1.3,2.1,2],[-1.2,-2.3,3]]},needBalance:true},
 16:{storeys:true,start:[0,2.9],walls:[],stairs:[[-2.9,'light',0]],optics:{source:[-3.5,2.65,1,0],mirrors:[[-1.7,2.65,1],[-1.7,1.45,1],[1.6,1.45,0]],receiver:[1.6,2.65]},sequence:{pads:[[-1.8,-2],[.4,-2],[2.6,-2]],order:[2,0,1,2,1]},needLight:true,needSequence:true},
 17:{storeys:true,start:[0,2.8],walls:[[0,-2.2,.3,2.3]],stairs:[[-2.9,'choice',0],[2.9,'keyChoice',1]],levers:[[0,2.1,0]],keys:[[-1.6,-1.8,0]],dials:{positions:[[1.3,-1.75],[2.5,-2.5]],links:[[1,1],[1,0]],target:[3,1]},needKeys:1,needDials:true},
 18:{storeys:true,start:[0,2.95],walls:[[0,-2.2,.3,2.3]],stairs:[],portals:[[-2.9,1.8,-2.9,-1.8],[2.9,1.8,2.9,-1.8]],sequence:{pads:[[-.9,2.5],[.9,2.5],[-1.8,-2.1],[1.8,-2.1]],order:[2,0,3,1,2,3]},keys:[[-.9,-1.4,0]],needKeys:1,needSequence:true},
 19:{storeys:true,start:[0,2.95],walls:[],stairs:[[-2.9,'circuit',0]],circuit:{count:4,masks:[3,5,9,14],positions:[[-3,2.5],[-1,2.5],[1,2.5],[3,2.5]]},balance:{at:[.6,-1.9],weights:[[-2,1.5,1],[0,1.5,2],[2,1.5,2],[-1.6,-2.3,3],[2.8,-2.3,4]]},needCircuit:true,needBalance:true},
 20:{storeys:true,start:[0,2.95],walls:[[0,-2.2,.3,2.3]],stairs:[[-2.9,'choice',0],[2.9,'keyChoice',1]],levers:[[0,1.5,0]],dials:{positions:[[-1.1,2.5],[1.1,2.5],[2.8,-2.5]],links:[[1,1,0],[0,1,1],[1,0,1]],target:[1,3,2]},sequence:{pads:[[-2.1,1.6],[2.1,1.6],[-1.4,-2.4],[1.4,-2.4]],order:[2,0,3,1,2,3]},keys:[[-1.4,-1.4,0]],gems:[[1.4,-1.4,0]],goalGems:1,needKeys:1,needDials:true,needSequence:true}
});
const upperHeight=2.1;
function surfaceY(x,z){return roomDefs[level]?.storeys?upperHeight*THREE.MathUtils.clamp((.95-z)/1.9,0,1):0;}
function exitY(){return roomDefs[level]?.storeys?upperHeight:0;}
function dialsMatch(){return !!challenge?.def.dials&&challenge.dialValues.every((v,i)=>v===challenge.def.dials.target[i]);}
function balanced(){const c=challenge;if(!c?.def.balance)return false;const sum=[0,0];c.weightPlaces.forEach((p,i)=>{if(p===0||p===1)sum[p]+=c.def.balance.weights[i][2];});return c.weightPlaces.every(p=>p===0||p===1)&&sum[0]===sum[1]&&sum[0]>0;}
const carryGroup=new THREE.Group();hero.add(carryGroup);carryGroup.position.set(0,1.65,0);carryGroup.visible=false;
const carriedBalls=[];for(let i=0;i<4;i++)carriedBalls.push(oval((i%2-.5)*.15,Math.floor(i/2)*.15,0,.082,.082,.082,gold,carryGroup));
function buildStoreys(def){
 if(!def.storeys)return;
 // The rear mezzanine leaves the lower courtyard and both stairways visible.
 box(8.02,.24,2.53,0,upperHeight-.07,-2.22,teal,.1,challengeRoot);
 for(let x=0;x<8;x++)for(let z=0;z<3;z++)box(.984,.08,.81,x-3.5,upperHeight+.02,-1.36-z*.83,cream,.025,challengeRoot);
 for(const x of[-3.55,0,3.55])box(.28,upperHeight,.3,x,upperHeight/2,-1.23,teal,.07,challengeRoot);
 box(7.5,.27,.3,0,upperHeight-.32,-1.23,tealTop,.06,challengeRoot);
 for(const x of[-4.01,4.01])box(.2,.52,2.6,x,upperHeight+.32,-2.2,teal,.07,challengeRoot);
 for(let x=0;x<8;x++)if(x<5||x>6)box(.97,.52,.2,x-3.5,upperHeight+.32,-3.48,teal,.06,challengeRoot);
 const spans=def.stairs.map(s=>[s[0]-.65,s[0]+.65]).sort((a,b)=>a[0]-b[0]);let left=-4;
 for(const[a,b]of spans){if(a>left){challengeRects.push([left-.28,a+.28,-1.24,1.24]);box(a-left,.28,.17,(left+a)/2,upperHeight+.18,-.97,tealTop,.055,challengeRoot);}left=b;}
 if(left<4){challengeRects.push([left-.28,4.28,-1.24,1.24]);box(4-left,.28,.17,(left+4)/2,upperHeight+.18,-.97,tealTop,.055,challengeRoot);}
 for(const[x,condition,id]of def.stairs){
  for(let i=0;i<12;i++){const h=(i+1)/12*upperHeight;box(1.28,h,.172,x,h/2+.06,.95-(i+.5)*1.9/12,cream,.024,challengeRoot).userData.walkSurface=true;}
  for(const side of[-1,1]){const a=new THREE.Vector3(x+side*.64,.45,.97),b=new THREE.Vector3(x+side*.64,upperHeight+.45,-.97);mesh(new THREE.TubeGeometry(new THREE.LineCurve3(a,b),1,.035,8,false),tealTop,0,0,0,challengeRoot);}
  if(condition!=='always'){const g=groupAt(x,1.02);for(let i=-2;i<=2;i++)box(.07,.75,.09,i*.23,.43,0,gold,.02,g);box(1.24,.08,.09,0,.8,0,gold,.025,g);mechanisms.push({kind:'door',group:g,condition,id,rect:[x-.94,x+.94,-1.24,1.24],open:0,baseY:0});}
 }
}
function buildAdvanced(def){
 const c=challenge;c.dialValues=(def.dials?.initial||def.dials?.target.map(()=>0)||[]).slice();c.weightPlaces=def.balance?.weights.map(()=>-1)||[];c.carried=-1;c.pans=[];carryGroup.visible=false;
 if(def.dials){const cfg=def.dials;cfg.positions.forEach(([x,z],i)=>addInteractive('dial',x,z,{id:i},(g,o)=>{
  mesh(new THREE.CylinderGeometry(.39,.43,.14,32),teal,0,.16,0,g);
  for(let j=0;j<4;j++){const a=j*Math.PI/2;box(.055,.024,.1,Math.sin(a)*.32,.25,Math.cos(a)*.32,white,.015,g);}
  const needle=triangle(.27,mat(puzzleColors[i]));needle.rotation.set(-Math.PI/2,0,Math.PI);needle.position.set(0,.3,0);const rotor=new THREE.Group();rotor.add(needle);g.add(rotor);o.rotor=rotor;
  const target=cfg.target[i]*Math.PI/2;emblem(i,gold,g,Math.sin(target)*.47,.17,Math.cos(target)*.47,.055);
  for(let j=0;j<cfg.target.length;j++)if(cfg.links[i][j])emblem(j,mat(puzzleColors[j]),g,(j-(cfg.target.length-1)/2)*.15,.26,-.23,.036);
 }));}
 if(def.balance){const cfg=def.balance,[x,z]=cfg.at;const frame=groupAt(x,z);box(.27,.85,.27,0,.49,0,teal,.045,frame);const beam=box(2.12,.1,.12,0,.85,0,gold,.035,frame);c.scaleBeam=beam;
  for(let side=0;side<2;side++)addInteractive('pan',x+(side? .9:-.9),z,{id:side},(g,o)=>{mesh(new THREE.CylinderGeometry(.39,.33,.08,24),goldDark,0,.34,0,g);const plate=mesh(new THREE.CylinderGeometry(.36,.36,.035,24),cream,0,.395,0,g);box(.035,.43,.035,0,.61,0,gold,.015,g);o.pile=new THREE.Group();o.pile.position.y=.47;g.add(o.pile);o.balls=[];for(let j=0;j<12;j++){const ball=oval((j%3-1)*.15,Math.floor(j/6)*.15,(Math.floor(j/3)%2-.5)*.16,.074,.074,.074,orange,o.pile);o.balls.push(ball);}c.pans.push(o);});
  cfg.weights.forEach(([wx,wz,value],i)=>addInteractive('weight',wx,wz,{id:i,value},(g,o)=>{mesh(new THREE.CylinderGeometry(.29,.33,.09,24),teal,0,.12,0,g);for(let j=0;j<value;j++)oval((j%2-.5)*.17,.26+Math.floor(j/2)*.16,0,.09,.09,.09,gold,g);const handle=mesh(new THREE.TorusGeometry(.1,.025,8,20),goldDark,0,.35+Math.floor((value-1)/2)*.16,0,g);o.handle=handle;}));
 }
}
function activateAdvanced(o){
 const c=challenge;if(activateAtrium(o))return true;
 if(o.type==='dial'){const prev=c.dialValues.slice();c.def.dials.links[o.id].forEach((amount,i)=>c.dialValues[i]=(c.dialValues[i]+amount)%4);if(blocked(hero.position.x,hero.position.z)){c.dialValues=prev;rejectObject(o);return true;}tone(285+o.id*65,.16);return true;}
 if(o.type==='weight'){if(c.carried!==-1){rejectObject(o);return true;}c.carried=o.id;c.weightPlaces[o.id]=2;tone(245,.13);return true;}
 if(o.type==='pan'){const old=c.weightPlaces.slice(),oldCarried=c.carried;if(c.carried!==-1){c.weightPlaces[c.carried]=o.id;c.carried=-1;}else{const take=c.weightPlaces.lastIndexOf(o.id);if(take<0){rejectObject(o);return true;}c.carried=take;c.weightPlaces[take]=2;}
  if(blocked(hero.position.x,hero.position.z)){c.weightPlaces=old;c.carried=oldCarried;rejectObject(o);return true;}tone(196+o.id*66,.18);return true;}
 return false;
}
function refreshAdvanced(){const c=challenge;if(!c)return;refreshAtrium();
 for(const o of interactionObjects){if(o.type==='weight')o.group.visible=c.weightPlaces[o.id]===-1;if(o.type==='dial'){o.rotor.rotation.y=c.dialValues[o.id]*Math.PI/2;}}
 carryGroup.visible=c.carried>=0;const value=c.carried>=0?c.def.balance.weights[c.carried][2]:0;carriedBalls.forEach((b,i)=>b.visible=i<value);
 if(c.def.balance){const sum=[0,0];c.weightPlaces.forEach((p,i)=>{if(p===0||p===1)sum[p]+=c.def.balance.weights[i][2];});c.scaleBeam.rotation.z=(sum[0]-sum[1])*.025;c.pans.forEach((o,i)=>{o.group.position.y=surfaceY(o.x,o.z)+(i?1:-1)*Math.sin(c.scaleBeam.rotation.z)*.9;o.pile.children.forEach((b,j)=>b.visible=j<sum[i]);});}
}
function positionExit(){for(const p of exitPieces)p.object.position.y=p.y+exitY();}

// Test room: connected indoor passages, a liftable brick and a small courtyard pool.
roomDefs[21]={start:[0,2.6],walls:[[-3.65,.8,.7,.3],[0,.8,3.8,.3],[3.65,.8,.7,.3],[0,-1.55,.3,3.9],[1,-1.1,2,.3]],doors:[[2.6,.8,1.4,.3,'lock',0]],keys:[[-2.05,-2.95,0]],gems:[[.95,-2.4,0]],needKeys:1,goalGems:1,poolRoom:true};
const heldBrick=new THREE.Group();hero.add(heldBrick);heldBrick.position.set(0,.65,.5);heldBrick.scale.setScalar(.72);heldBrick.visible=false;
function brickShape(g){box(.92,.39,.56,0,.27,0,crateMat,.07,g);for(const x of[-.22,.22])box(.15,.012,.25,x,.469,0,goldDark,.045,g);}
brickShape(heldBrick);
function buildAtrium(def){
 heldBrick.visible=false;if(!def.poolRoom)return;const c=challenge;c.brickMode='floor';c.brickAt={x:-2.6,z:.8};c.brickRect=rectFor(-2.6,.8,.92,.56);c.poolRipples=[];
 for(const[x,z]of[[-2.6,.8],[2.6,.8],[2.8,-1.1]]){
  const geo=new THREE.ExtrudeGeometry(archShape(.85,.7,.91),{depth:.21,steps:1,curveSegments:20,bevelEnabled:true,bevelSize:.025,bevelThickness:.025,bevelSegments:2});mesh(geo,tealTop,x,.06,z-.1,challengeRoot);
  for(const side of[-1,1])challengeRects.push(rectFor(x+side*.775,z,.15,.25));
 }
 // Coping sits above a blue tiled basin; the stepping-stone lane has open ends.
 box(2.9,.025,2.1,-2.05,.07,-1.45,mat('#3d92ad'),.01,challengeRoot);
 for(let x=0;x<10;x++)for(let z=0;z<7;z++)box(.278,.008,.278,-3.35+x*.289,.087,-2.34+z*.295,mat((x+z)%2?'#70bdcc':'#65b1c5'),.008,challengeRoot);
 const water=mesh(new THREE.PlaneGeometry(2.86,2.06),new THREE.MeshStandardMaterial({color:'#5bc9d5',roughness:.25,transparent:true,opacity:.6,depthWrite:false}),-2.05,.096,-1.45,challengeRoot);water.rotation.x=-Math.PI/2;water.castShadow=false;
 for(const x of[-3.55,-.55])box(.15,.19,2.3,x,.15,-1.45,cream,.055,challengeRoot);
 for(const z of[-2.55,-.35])for(const[x,w]of[[-3.08,.92],[-1.02,.92]])box(w,.19,.15,x,.15,z,cream,.045,challengeRoot);
 for(const x of[-3.5,-.6])for(const z of[-2.5,-.4])box(.2,.2,.2,x,.15,z,cream,.07,challengeRoot);
 for(let i=0;i<3;i++){const r=mesh(new THREE.RingGeometry(.13,.145,32),new THREE.MeshBasicMaterial({color:'#c8edf0',transparent:true,opacity:.3,depthWrite:false,side:THREE.DoubleSide}),i===1?-1.1:-3,.103,-2.05+i*.6,challengeRoot);r.rotation.x=-Math.PI/2;r.castShadow=false;c.poolRipples.push(r);}
 for(const z of[-1.65,-1.25]){const pts=[new THREE.Vector3(-.35,.16,z),new THREE.Vector3(-.35,.47,z),new THREE.Vector3(-.65,.47,z),new THREE.Vector3(-.78,.15,z)];mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts),16,.025,8,false),white,0,0,0,challengeRoot);}for(const y of[.19,.31])box(.035,.035,.4,-.74,y,-1.45,white,.012,challengeRoot);
 challengeRects.push([-3.85,-2.72,-2.86,-.04],[-1.38,-.25,-2.86,-.04]);
 const bridge=groupAt(-2.05,-1.45);for(let i=0;i<5;i++)box(1.1,.08,.425,0,.075,-.85+i*.425,tealTop,.035,bridge);
 mechanisms.push({kind:'bridge',group:bridge,condition:'brickSocket',id:0,rect:[-2.72,-1.38,-2.86,-.04],open:0});
 c.brick=addInteractive('brick',-2.6,.8,{id:0},g=>brickShape(g));
 c.socket=addInteractive('brickSocket',-3.35,.08,{id:0},g=>{box(1,.075,.64,0,.101,0,goldDark,.045,g);box(.83,.025,.46,0,.153,0,mat('#f3d878'),.035,g);emblem(2,goldDark,g,0,.175,0,.12);});
 // A matching inset leads from the brick plate toward the stones.
 box(.8,.018,.065,-2.76,.077,-.12,gold,.01,challengeRoot);
}
function setBrick(mode,x,z){const c=challenge;c.brickMode=mode;if(mode!=='carried'){c.brickAt={x,z};c.brick.x=x;c.brick.z=z;c.brick.group.position.set(x,0,z);c.brickRect=rectFor(x,z,.92,.56);}refreshRoom();}
function liftBrick(o){const c=challenge,old=c.brickMode;c.brickMode='carried';if(blocked(hero.position.x,hero.position.z)){c.brickMode=old;rejectObject(o);return;}setBrick('carried');tone(230,.15);}
function activateAtrium(o){if(!challenge.def.poolRoom)return false;
 if(o.type==='brick'){liftBrick(o);return true;}
 if(o.type==='brickSocket'){if(challenge.brickMode==='socket'){liftBrick(challenge.brick);return true;}if(challenge.brickMode!=='carried'){rejectObject(o);return true;}const r=rectFor(o.x,o.z,.92,.56);if(hero.position.x>r[0]&&hero.position.x<r[1]&&hero.position.z>r[2]&&hero.position.z<r[3]){rejectObject(o);return true;}setBrick('socket',o.x,o.z);tone(440,.2);return true;}return false;
}
function dropBrick(){const c=challenge;if(!c?.def.poolRoom||c.brickMode!=='carried')return;
 const obstacles=activeRoomRects();for(let i=0;i<8;i++){const a=hero.rotation.y+i*Math.PI/4,x=hero.position.x+Math.sin(a)*1.12,z=hero.position.z+Math.cos(a)*1.12,r=[x-.47,x+.47,z-.29,z+.29];if(x< -3.45||x>3.45||z< -2.75||z>2.7)continue;if(obstacles.some(q=>r[0]<q[1]&&r[1]>q[0]&&r[2]<q[3]&&r[3]>q[2]))continue;route=[];afterRoute=null;mode='idle';setBrick('floor',x,z);tone(185,.12);return;}tone(160,.12);
}
function refreshAtrium(){const c=challenge;heldBrick.visible=!!c?.def.poolRoom&&c.brickMode==='carried';if(c?.def.poolRoom)c.brick.group.visible=c.brickMode!=='carried';}

const progressStuds=[];for(let i=0;i<21;i++){const stud=oval(-1.8+i*.19,.74,3.58,.07,.035,.065,gold.clone());progressStuds.push(stud);}
// Temporary test navigation; one flag removes both the picker and its reserved space.
const ENABLE_LEVEL_TEST_NAV=true;
const levelNav=document.getElementById('stage-nav'),levelButtons=[];
document.documentElement.classList.toggle('testing-levels',ENABLE_LEVEL_TEST_NAV);
levelNav.hidden=!ENABLE_LEVEL_TEST_NAV;
if(ENABLE_LEVEL_TEST_NAV)for(let n=1;n<=21;n++){
 const button=document.createElement('button');button.type='button';button.textContent=String(n);button.setAttribute('aria-label','المرحلة '+n);
 button.addEventListener('click',()=>{points.clear();gesture=false;loadLevel(n);});levelNav.appendChild(button);levelButtons.push(button);
}
function syncLevelPicker(){levelButtons.forEach((button,i)=>{if(i+1===level)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current');});}

function saveProgress(){try{window.localStorage.setItem('aboden-puzzle-level',String(level));}catch{}}
function restoredLevel(){try{const n=Number(window.localStorage.getItem('aboden-puzzle-level'));return Number.isInteger(n)&&n>=1&&n<=21?n:1;}catch{return 1;}}
function groupAt(x,z){const g=new THREE.Group();g.position.set(x,surfaceY(x,z),z);challengeRoot.add(g);return g;}
function emblem(index,material,parent,x=0,y=.2,z=0,size=.18){
 let o;if(index%4===0){o=mesh(new THREE.TorusGeometry(size,.035,8,24),material,x,y,z,parent);o.rotation.x=-Math.PI/2;}
 else if(index%4===1){o=triangle(size*2,material);o.rotation.x=-Math.PI/2;o.position.set(x,y,z);parent.add(o);}
 else if(index%4===2){o=box(size*1.6,.045,size*1.6,x,y,z,material,.025,parent);o.rotation.y=Math.PI/4;}
 else{o=box(size*1.9,.045,.075,x,y,z,material,.02,parent);box(.075,.045,size*1.9,x,y,z,material,.02,parent);}
 return o;
}
function addInteractive(type,x,z,data={},make){const group=groupAt(x,z);const obj={type,x,z,group,...data};group.userData.interaction=obj;interactionObjects.push(obj);make?.(group,obj);return obj;}
function disposeRoom(){
 // Rounded geometries are cached and reused; dispose only room-owned resources.
 const sharedGeometries=new Set(roundedCache.values()),sharedMaterials=new Set([teal,tealTop,cream,orange,crateMat,cratePanel,gold,goldDark,white,black,bagMat]);
 const geometries=new Set(),materials=new Set();challengeRoot.traverse(o=>{if(o.isMesh){if(!sharedGeometries.has(o.geometry))geometries.add(o.geometry);for(const m of Array.isArray(o.material)?o.material:[o.material])if(!sharedMaterials.has(m))materials.add(m);}});
 geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());challengeRoot.clear();interactionObjects=[];mechanisms=[];challengeRects=[];beamParts=[];
}
function roomCondition(type,id=0){const c=challenge;if(!c)return false;switch(type){case'brickSocket':return c.brickMode==='socket';case'dials':return dialsMatch();case'balance':return balanced();case'light':return c.light;case'keyChoice':return c.choice===id&&!!(c.keys&1);case'lock':return !!(c.unlocked&(1<<id));case'choice':return c.choice===id;case'litChoice':return c.choice===id&&c.light;case'circuit':return c.bits===(1<<c.def.circuit.count)-1;case'final':return !!(c.keys&1)&&c.sequence===c.def.sequence.order.length;default:return true;}}
function activeRoomRects(){if(!challenge)return [];const r=challengeRects.slice();if(challenge.def.poolRoom&&challenge.brickMode!=='carried')r.push(challenge.brickRect);for(const m of mechanisms)if(!roomCondition(m.condition,m.id))r.push(m.rect);return r;}
function rectFor(x,z,w,d,pad=.29){return[x-w/2-pad,x+w/2+pad,z-d/2-pad,z+d/2+pad];}
function buildRoom(){
 disposeRoom();const def=roomDefs[level];challenge={def,keys:0,gems:0,unlocked:0,choice:0,bits:0,sequence:0,light:false,mirrors:[],lamps:[],clues:[],feedbackAt:-10};
 if(level>=3){puzzles=[];hero.position.set(def.start[0],.07,def.start[1]);}
 buildStoreys(def);
 for(const[x,z,w,d]of def.walls){box(w,.73,d,x,surfaceY(x,z)+.425,z,teal,.095,challengeRoot);challengeRects.push(rectFor(x,z,w,d));}
 if(def.moat){
  box(7.97,.05,1.22,0,.069,0,mat('#4c8caa'),.025,challengeRoot);
  for(let i=0;i<14;i++)box(.19,.008,.025,-3.7+i*.55,.101,Math.sin(i*4)*.32,mat('#91c3cf'),.008,challengeRoot);
  // Non-crossable water strips have no hidden full-floor collision shortcut.
  const spans=def.bridges.map(b=>[b[0]-.65,b[0]+.65]).sort((a,b)=>a[0]-b[0]);let left=-4;
  for(const[a,b]of spans){if(a>left)challengeRects.push([left-.28,a+.28,-.89,.89]);left=b;}
  if(left<4)challengeRects.push([left-.28,4.3,-.89,.89]);
  for(const[x,condition,id]of def.bridges){const group=groupAt(x,0);for(let j=0;j<6;j++)box(1.25,.13,.22,0,.1,-.6+j*.24,mat('#d5b07b'),.035,group);
   for(const side of[-1,1])box(.045,.045,1.48,side*.55,.185,0,gold,.018,group);
   const m={kind:'bridge',group,condition,id,rect:[x-.93,x+.93,-.89,.89],open:0};mechanisms.push(m);
  }
 }
 for(const[x,z,w,d,condition,id]of def.doors||[]){const group=groupAt(x,z);for(let j=-2;j<=2;j++)box(.09,.8,.12,j*w/5,.48,0,condition==='lock'?gold:tealTop,.035,group);box(w,.1,.17,0,.9,0,condition==='lock'?gold:tealTop,.045,group);
  const m={kind:'door',group,condition,id,rect:rectFor(x,z,w,d),open:0,baseY:surfaceY(x,z)};mechanisms.push(m);
  if(condition==='lock'){const obj={type:'lock',x,z,id,group};group.userData.interaction=obj;interactionObjects.push(obj);const face=box(.33,.38,.15,0,.55,.14,goldDark,.06,group);oval(0,.61,.23,.052,.063,.012,black,group);box(.055,.11,.025,0,.53,.23,black,.015,group);}
 }
 for(const[x,z,id]of def.keys||[])addInteractive('key',x,z,{id},g=>{const color=mat(puzzleColors[id]);const ring=mesh(new THREE.TorusGeometry(.14,.045,10,24),color,0,.56,0,g);box(.085,.4,.085,0,.31,0,color,.028,g);box(.2,.07,.08,.055,.2,0,color,.02,g);emblem(id,color,g,0,.1,0,.25);});
 for(const[x,z,id]of def.gems||[])addInteractive('gem',x,z,{id},g=>{mesh(new THREE.OctahedronGeometry(.23,0),mat('#f6d871'),0,.58,0,g);const ring=mesh(new THREE.TorusGeometry(.32,.025,8,32),gold,0,.11,0,g);ring.rotation.x=-Math.PI/2;});
 for(const[x,z,id]of def.levers||[])addInteractive('lever',x,z,{id},(g,o)=>{box(.58,.13,.55,0,.15,0,teal,.06,g);o.arm=box(.085,.49,.085,0,.43,0,gold,.025,g);oval(0,.68,0,.12,.12,.12,orange,g);emblem(1,gold,g,-.45,.1,0,.12);emblem(1,gold,g,.45,.1,0,.12);});
 if(def.circuit){const cfg=def.circuit;cfg.positions.forEach(([x,z],i)=>addInteractive('circuit',x,z,{id:i,mask:cfg.masks[i]},(g,o)=>{box(.62,.14,.62,0,.16,0,teal,.07,g);o.cap=box(.46,.09,.46,0,.27,0,mat('#c3d7cb'),.06,g);for(let j=0;j<cfg.count;j++)if(cfg.masks[i]&(1<<j))emblem(j,mat(puzzleColors[j]),g,(j-(cfg.count-1)/2)*.14,.33,0,.045);}));
  box(1.5,.18,.44,1.75,exitY()+.14,-2.95,teal,.07,challengeRoot);
  for(let i=0;i<cfg.count;i++){const lamp=emblem(i,mat('#55777b'),challengeRoot,1.75+(i-(cfg.count-1)/2)*.34,exitY()+.27,-2.95,.115);challenge.lamps.push(lamp);}
 }
 if(def.sequence){const cfg=def.sequence;cfg.pads.forEach(([x,z],i)=>addInteractive('sequence',x,z,{id:i},(g,o)=>{o.cap=box(.66,.11,.66,0,.14,0,mat(puzzleColors[i]),.07,g);emblem(i,white,g,0,.22,0,.18);}));
  const width=cfg.order.length*.42+.15;box(width,.13,.4,-.5,exitY()+.15,-2.87,cream,.055,challengeRoot);
  cfg.order.forEach((id,i)=>{const clue=emblem(id,mat(puzzleColors[id]),challengeRoot,-.5+(i-(cfg.order.length-1)/2)*.42,exitY()+.24,-2.87,.095);challenge.clues.push(clue);});
  const arrow=triangle(.16,gold);arrow.rotation.set(-Math.PI/2,0,-Math.PI/2);arrow.position.set(-.5-width/2-.2,exitY()+.18,-2.87);challengeRoot.add(arrow);
 }
 for(const[a,b,c,d]of def.portals||[]){for(const[x,z,tx,tz]of[[a,b,c,d],[c,d,a,b]])addInteractive('portal',x,z,{tx,tz},g=>{box(.88,.07,.88,0,.11,0,mat('#8474ad'),.12,g);for(const r of[.22,.37]){const ring=mesh(new THREE.TorusGeometry(r,.032,8,32),mat('#d7bee9'),0,.19,0,g);ring.rotation.x=-Math.PI/2;}oval(0,.24,0,.075,.075,.075,white,g);});}
 if(def.optics){const cfg=def.optics;const source=groupAt(cfg.source[0],cfg.source[1]);box(.26,.38,.33,0,.28,0,teal,.05,source);oval(.16,.42,0,.055,.105,.1,gold,source);
  cfg.mirrors.forEach(([x,z,dir],i)=>{const o=addInteractive('mirror',x,z,{id:i,dir},(g,o)=>{const base=mesh(new THREE.CylinderGeometry(.33,.37,.12,24),teal,0,.13,0,g);o.glass=box(.63,.48,.065,0,.45,0,mat('#c1dce0',.25),.027,g);o.glass.rotation.y=dir?-Math.PI/4:Math.PI/4;box(.1,.15,.1,0,.25,0,gold,.025,g);const tip=triangle(.16,gold);tip.rotation.x=-Math.PI/2;tip.position.set(0,.22,.38);g.add(tip);});challenge.mirrors.push(o);});
  const rec=groupAt(...cfg.receiver);box(.6,.2,.6,0,.19,0,teal,.065,rec);challenge.receiver=mesh(new THREE.OctahedronGeometry(.2,0),mat('#698b8e'),0,.48,0,rec);
  for(let i=0;i<12;i++){const beam=box(1,.035,.035,0,.45,0,new THREE.MeshBasicMaterial({color:'#ffe6a1',transparent:true,opacity:.82}),.012,challengeRoot);beam.castShadow=false;beam.visible=false;beamParts.push(beam);}
  traceLight();
 }
 buildAdvanced(def);buildAtrium(def);
 // Forgiving touch volumes include the hole in a key and the empty center of a portal.
 const touchMaterial=new THREE.MeshBasicMaterial({transparent:true,opacity:0,depthWrite:false,colorWrite:false});
 for(const o of interactionObjects){const flat=['sequence','portal','circuit','dial'].includes(o.type);const hit=mesh(new THREE.BoxGeometry(flat?.84:.72,flat?.3:.95,flat?.84:.72),touchMaterial,0,flat?.18:.5,0,o.group);hit.castShadow=hit.receiveShadow=false;}
 positionExit();refreshRoom();
}
function traceLight(){
 const c=challenge,cfg=c.def.optics;if(!cfg)return;c.light=false;beamParts.forEach(o=>o.visible=false);let[x,z,dx,dz]=cfg.source;
 for(let bounce=0;bounce<beamParts.length;bounce++){
  let distance=dx>0?(3.82-x):dx<0?(x+3.82):dz>0?(3.25-z):(z+3.25),hit=null;
  const candidates=[...c.mirrors.map(m=>({x:m.x,z:m.z,mirror:m})),{x:cfg.receiver[0],z:cfg.receiver[1],receiver:true}];
  for(const p of candidates){const along=(p.x-x)*dx+(p.z-z)*dz,off=Math.abs((p.x-x)*dz-(p.z-z)*dx);if(along>.02&&off<.08&&along<distance){distance=along;hit=p;}}
  for(const[wx,wz,w,d]of c.def.walls){const loX=wx-w/2,hiX=wx+w/2,loZ=wz-d/2,hiZ=wz+d/2;let along=Infinity;if(dx&&z>loZ&&z<hiZ)along=dx>0?loX-x:x-hiX;if(dz&&x>loX&&x<hiX)along=dz>0?loZ-z:z-hiZ;if(along>.01&&along<distance){distance=along;hit=null;}}
  const beam=beamParts[bounce];beam.visible=true;beam.position.set(x+dx*distance/2,.45,z+dz*distance/2);beam.scale.x=Math.max(.01,distance);beam.rotation.y=dx?0:Math.PI/2;
  if(!hit)break;if(hit.receiver){c.light=true;break;}x=hit.x;z=hit.z;const oldDx=dx;dx=hit.mirror.dir?dz:-dz;dz=hit.mirror.dir?oldDx:-oldDx;
 }
 c.receiver.material.color.set(c.light?'#f4d175':'#698b8e');c.receiver.material.emissive.set(c.light?'#60481c':'#000000');
}
function refreshRoom(){
 const c=challenge;if(!c)return;const d=c.def;const oldSolved=solved;
 solved=puzzles.every(p=>p.done)&&(c.gems&(d.goalGems||0))===(d.goalGems||0)&&(c.keys&(d.needKeys||0))===(d.needKeys||0)&&(!d.needCircuit||roomCondition('circuit'))&&(!d.needSequence||c.sequence===d.sequence.order.length)&&(!d.needLight||c.light)&&(!d.needDials||dialsMatch())&&(!d.needBalance||balanced());
 refreshAdvanced();c.lamps.forEach((m,i)=>{m.material.color.set(c.bits&(1<<i)?puzzleColors[i]:'#55777b');});
 c.clues.forEach((m,i)=>{m.position.y=surfaceY(m.position.x,m.position.z)+(i<c.sequence?.31:.24);m.material.emissive.set(i<c.sequence?'#66592c':'#000000');});
 interactionObjects.forEach(o=>{if(o.type==='key')o.group.visible=!(c.keys&(1<<o.id));if(o.type==='gem')o.group.visible=!(c.gems&(1<<o.id));});
 if(solved&&!oldSolved){tone(659,.22);setTimeout(()=>tone(880,.27),130);}
 renderer.shadowMap.needsUpdate=true;
}
function rejectObject(obj){challenge.feedbackAt=elapsed;challenge.feedbackObject=obj;route=[];afterRoute=null;mode='idle';tone(160,.12,.018);}
function approachObject(obj){
 if(!obj.group.visible||mode==='finishing'||mode==='pushing')return false;
 let best=null,bestLength=Infinity;
 // Interaction points surround an object; line-of-sight prevents touching through walls.
 const candidates=obj.type==='portal'||obj.type==='sequence'?[{x:obj.x,z:obj.z}]:[];
 for(const radius of(obj.type==='brickSocket'?[1,1.15]:obj.type==='brick'?[.85,1.05]:[.62,.83]))for(let i=0;i<12;i++){const a=i/12*Math.PI*2;candidates.push({x:obj.x+Math.cos(a)*radius,z:obj.z+Math.sin(a)*radius});}
 candidates.sort((a,b)=>Math.hypot(a.x-hero.position.x,a.z-hero.position.z)-Math.hypot(b.x-hero.position.x,b.z-hero.position.z));
 for(const p of candidates){if((obj.type==='portal'||obj.type==='sequence')&&Math.hypot(p.x-obj.x,p.z-obj.z)>.05)continue;
  // Only the lock's own gate can interrupt the final arm-length reach.
  const blockers=activeRoomRects().filter(r=>!(obj.type==='brick'&&r===challenge.brickRect)&&!(obj.type==='lock'&&mechanisms.some(m=>m.group===obj.group&&m.rect===r)));
  if(blockers.some(r=>segmentHits(p,{x:obj.x,z:obj.z},r)))continue;
  const path=findPath(hero.position,p);if(!path)continue;let length=0,prev=hero.position;for(const q of path){length+=Math.hypot(q.x-prev.x,q.z-prev.z);prev=q;}if(length<bestLength){bestLength=length;best=path;break;}
 }
 if(!best){rejectObject(obj);return false;}route=best;afterRoute=()=>activateObject(obj);mode='walking';return true;
}
function activateObject(o){
 const c=challenge;if(!c||!o.group.visible)return;route=[];afterRoute=null;
 if(activateAdvanced(o)){refreshRoom();mode='idle';return;}
 switch(o.type){
 case'key':c.keys|=1<<o.id;tone(784,.2);break;
 case'gem':c.gems|=1<<o.id;tone(880,.2);break;
 case'lock':if(!(c.keys&(1<<o.id))){rejectObject(o);return;}c.unlocked|=1<<o.id;tone(330,.2);break;
 case'lever':c.choice=1-c.choice;if(blocked(hero.position.x,hero.position.z)){c.choice=1-c.choice;rejectObject(o);return;}tone(245,.15);break;
 case'circuit':c.bits^=o.mask;if(blocked(hero.position.x,hero.position.z)){c.bits^=o.mask;rejectObject(o);return;}tone(330+o.id*110,.15);break;
 case'sequence':if(c.sequence===c.def.sequence.order.length)return;if(c.def.sequence.order[c.sequence]===o.id){c.sequence++;tone(330+c.sequence*85,.18);}else{c.sequence=0;rejectObject(o);}break;
 case'portal':if(blocked(o.tx,o.tz)){rejectObject(o);return;}hero.position.set(o.tx,surfaceY(o.tx,o.tz)+.07,o.tz);heroShadow.position.set(o.tx,surfaceY(o.tx,o.tz)+.066,o.tz);tone(523,.27);break;
 case'mirror':o.dir=1-o.dir;o.glass.rotation.y=o.dir?-Math.PI/4:Math.PI/4;traceLight();tone(440,.12);break;
 }
 refreshRoom();mode='idle';
}
function pickRoom(){
 const hits=raycaster.intersectObjects(interactionObjects.filter(o=>o.group.visible).map(o=>o.group),true);
 if(hits.length){let g=hits[0].object;while(g&&!g.userData.interaction)g=g.parent;if(g){approachObject(g.userData.interaction);return true;}}
 return false;
}
function updateRoom(dt){if(!challenge)return;if(challenge.def.poolRoom)challenge.poolRipples.forEach((r,i)=>{r.scale.setScalar(1+.25*Math.sin(elapsed*1.5+i*2));r.material.opacity=.2+.08*Math.sin(elapsed+i);});
 for(const m of mechanisms){const open=roomCondition(m.condition,m.id);m.open=THREE.MathUtils.damp(m.open,open?1:0,9,dt);m.group.position.y=(m.baseY||0)+(m.kind==='bridge'?-1.05*(1-m.open):-1.04*m.open);}
 for(const o of interactionObjects){if(o.type==='key'||o.type==='gem'){const item=o.group.children[0];item.rotation.y+=dt*.7;item.position.y=.56+Math.sin(elapsed*2.4+o.x)*.04;}if(o.type==='lever')o.arm.rotation.z=THREE.MathUtils.damp(o.arm.rotation.z,challenge.choice?.48:-.48,9,dt);}
 if(challenge.feedbackObject){const o=challenge.feedbackObject,t=elapsed-challenge.feedbackAt;o.group.rotation.z=t<.35?Math.sin(t*45)*.05:0;if(t>=.35)challenge.feedbackObject=null;}
}

function wallRects(){if(level>=3)return activeRoomRects();return level===1?[[-2.745,.945,-1.165,-.235],[-4.28,-2.22,.685,1.615]]:[[-.455,.455,-2.135,1.535]];}
function loadLevel(number){
 level=number;syncLevelPicker();saveProgress();progressStuds.forEach((s,i)=>{s.material.color.set(i<level?'#f3c858':'#739696');s.scale.y=i===level-1?.06:.035;});levelTwoDecor.visible=level===2;secondCrate.visible=secondShadow.visible=level===2;
 firstPlateParts.forEach(o=>o.visible=level===1);
 dividerB.visible=dividerShadowB.visible=level===1;
 if(level===1){dividerA.position.set(-.9,.485,-.7);dividerA.rotation.y=0;dividerShadowA.position.set(-.9,.065,-.7);dividerShadowA.rotation.z=0;}
 else{dividerA.position.set(0,.485,-.3);dividerA.rotation.y=Math.PI/2;dividerShadowA.position.set(0,.065,-.3);dividerShadowA.rotation.z=Math.PI/2;}
 dividerA.visible=dividerShadowA.visible=level<=2;crate.visible=crateShadow.visible=level<=2;
 if(level<=2){disposeRoom();challenge=null;}
 resetLevel();sceneBounds.max.y=exitY()+2.4;fit();
}

let audioCtx=null;
function tone(freq,duration=.13,gain=.035){try{const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return;if(!audioCtx)audioCtx=new Audio();if(audioCtx.state==='suspended')audioCtx.resume().catch(()=>{});const osc=audioCtx.createOscillator(),vol=audioCtx.createGain(),now=audioCtx.currentTime;osc.type='sine';osc.frequency.setValueAtTime(freq,now);vol.gain.setValueAtTime(0,now);vol.gain.linearRampToValueAtTime(gain,now+.014);vol.gain.exponentialRampToValueAtTime(.0001,now+duration);osc.connect(vol);vol.connect(audioCtx.destination);osc.start();osc.stop(now+duration+.01);}catch{}}
function blocked(x,z,ignoreCrate=false){
 if(z< -3.03){if(!solved||Math.abs(x-archX)>.29||z< -4.43)return true;}
 else if(x< -3.65||x>3.65||z>3.05)return true;
 if(wallRects().some(r=>x>r[0]&&x<r[1]&&z>r[2]&&z<r[3]))return true;
 if(!ignoreCrate&&puzzles.some(p=>Math.abs(x-p.crate.position.x)<.86&&Math.abs(z-p.crate.position.z)<.86))return true;
 return false;
}
function segmentHits(a,b,r){let enter=0,leave=1;for(const [axis,lo,hi]of [['x',r[0],r[1]],['z',r[2],r[3]]]){const d=b[axis]-a[axis];if(Math.abs(d)<1e-9){if(a[axis]<=lo||a[axis]>=hi)return false;}else{let t1=(lo-a[axis])/d,t2=(hi-a[axis])/d;if(t1>t2)[t1,t2]=[t2,t1];enter=Math.max(enter,t1);leave=Math.min(leave,t2);if(enter>=leave)return false;}}return leave>0&&enter<1;}
function clearSegment(a,b,ignoreCrate=false){const obstacles=[...wallRects(),[-100,archX-.29,-100,-3.03],[archX+.29,100,-100,-3.03]];if(!ignoreCrate)obstacles.push(...puzzles.map(p=>[p.crate.position.x-.87,p.crate.position.x+.87,p.crate.position.z-.87,p.crate.position.z+.87]));if(obstacles.some(r=>segmentHits(a,b,r)))return false;const n=Math.max(1,Math.ceil(Math.hypot(b.x-a.x,b.z-a.z)/.05));for(let i=1;i<=n;i++)if(blocked(a.x+(b.x-a.x)*i/n,a.z+(b.z-a.z)*i/n,ignoreCrate))return false;return true;}

function findPath(from,to,ignoreCrate=false){
 if(blocked(to.x,to.z,ignoreCrate))return null;
 const step=.2,nx=37,nz=38,originX=-3.6,originZ=-4.4;
 const point=i=>({x:originX+(i%nx)*step,z:originZ+Math.floor(i/nx)*step});
 function nearest(p){let best=-1,score=Infinity;for(let i=0;i<nx*nz;i++){const q=point(i),d=(p.x-q.x)**2+(p.z-q.z)**2;if(d<score&&!blocked(q.x,q.z,ignoreCrate)&&clearSegment(p,q,ignoreCrate)){score=d;best=i;}}return best;}
 const start=nearest(from),goal=nearest(to);if(start<0||goal<0)return null;
 const prev=new Int32Array(nx*nz).fill(-2),queue=[start];prev[start]=-1;let head=0;
 while(head<queue.length&&prev[goal]===-2){const i=queue[head++],x=i%nx,z=Math.floor(i/nx);for(const[dx,dz]of [[1,0],[-1,0],[0,1],[0,-1]]){const xx=x+dx,zz=z+dz;if(xx<0||xx>=nx||zz<0||zz>=nz)continue;const j=zz*nx+xx;if(prev[j]!==-2)continue;const p=point(j);if(blocked(p.x,p.z,ignoreCrate)||!clearSegment(point(i),p,ignoreCrate))continue;prev[j]=i;queue.push(j);}}
 if(prev[goal]===-2)return null;
 const raw=[];for(let i=goal;i!==-1;i=prev[i])raw.push(point(i));raw.reverse();raw.push({x:to.x,z:to.z});
 const smooth=[];let anchor={x:from.x,z:from.z},index=0;
 while(index<raw.length){let far=index;while(far+1<raw.length&&clearSegment(anchor,raw[far+1],ignoreCrate))far++;smooth.push(raw[far]);anchor=raw[far];index=far+1;}
 return smooth;
}
function walkTo(x,z,done=null){const path=findPath(hero.position,{x,z});if(!path)return false;route=path;afterRoute=done;mode='walking';return true;}
function startPush(puzzle=puzzles.find(p=>!p.done)){if(!puzzle||puzzle.done||mode==='pushing'||mode==='finishing'||mode==='complete')return;const c=puzzle.crate,dx=puzzle.dx,dz=puzzle.dz;walkTo(c.position.x-dx*.95,c.position.z-dz*.95,()=>{mode='pushing';activePuzzle=puzzle;pushStart={time:elapsed,x:c.position.x,z:c.position.z};hero.rotation.y=Math.atan2(dx,dz);tone(185,.22,.018);});}
function startExit(){if(!solved){walkTo(archX,-2.65);return;}walkTo(archX,-4.38,()=>{mode='finishing';finishedAt=elapsed;hero.visible=false;heroShadow.visible=false;for(let i=0;i<sparkles.length;i++){sparkles[i].visible=true;sparkles[i].userData.start=elapsed;}tone(660,.24);setTimeout(()=>tone(880,.32),140);});}
const sparkles=[];for(let i=0;i<16;i++){const star=mesh(new THREE.OctahedronGeometry(.045,0),mat(i%2?'#fff0bb':'#f4cd59'),archX,1.4,frontZ+.15);star.visible=false;star.castShadow=false;sparkles.push(star);}
const destination=new THREE.Mesh(new THREE.RingGeometry(.1,.13,32),new THREE.MeshBasicMaterial({color:'#fff0b3',transparent:true,opacity:0,depthWrite:false,side:THREE.DoubleSide}));destination.rotation.x=-Math.PI/2;destination.position.y=.085;world.add(destination);let markerTime=-10;
function resetLevel(){route=[];afterRoute=null;activePuzzle=null;mode='idle';solved=false;gateOpen=0;gate.position.y=0;
 crate.position.set(level===1?.36:-1.65,.61,level===1?1.35:.7);secondCrate.position.set(1.75,.61,.7);
 hero.position.set(level===1?-.76:-1.65,.07,level===1?1.35:2.4);hero.rotation.set(0,level===1?Math.PI/2:Math.PI,0);hero.scale.set(1,1,1);hero.visible=heroShadow.visible=true;
 puzzles=level===1?[{crate,shadow:crateShadow,x:px,z:pz,dx:1,dz:0,done:false}]:[{crate,shadow:crateShadow,x:-1.65,z:-1.7,dx:0,dz:-1,done:false},{crate:secondCrate,shadow:secondShadow,x:1.75,z:-1.7,dx:0,dz:-1,done:false}];
 gateIcon.material.color.copy(gold.color);plateMeshes.forEach((m,i)=>m.position.y=initialPlate[i]);plateIcon.position.y=.22;plateIcon.material.color.set('#ae8024');secondPlates.forEach(p=>{p.group.position.y=0;p.top.material.color.copy(gold.color);p.icon.material.color.set('#ae8024');});sparkles.forEach(s=>s.visible=false);destination.material.opacity=0;markerTime=-10;
 puzzles.forEach(p=>p.shadow.position.set(p.crate.position.x,.066,p.crate.position.z));heroShadow.position.set(hero.position.x,surfaceY(hero.position.x,hero.position.z)+.066,hero.position.z);buildRoom();renderer.shadowMap.needsUpdate=true;}
function pickFloor(){
 const localRay=renderer.xr.isPresenting?immersive.toLocalRay(raycaster.ray):raycaster.ray;
 const candidates=[];for(const y of roomDefs[level].storeys?[0,upperHeight]:[0]){const p=new THREE.Vector3();if(localRay.intersectPlane(new THREE.Plane(new THREE.Vector3(0,1,0),-y-.065),p)){if(!roomDefs[level].storeys||(y===0?p.z>=.95:p.z<=-.95))candidates.push(p);}}
 if(roomDefs[level].storeys)for(const hit of raycaster.intersectObjects(challengeRoot.children.filter(o=>o.userData.walkSurface)))candidates.push(renderer.xr.isPresenting?immersive.toLocalPoint(hit.point):hit.point);
 candidates.sort((a,b)=>a.distanceToSquared(localRay.origin)-b.distanceToSquared(localRay.origin));return candidates[0]||null;
}
function pick(clientX,clientY){if(renderer.xr.isPresenting)return;const rect=canvas.getBoundingClientRect();pointer.set((clientX-rect.left)/rect.width*2-1,1-(clientY-rect.top)/rect.height*2);raycaster.setFromCamera(pointer,camera);dispatchGamePick();}
function dispatchGamePick(){tone(440,.02,.0001);if(mode==='finishing')return;if(mode==='complete'){loadLevel(1);return;}if(mode==='pushing')return;
 if(heldBrick.visible&&raycaster.intersectObject(hero,true).length){dropBrick();return;}
 if(pickRoom())return;
 for(const puzzle of puzzles)if(raycaster.intersectObject(puzzle.crate,true).length){startPush(puzzle);return;}
 const p=pickFloor();if(!p)return;
 for(const puzzle of puzzles)if(Math.abs(p.x-puzzle.x)<.62&&Math.abs(p.z-puzzle.z)<.62&&!puzzle.done){startPush(puzzle);return;}
 const gateHits=raycaster.intersectObjects([gate,gateIcon,...world.children.filter(o=>o.userData.exitTunnel)],true);
 if(gateHits.length||(Math.abs(p.x-archX)<.82&&p.z< -2.8)){startExit();return;}
 if(walkTo(p.x,p.z)){destination.position.set(p.x,surfaceY(p.x,p.z)+.085,p.z);markerTime=elapsed;}
}
// Single-finger tap selects a destination; dragging preserves the scene-view control.
const points=new Map();let lastDistance=0,gesture=false;
canvas.addEventListener('pointerdown',e=>{canvas.setPointerCapture(e.pointerId);points.set(e.pointerId,{x:e.clientX,y:e.clientY,sx:e.clientX,sy:e.clientY,moved:false});if(points.size>1){gesture=true;const[a,b]=[...points.values()];lastDistance=Math.hypot(a.x-b.x,a.y-b.y);}});
canvas.addEventListener('pointermove',e=>{const old=points.get(e.pointerId);if(!old)return;const dx=e.clientX-old.x,dy=e.clientY-old.y;old.x=e.clientX;old.y=e.clientY;if(Math.hypot(old.x-old.sx,old.y-old.sy)>9)old.moved=true;if(points.size===1&&old.moved){azimuth-=dx*.004;elevation=Math.max(.3,Math.min(1.25,elevation+dy*.003));fit();}else if(points.size>1){const[a,b]=[...points.values()],d=Math.hypot(a.x-b.x,a.y-b.y);zoom=Math.max(.65,Math.min(2,zoom*d/(lastDistance||d)));lastDistance=d;fit();}});
canvas.addEventListener('pointerup',e=>{const p=points.get(e.pointerId);if(p&&!p.moved&&!gesture)pick(e.clientX,e.clientY);points.delete(e.pointerId);if(!points.size)gesture=false;});
for(const type of ['pointercancel','lostpointercapture'])canvas.addEventListener(type,e=>{points.delete(e.pointerId);if(!points.size)gesture=false;});
canvas.addEventListener('wheel',e=>{e.preventDefault();zoom=Math.max(.65,Math.min(2,zoom*Math.exp(-e.deltaY*.001)));fit();},{passive:false});
canvas.addEventListener('contextmenu',e=>e.preventDefault());addEventListener('resize',fit);
addEventListener('keydown',e=>{if(e.key==='Escape'){resetLevel();return;}const dirs={ArrowUp:[0,-1],ArrowDown:[0,1],ArrowLeft:[-1,0],ArrowRight:[1,0]};if(!dirs[e.key]||mode==='pushing'||mode==='finishing')return;e.preventDefault();const[dX,dZ]=dirs[e.key];const x=hero.position.x+dX*.5,z=hero.position.z+dZ*.5;const hit=puzzles.find(p=>!p.done&&Math.abs(x-p.crate.position.x)<.86&&Math.abs(z-p.crate.position.z)<.86);if(hit){startPush(hit);return;}if(solved&&Math.abs(x-archX)<.65&&z< -2.8){startExit();return;}walkTo(x,z);});
function turnToward(dx,dz,dt){const wanted=Math.atan2(dx,dz);const delta=Math.atan2(Math.sin(wanted-hero.rotation.y),Math.cos(wanted-hero.rotation.y));hero.rotation.y+=delta*Math.min(1,dt*14);}
function update(dt){elapsed+=dt;let walking=false;updateRoom(dt);
 if(mode==='walking'&&route.length){let distanceLeft=dt*2.1;while(route.length&&distanceLeft>0){const p=route[0],dx=p.x-hero.position.x,dz=p.z-hero.position.z,d=Math.hypot(dx,dz);if(d>.0001)turnToward(dx,dz,dt);walking=true;if(d<=distanceLeft){hero.position.x=p.x;hero.position.z=p.z;distanceLeft-=d;route.shift();}else{hero.position.x+=dx/d*distanceLeft;hero.position.z+=dz/d*distanceLeft;distanceLeft=0;}}if(!route.length){const cb=afterRoute;afterRoute=null;mode='idle';if(cb)cb();}}
 if(mode==='pushing'){const p=activePuzzle,c=p.crate,t=Math.min(1,(elapsed-pushStart.time)/1.5),ease=t*t*(3-2*t);c.position.x=pushStart.x+(p.x-pushStart.x)*ease;c.position.z=pushStart.z+(p.z-pushStart.z)*ease;hero.position.x=c.position.x-p.dx*.95;hero.position.z=c.position.z-p.dz*.95;hero.rotation.y=Math.atan2(p.dx,p.dz);walking=true;if(t===1){c.position.set(p.x,.61,p.z);p.done=true;solved=puzzles.every(p=>p.done);refreshRoom();mode='idle';tone(solved?659:523,.25);}}
 if(level===2)secondPlates.forEach((p,i)=>{const down=puzzles[i].done;p.group.position.y=THREE.MathUtils.damp(p.group.position.y,down?-.037:0,8,dt);p.top.material.color.copy(down?successColor:gold.color);});
 gateOpen=THREE.MathUtils.damp(gateOpen,solved?1:0,5,dt);gate.position.y=exitY()-1.6*gateOpen;gateIcon.material.color.copy(gold.color).lerp(successColor,gateOpen);plateIcon.material.color.copy(goldDark.color).lerp(successColor,gateOpen);plateMeshes.forEach((m,i)=>m.position.y=initialPlate[i]-.037*gateOpen);plateIcon.position.y=.22-.037*gateOpen;
 const gait=walking?Math.sin(elapsed*17):0;hero.position.y=surfaceY(hero.position.x,hero.position.z)+.07+(walking?Math.abs(gait)*.025:Math.sin(elapsed*2)*.008);feet.forEach((f,i)=>{f.position.y=.105+Math.max(0,gait*(i?1:-1))*.065;f.position.z=.045+gait*(i?1:-1)*.09;});
 const pushing=mode==='pushing'||heldBrick.visible;for(let i=0;i<2;i++){const side=i?1:-1,start=new THREE.Vector3(side*.235,.67,.03),end=new THREE.Vector3(side*.25,pushing?.6:.43,pushing?.435:.11+gait*side*.07);hands[i].position.copy(end);const arm=armMeshes[i],delta=end.clone().sub(start);arm.position.copy(start).add(end).multiplyScalar(.5);arm.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),delta.clone().normalize());arm.scale.y=(delta.length()+.158)/(Math.hypot(.005,-.09,.35)+.158);}
 heroShadow.position.set(hero.position.x,surfaceY(hero.position.x,hero.position.z)+.066,hero.position.z);puzzles.forEach(p=>p.shadow.position.set(p.crate.position.x,.066,p.crate.position.z));
 if(mode==='finishing'||mode==='complete'){const t=elapsed-finishedAt;sparkles.forEach((s,i)=>{const a=i/16*Math.PI*2;s.position.set(archX+Math.cos(a)*(.18+t*.32),exitY()+1.6+Math.sin(Math.min(1,t/1.6)*Math.PI)*.65,frontZ+.2+Math.sin(a)*(.18+t*.32));s.scale.setScalar(Math.max(0,1-t/2));s.rotation.y+=dt*2;});if(t>2){sparkles.forEach(s=>s.visible=false);if(level<21){loadLevel(level+1);}else mode='complete';}}
 destination.material.opacity=Math.max(0,.48-(elapsed-markerTime)*.65);destination.scale.setScalar(1+Math.max(0,elapsed-markerTime)*.4);
 renderer.shadowMap.needsUpdate=true;
}
loadLevel(restoredLevel());fit();renderer.render(scene,camera);document.getElementById('loading')?.remove();renderer.shadowMap.autoUpdate=false;
window.__sceneCheck={levels:21,meshes:world.children.length,geometryCount:roundedCache.size,ready:true,externalAssets:0};
const immersive=createXR({THREE,renderer,scene,world,ground,lights:[hemisphere,key,fill],onRay:ray=>{raycaster.ray.copy(ray);dispatchGamePick();},onLevel:loadLevel,getLevel:()=>level,totalLevels:21});
let lastTime=0;function frame(ms,xrFrame){if(document.hidden&&!immersive.active){lastTime=ms;return;}const dt=lastTime?Math.min((ms-lastTime)/1000,.04):1/60;lastTime=ms;immersive.update(xrFrame,dt);if(immersive.playing)update(dt);renderer.render(scene,immersive.active?immersive.camera:camera);}renderer.setAnimationLoop(frame);
