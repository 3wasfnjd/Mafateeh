import fs from 'node:fs';
import * as THREE from '../vendor/three.module.js';
import {createXR} from '../src/xr.js';
import {createTouchStick,readStick,viewMotion} from '../src/controls.js';
import {fakeDocument,rendererClass} from './support.mjs';
const document=fakeDocument();const window={localStorage:{setItem(){},getItem(){return null}},dispatchEvent(){},isSecureContext:true};
Object.defineProperty(globalThis,'navigator',{value:{},configurable:true});Object.assign(globalThis,{document,window});
const StubRenderer=rendererClass(THREE);
let code=fs.readFileSync(new URL('../src/game.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace('const renderer=new THREE.WebGLRenderer(','const renderer=new StubRenderer(');
const cases="\nfunction assert(v,m){if(!v)throw Error(m);}\nfunction sim(t){for(let i=0;i<t*60;i++){update(1/60);if(mode==='walking'||mode==='steering')assert(!blocked(hero.position.x,hero.position.z),'Collision at '+hero.position.x+','+hero.position.z);}}\nfunction object(type){return interactionObjects.find(o=>o.type===type);}\nfunction use(type){const o=object(type);assert(o,'Missing '+type);assert(approachObject(o),'Cannot reach '+type+' from '+hero.position.x+','+hero.position.z);sim(14);}\nloadLevel(21);assert(levelButtons.length===21,'Missing test-level button');assert(!findPath(hero.position,{x:-2.05,z:-2.6}),'Pool can be bypassed');\nuse('brick');assert(heldBrick.visible&&challenge.brickMode==='carried','Brick not lifted');\ndropBrick();assert(!heldBrick.visible&&challenge.brickMode==='floor','Brick cannot be dropped');use('brick');\nuse('brickSocket');assert(challenge.brickMode==='socket','Brick not placed on socket');assert(roomCondition('brickSocket'),'Stepping stones did not open');use('key');assert(challenge.keys===1,'Pool key not collected');\nuse('lock');assert(challenge.unlocked===1,'Internal entrance did not unlock');use('gem');assert(solved,'Room still unsolved');startExit();sim(15);assert(mode==='complete','Room did not complete');\nloadLevel(21);scene.updateMatrixWorld(true);const brick=object('brick');const p=new THREE.Vector3(brick.x,.3,brick.z).project(camera);pick((p.x+1)*393/2,136+(1-p.y)*716/2);sim(14);assert(heldBrick.visible,'Touch did not pick up brick');\nscene.updateMatrixWorld(true);const h=hero.position.clone();h.y+=.8;const hp=h.project(camera);pick((hp.x+1)*393/2,136+(1-hp.y)*716/2);assert(!heldBrick.visible,'Touching carrier did not put down brick');\nfor(let n=1;n<=21;n++){loadLevel(n);assert(!blocked(hero.position.x,hero.position.z),'Invalid spawn '+n);assert(!heldBrick.visible,'Carried brick leaked to '+n);challengeRoot.traverse(o=>{if(o.isMesh)for(const v of o.geometry.attributes.position.array)assert(Number.isFinite(v),'Invalid mesh '+n);});}\nconsole.log('Room 21: carry, drop, socket, pool path, locked entrance, completion and touch verified. All 21 spawns and geometries valid.');\n";
const movementCases=`
function release(){xrMotion.x=xrMotion.z=0;touchStick.reset();update(1/60);}
function drive(x,z,seconds){xrMotion.x=x;xrMotion.z=z;sim(seconds);}
renderer.xr.isPresenting=true;
loadLevel(3);release();const spawn=hero.position.clone();
drive(1,0,2);assert(hero.position.x>spawn.x+.5&&hero.position.x<-.42,'Stick must stop at interior wall');
release();const stop=hero.position.clone();sim(.5);assert(Math.hypot(hero.position.x-stop.x,hero.position.z-stop.z)<1e-8,'Release must stop immediately');
drive(-1,0,3);assert(hero.position.x>=-3.65,'Stick must respect outer boundary');
loadLevel(11);release();const start=hero.position.clone();drive(1,-1,.1);assert(Math.hypot(hero.position.x-start.x,hero.position.z-start.z)<=.211,'Diagonal speed must be capped');
loadLevel(4);release();drive(0,-1,3);assert(hero.position.z>=.89,'Stick cannot cross closed water');
loadLevel(14);release();hero.position.set(-2.9,.07,1.5);drive(0,-1,1.4);assert(hero.position.z<-.95&&hero.position.y>2.1,'Stick must walk upstairs');
release();drive(0,1,1.4);assert(hero.position.z>.95&&hero.position.y<.15,'Stick must walk downstairs');
loadLevel(13);release();hero.position.set(-2.9,.07,1.5);drive(0,-1,2);assert(hero.position.z>=1.24,'Closed stairs must block movement');
loadLevel(1);release();drive(1,0,2);assert(puzzles[0].done,'Stick should push crate from the correct side');
loadLevel(3);release();assert(walkTo(-2.5,1.3),'Tap route setup');sim(.1);drive(-1,0,.2);release();const cancelled=hero.position.clone();sim(.8);assert(Math.hypot(hero.position.x-cancelled.x,hero.position.z-cancelled.z)<1e-8,'Stick overrides tap route without resuming it on release');
loadLevel(11);release();drive(1,0,.1);loadLevel(3);const changed=hero.position.clone();drive(1,0,.2);assert(hero.position.x===changed.x,'Level change waits for stick release');release();drive(1,0,.1);assert(hero.position.x>changed.x,'Movement resumes after re-centering stick');
loadLevel(21);release();use('brick');release();drive(0,-1,.3);assert(heldBrick.visible,'Carried brick must stay attached while steering');
loadLevel(3);release();const keyObject=object('key');hero.position.set(keyObject.x-.5,.07,keyObject.z);drive(1,0,.12);assert(challenge.keys===1,'Walking to key should collect it');
loadLevel(3);release();renderer.xr.isPresenting=false;touchStick.value.x=1;const touchStart=hero.position.clone();update(.04);assert(hero.position.distanceTo(touchStart)>.02,'Touch stick reaches gameplay');resetMovement();const paused=hero.position.clone();sim(.2);assert(Math.hypot(hero.position.x-paused.x,hero.position.z-paused.z)<1e-8,'Input reset stops touch motion');
console.log('Movement: release, walls, water, stairs, crates, tap override, stage reset, brick carrying and key collection passed.');
`;
new Function('THREE','createXR','document','window','devicePixelRatio','innerWidth','innerHeight','addEventListener','StubRenderer','createTouchStick','readStick','viewMotion',code+cases+movementCases)(THREE,createXR,document,window,1,393,852,()=>{},StubRenderer,createTouchStick,readStick,viewMotion);
