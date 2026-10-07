// Local input helpers shared by touch, keyboard and Quest controllers.
export function readStick(x=0,y=0,deadZone=.18){
 if(!Number.isFinite(x)||!Number.isFinite(y))return {x:0,y:0};
 const length=Math.hypot(x,y);
 if(length<=deadZone)return {x:0,y:0};
 const strength=(Math.min(length,1)-deadZone)/(1-deadZone);
 return {x:x/length*strength,y:y/length*strength};
}

// Stick up is away from the viewer, even after rotating the board.
export function viewMotion(x,y,viewYaw,boardYaw=0){
 const angle=viewYaw-boardYaw,c=Math.cos(angle),s=Math.sin(angle);
 return {x:x*c+y*s,z:-x*s+y*c};
}

export function createTouchStick(element,knob,onStart=()=>{}){
 let pointerId=null;
 const value={x:0,y:0};
 function position(event){
  const rect=element.getBoundingClientRect(),radius=Math.max(1,Math.min(rect.width,rect.height)/2-22);
  let x=event.clientX-rect.left-rect.width/2,y=event.clientY-rect.top-rect.height/2;
  const length=Math.hypot(x,y);if(length>radius){x*=radius/length;y*=radius/length;}
  Object.assign(value,readStick(x/radius,y/radius,.12));
  knob.style.transform=`translate(${x}px,${y}px)`;
 }
 function reset(){
  const id=pointerId;pointerId=null;value.x=value.y=0;
  knob.style.transform='translate(0px,0px)';element.removeAttribute('data-active');
  if(id!==null&&element.hasPointerCapture?.(id))element.releasePointerCapture(id);
 }
 element.addEventListener('pointerdown',event=>{
  event.preventDefault();event.stopPropagation();
  if(pointerId!==null||(event.pointerType==='mouse'&&event.button!==0))return;
  pointerId=event.pointerId;element.setPointerCapture(pointerId);element.setAttribute('data-active','');position(event);onStart();
 });
 element.addEventListener('pointermove',event=>{
  if(event.pointerId!==pointerId)return;
  event.preventDefault();event.stopPropagation();position(event);
 });
 for(const type of ['pointerup','pointercancel','lostpointercapture'])element.addEventListener(type,event=>{
  if(event.pointerId!==pointerId)return;event.preventDefault();event.stopPropagation();reset();
 });
 element.addEventListener('contextmenu',event=>event.preventDefault());
 return {value,reset};
}
