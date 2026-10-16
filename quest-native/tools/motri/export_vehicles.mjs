// Exports Motri's own vehicles for the desert camp level (level 4) as GLB, with baked
// vertex colours. Run it next to a Motri checkout's sources (as src/), like export_models.mjs:
//   node --import ./register.mjs export_vehicles.mjs     (writes out/shas.glb, out/datsun.glb)
//   shas    buildCamelCampPickup: the parked 2026 Toyota LC70 single cab beside the camel camp
//   datsun  buildPickupVehicleBody(..., 'datsun'): the Datsun body skin; it is made for the
//           playable car's chassis, so it gets that chassis' four wheels (offset x 0.90, z 0.75,
//           radius 0.4) and a dark underbody here, and is turned to face +Z
// The water tanker comes out of camel_camp.glb (export_models.mjs) in import_motri.py.
import * as THREE from 'three/webgpu'
import fs from 'node:fs'
import { buildCamelCampPickup } from './src/Game/World/CamelCampPickup.js'
import { buildPickupVehicleBody } from './src/Game/World/PickupVehicleBody.js'

function writeGLB(root, path) {
  root.updateMatrixWorld(true)
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert()
  const nodes = [], meshes = [], accessors = [], views = [], chunks = []
  let offset = 0
  const push = (arr, target) => { const b = Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength); const pad = (4 - b.length % 4) % 4
    views.push({ buffer: 0, byteOffset: offset, byteLength: b.length, ...(target ? { target } : {}) }); chunks.push(b, Buffer.alloc(pad)); offset += b.length + pad; return views.length - 1 }
  root.traverse(m => {
    if (!m.isMesh) return
    const g0 = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry
    const n = m.isInstancedMesh ? m.count : 1
    for (let i = 0; i < n; i++) {
      const mat = new THREE.Matrix4()
      if (m.isInstancedMesh) m.getMatrixAt(i, mat)
      mat.premultiply(m.matrixWorld).premultiply(inv)
      const g = g0.clone(); g.applyMatrix4(mat); if (!g.attributes.normal) g.computeVertexNormals()
      const pos = new Float32Array(g.attributes.position.array), nor = new Float32Array(g.attributes.normal.array)
      const col = g.attributes.color ? new Float32Array(g.attributes.color.array) : null
      const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity]
      for (let k = 0; k < pos.length; k += 3) for (let a = 0; a < 3; a++) { mn[a] = Math.min(mn[a], pos[k + a]); mx[a] = Math.max(mx[a], pos[k + a]) }
      const cnt = pos.length / 3
      accessors.push({ bufferView: push(pos, 34962), componentType: 5126, count: cnt, type: 'VEC3', min: mn, max: mx })
      const pa = accessors.length - 1
      accessors.push({ bufferView: push(nor, 34962), componentType: 5126, count: cnt, type: 'VEC3' })
      const attrs = { POSITION: pa, NORMAL: pa + 1 }
      if (col) { accessors.push({ bufferView: push(col, 34962), componentType: 5126, count: cnt, type: 'VEC3' }); attrs.COLOR_0 = accessors.length - 1 }
      meshes.push({ primitives: [{ attributes: attrs, material: 0 }] })
      nodes.push({ name: (m.name || 'mesh') + (m.isInstancedMesh ? '_' + i : ''), mesh: meshes.length - 1 })
    }
  })
  const json = { asset: { version: '2.0', generator: 'motri-export' }, scene: 0, scenes: [{ nodes: nodes.map((_, i) => i) }], nodes, meshes, accessors,
    bufferViews: views, buffers: [{ byteLength: offset }], materials: [{ name: 'motri_vc', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 0.9 } }] }
  let js = Buffer.from(JSON.stringify(json)); js = Buffer.concat([js, Buffer.alloc((4 - js.length % 4) % 4, 0x20)])
  const bin = Buffer.concat(chunks)
  const head = Buffer.alloc(12); head.writeUInt32LE(0x46546C67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + js.length + 8 + bin.length, 8)
  const h1 = Buffer.alloc(8); h1.writeUInt32LE(js.length, 0); h1.writeUInt32LE(0x4E4F534A, 4)
  const h2 = Buffer.alloc(8); h2.writeUInt32LE(bin.length, 0); h2.writeUInt32LE(0x004E4942, 4)
  fs.writeFileSync(path, Buffer.concat([head, h1, js, h2, bin])); console.log(path, nodes.length, 'nodes', nodes.map(n => n.name).slice(0, 30).join(','))
}

const mat = new THREE.MeshBasicMaterial({ vertexColors: true })
const colour = (geometry, hex) => {
  const c = new THREE.Color(hex), values = new Float32Array(geometry.attributes.position.count * 3)
  for (let i = 0; i < values.length; i += 3) values.set([c.r, c.g, c.b], i)
  geometry.setAttribute('color', new THREE.BufferAttribute(values, 3))
}

const shas = new THREE.Group(); shas.add(buildCamelCampPickup(mat).mesh)
writeGLB(shas, 'out/shas.glb')

const body = buildPickupVehicleBody(mat, mat, 'datsun')
for (const m of body.children) if (m.name.endsWith('BodyPaint')) colour(m.geometry, body.userData.paintedColor)
const datsun = new THREE.Group(), chassis = new THREE.Group()
chassis.add(body)
const dark = new THREE.BoxGeometry(2.7, 0.22, 1.1); colour(dark, '#2b302d')
const under = new THREE.Mesh(dark, mat); under.position.set(0.05, -0.45, 0); under.name = 'Datsun_Underbody'; chassis.add(under)
const tyre = new THREE.CylinderGeometry(0.4, 0.4, 0.26, 16); colour(tyre, '#303631')
const rim = new THREE.CylinderGeometry(0.23, 0.23, 0.272, 12); colour(rim, '#b2b8aa')
for (const x of [-0.9, 0.9]) for (const z of [-0.75, 0.75]) {
  for (const [g, n] of [[tyre, 'Tyre'], [rim, 'Rim']]) {
    const w = new THREE.Mesh(g, mat); w.rotation.x = Math.PI / 2; w.position.set(x, -0.6, z); w.name = 'Datsun_' + n; chassis.add(w)
  }
}
chassis.rotation.y = -Math.PI / 2   // chassis +X forward -> +Z
chassis.position.y = 1.0            // wheels (centre y -0.6, radius 0.4) on the ground
datsun.add(chassis)
writeGLB(datsun, 'out/datsun.glb')
