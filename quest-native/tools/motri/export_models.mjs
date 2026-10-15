import * as THREE from 'three/webgpu'
import fs from 'node:fs'
import { CamelCampModel } from './src/Game/World/CamelCampModel.js'
import { buildSheepPenModel } from './src/Game/World/SheepPenModel.js'
import { RestHousePoultryModel } from './src/Game/World/RestHousePoultryModel.js'
import { RestHousePoultryMotion } from './src/Game/World/RestHousePoultryMotion.js'

// Writes every mesh (and each instance of an instanced mesh) as its own node with
// baked positions/normals/colours relative to the group root.
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
const camp = new CamelCampModel(mat); camp.pose?.(0); writeGLB(camp.root, 'out/camel_camp.glb')
const pen = buildSheepPenModel(mat); writeGLB(pen.root || pen, 'out/sheep_pen.glb')
const motion = new RestHousePoultryMotion([], 1, () => 0.37)
const birds = new RestHousePoultryModel(mat, motion); writeGLB(birds.root, 'out/poultry.glb')
console.log('birds', JSON.stringify(motion.birds.map(b => [b.kind, +b.x.toFixed(2), +b.z.toFixed(2), b.size])))
