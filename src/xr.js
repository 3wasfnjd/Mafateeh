// WebXR adapter. Gameplay and navigation stay in the board's local coordinate system.
import {readStick,viewMotion} from './controls.js';
export function createXR({THREE,renderer,scene,world,ground,lights,onRay,onMove=()=>{},onLevel,getLevel,totalLevels}){
 const root=new THREE.Group();scene.add(root);root.add(world,...lights);for(const l of lights)if(l.target)root.add(l.target);
 const camera=new THREE.PerspectiveCamera(70,1,.01,50);scene.add(camera);
 const savedBackground=scene.background,baseGroundY=ground.position.y;
 const reticle=new THREE.Mesh(new THREE.RingGeometry(.07,.095,40).rotateX(-Math.PI/2),new THREE.MeshBasicMaterial({color:0xffd875,side:THREE.DoubleSide}));reticle.matrixAutoUpdate=false;reticle.visible=false;scene.add(reticle);
 const dock=new THREE.Group();root.add(dock);dock.visible=false;
 const dockItems=[],controllers=[],inverse=new THREE.Matrix4(),rotation=new THREE.Matrix4(),raycaster=new THREE.Raycaster();
 const anchor=new THREE.Vector3(),normal=new THREE.Vector3(),forward=new THREE.Vector3();
 let session=null,kind=null,pending=false,placed=false,placing=false,hitSource=null,lastPose=null,scale=.14,dockLevel=-1,noticeTimer;
 const bar=document.getElementById('xr-modes'),status=document.getElementById('xr-status');
 const buttons={vr:document.getElementById('enter-vr'),ar:document.getElementById('enter-ar')};
 function notice(text){clearTimeout(noticeTimer);status.textContent=text;status.hidden=!text;if(text)noticeTimer=setTimeout(()=>{status.hidden=true},6500);}
 function setBusy(b){pending=b;for(const button of Object.values(buttons))button.disabled=b;}
 function tuneShadows(){for(const l of lights)if(l.shadow){const s=session?scale:1,c=l.shadow.camera;Object.assign(c,{left:-8*s,right:8*s,top:8*s,bottom:-8*s,near:session?.01:.5,far:30*s});c.updateProjectionMatrix();l.shadow.normalBias=.025*s;l.shadow.needsUpdate=true;}renderer.shadowMap.needsUpdate=true;}
 function applyScale(s){scale=THREE.MathUtils.clamp(s,.06,.26);root.scale.setScalar(scale);root.position.y=anchor.y+.425*scale;root.updateMatrixWorld(true);tuneShadows();}
 function faceViewer(pose){const p=pose.transform.position;root.rotation.set(0,Math.atan2(p.x-root.position.x,p.z-root.position.z),0);}
 function placeVR(pose){const p=pose.transform.position,q=pose.transform.orientation;forward.set(0,0,-1).applyQuaternion(new THREE.Quaternion(q.x,q.y,q.z,q.w));forward.y=0;if(forward.lengthSq()<.01)forward.set(0,0,-1);forward.normalize();anchor.set(p.x+forward.x*1.1,Math.max(.55,p.y-.8),p.z+forward.z*1.1);root.position.copy(anchor);faceViewer(pose);applyScale(scale);placed=true;placing=false;root.visible=true;dock.visible=true;}
 function placeAR(){if(!reticle.visible||!lastPose)return;anchor.setFromMatrixPosition(reticle.matrix);root.position.copy(anchor);faceViewer(lastPose);applyScale(scale);placed=true;placing=false;root.visible=true;dock.visible=true;reticle.visible=false;}
 function reposition(){onMove(0,0);if(!session)return;if(kind==='ar'){placing=true;placed=false;root.visible=false;dock.visible=false;}else if(lastPose)placeVR(lastPose);}
 function texture(label){const c=document.createElement('canvas');c.width=128;c.height=96;const g=c.getContext('2d');g.fillStyle='#e6dfc8';g.fillRect(0,0,128,96);g.fillStyle='#29484c';g.font='600 48px sans-serif';g.textAlign='center';g.textBaseline='middle';g.fillText(label,64,49);const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;return t;}
 function dockButton(label,x,z,action,levelNumber){const m=new THREE.Mesh(new THREE.PlaneGeometry(.53,.4),new THREE.MeshBasicMaterial({map:texture(label),side:THREE.DoubleSide}));m.rotation.x=-Math.PI/2;m.position.set(x,.11,z);m.userData={action,levelNumber};dock.add(m);dockItems.push(m);}
 for(let i=0;i<totalLevels;i++)dockButton(String(i+1),(i%7-3)*.63,4.1+Math.floor(i/7)*.51,()=>onLevel(i+1),i+1);
 const controlsZ=4.1+Math.ceil(totalLevels/7)*.51+.16;
 dockButton('−',-1.05,controlsZ,()=>applyScale(scale*.85));dockButton('+',-.35,controlsZ,()=>applyScale(scale/ .85));dockButton('↻',.35,controlsZ,reposition);dockButton('×',1.05,controlsZ,()=>session?.end());
 function controllerRay(c){rotation.identity().extractRotation(c.matrixWorld);const r=new THREE.Ray();r.origin.setFromMatrixPosition(c.matrixWorld);r.direction.set(0,0,-1).applyMatrix4(rotation).normalize();return r;}
 function select(c){if(!session||pending)return;if(kind==='ar'&&placing){placeAR();return;}if(!placed)return;root.updateMatrixWorld(true);raycaster.ray.copy(controllerRay(c));const hit=raycaster.intersectObjects(dockItems)[0];if(hit)hit.object.userData.action();else onRay(raycaster.ray.clone());const actuator=c.userData.source?.gamepad?.hapticActuators?.[0];if(actuator)Promise.resolve(actuator.pulse(.2,25)).catch(()=>{});}
 renderer.xr.enabled=true;renderer.xr.setReferenceSpaceType('local-floor');
 for(let i=0;i<2;i++){const c=renderer.xr.getController(i);const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(),new THREE.Vector3(0,0,-1)]),new THREE.LineBasicMaterial({color:0xffdd85,transparent:true,opacity:.7}));line.scale.z=2;c.add(line);c.userData.line=line;c.addEventListener('connected',e=>{c.userData.source=e.data});c.addEventListener('disconnected',()=>{c.userData.source=null;onMove(0,0)});c.addEventListener('select',()=>select(c));c.addEventListener('squeezestart',reposition);scene.add(c);controllers.push(c);}
 function restore(){onMove(0,0);try{hitSource?.cancel()}catch{}hitSource=null;session=null;kind=null;placed=false;placing=false;lastPose=null;reticle.visible=false;dock.visible=false;root.visible=true;root.position.set(0,0,0);root.rotation.set(0,0,0);root.scale.setScalar(1);root.updateMatrixWorld(true);ground.visible=true;ground.position.y=baseGroundY;scene.background=savedBackground;renderer.setClearColor(savedBackground,1);document.body.classList.remove('xr-active');setBusy(false);tuneShadows();queueMicrotask(()=>window.dispatchEvent(new Event('resize')));}
 async function start(type){if(pending||session)return;onMove(0,0);setBusy(true);notice('');let requested;
  try{renderer.xr.setFramebufferScaleFactor(.8);requested=await navigator.xr.requestSession(type==='ar'?'immersive-ar':'immersive-vr',{requiredFeatures:type==='ar'?['local-floor','hit-test']:['local-floor']});session=requested;kind=type;scale=.14;placed=false;placing=type==='ar';root.visible=false;ground.visible=type!=='ar';ground.position.y=0;scene.background=type==='ar'?null:savedBackground;renderer.setClearColor(savedBackground,type==='ar'?0:1);requested.addEventListener('end',restore,{once:true});requested.addEventListener('visibilitychange',()=>onMove(0,0));document.body.classList.add('xr-active');await renderer.xr.setSession(requested);renderer.xr.setFoveation(1);
   if(type==='ar'){const viewer=await requested.requestReferenceSpace('viewer');const source=await requested.requestHitTestSource({space:viewer});if(session!==requested){source.cancel();return;}hitSource=source;}
   setBusy(false);
  }catch(error){if(requested)try{await requested.end()}catch{}if(session||!requested)restore();notice(error?.name==='NotAllowedError'?'لم يُسمح بالدخول إلى وضع النظارة.':type==='ar'?'تعذّر تشغيل AR مع تتبّع السطح في هذا المتصفح.':'تعذّر تشغيل VR في هذا المتصفح.');}
 }
 buttons.vr.addEventListener('click',()=>start('vr'));buttons.ar.addEventListener('click',()=>start('ar'));
 if(navigator.xr&&window.isSecureContext!==false){Promise.all(['immersive-vr','immersive-ar'].map(mode=>navigator.xr.isSessionSupported(mode).catch(()=>false))).then(([vr,ar])=>{buttons.vr.hidden=!vr;buttons.ar.hidden=!ar;bar.hidden=!vr&&!ar;});}
 function update(frame,dt){
  // Always clear the last frame: a disconnected controller cannot leave movement held.
  onMove(0,0);
  if(!session||!frame||(session.visibilityState&&session.visibilityState!=='visible'))return;
  const ref=renderer.xr.getReferenceSpace(),pose=frame.getViewerPose(ref);
  if(!pose){reticle.visible=false;return;}lastPose=pose;
  if(kind==='vr'&&!placed)placeVR(lastPose);
  if(kind==='ar'&&placing){reticle.visible=false;if(hitSource){const hit=frame.getHitTestResults(hitSource)[0];const p=hit?.getPose(ref);if(p){const m=new THREE.Matrix4().fromArray(p.transform.matrix);normal.set(0,1,0).transformDirection(m);if(normal.y>.85){reticle.matrix.copy(m);reticle.visible=true;}}}}
  if(placed){
   let move={x:0,y:0};
   for(const source of session.inputSources){
    const g=source.gamepad;if(!g||g.connected===false)continue;
    const offset=g.axes.length>=4?2:0,stick=readStick(g.axes[offset]||0,g.axes[offset+1]||0);
    if(source.handedness==='right')move=stick;
    else if(source.handedness==='left'){
     if(stick.x)root.rotation.y-=stick.x*dt;
     if(stick.y)applyScale(scale*Math.exp(-stick.y*dt*.75));
    }
   }
   root.updateMatrixWorld(true);
   const q=lastPose.transform.orientation;
   forward.set(0,0,-1).applyQuaternion(new THREE.Quaternion(q.x,q.y,q.z,q.w));
   // When looking straight down, use the headset's horizontal right direction.
   if(forward.x*forward.x+forward.z*forward.z<.0001){
    forward.set(1,0,0).applyQuaternion(new THREE.Quaternion(q.x,q.y,q.z,q.w));
    const rightX=forward.x;forward.x=forward.z;forward.z=-rightX;
   }
   const motion=viewMotion(move.x,move.y,Math.atan2(-forward.x,-forward.z),root.rotation.y);
   onMove(motion.x,motion.z);
  }
  if(dockLevel!==getLevel()){dockLevel=getLevel();for(const m of dockItems)m.material.color.set(m.userData.levelNumber===dockLevel?0xf0c65a:0xffffff);}
 }
 return {camera,start,reposition,update,get active(){return !!session},get playing(){return !session||placed},toLocalRay(ray){root.updateMatrixWorld(true);return ray.clone().applyMatrix4(inverse.copy(root.matrixWorld).invert());},toLocalPoint(point){root.updateMatrixWorld(true);return root.worldToLocal(point.clone());}};
}
