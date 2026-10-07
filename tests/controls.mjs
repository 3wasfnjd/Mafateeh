import assert from 'node:assert/strict';
import {readStick,viewMotion,createTouchStick} from '../src/controls.js';

assert.deepEqual(readStick(.08,-.09),{x:0,y:0});
assert.deepEqual(readStick(NaN,1),{x:0,y:0});
assert.equal(Math.hypot(...Object.values(readStick(1,1))),1);
const north=viewMotion(0,-1,0,Math.PI/2);
assert(Math.abs(north.x-1)<1e-9&&Math.abs(north.z)<1e-9,'Board rotation must not reverse viewer-relative movement');

const listeners={},captured=new Set(),knob={style:{}};
const element={
 addEventListener(type,fn){listeners[type]=fn},setAttribute(){},removeAttribute(){},
 getBoundingClientRect:()=>({left:20,top:300,width:108,height:108}),
 setPointerCapture:id=>captured.add(id),hasPointerCapture:id=>captured.has(id),releasePointerCapture:id=>captured.delete(id)
};
let starts=0;const stick=createTouchStick(element,knob,()=>starts++);
const event=(id,x,y)=>({pointerId:id,clientX:x,clientY:y,pointerType:'touch',preventDefault(){},stopPropagation(){}});
listeners.pointerdown(event(1,74,354));assert.equal(starts,1);assert.deepEqual(stick.value,{x:0,y:0});
listeners.pointermove(event(1,250,354));assert.equal(stick.value.x,1);assert.equal(stick.value.y,0);assert.equal(knob.style.transform,'translate(32px,0px)');
listeners.pointerdown(event(2,74,320));listeners.pointermove(event(2,74,250));assert.equal(stick.value.x,1,'Second finger cannot steal movement');
listeners.pointerup(event(2,74,320));assert.equal(stick.value.x,1,'Releasing another finger cannot stop movement');
listeners.pointerup(event(1,250,354));assert.deepEqual(stick.value,{x:0,y:0});assert.equal(captured.size,0);
for(const type of ['pointercancel','lostpointercapture']){
 listeners.pointerdown(event(3,74,320));assert(stick.value.y<0);listeners[type](event(3,74,320));assert.deepEqual(stick.value,{x:0,y:0});
}
console.log('Controls: dead zone, diagonal speed, view-relative direction, multi-touch ownership and release/cancel passed.');
