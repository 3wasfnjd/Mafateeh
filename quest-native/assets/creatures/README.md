# Creature slots — replacing the falcon, cat and sparrow models

The current `falcon.glb`, `cat.glb` and `sparrow.glb` are placeholders built by
`tools/blender/build_creatures.py`. To use a new model, **overwrite the file with the same
name** and reopen the project in Godot (or run `godot --headless --import`). No code changes needed.

| Slot | File | Size in game | Animation roles (any clip named like these) |
|---|---|---|---|
| Falcon «شاهين» | `falcon.glb` | 0.22 tall (perched) | `perch` (idle, sit, stand) · `fly` (flap, flying) · `land` (optional) |
| Cat | `cat.glb` | 0.27 tall (sitting) | `sit` (idle) · `walk` · `sleep` (lie, rest) |
| Sparrow | `sparrow.glb` | 0.14 tall | `peck` (eat, idle) · `fly` (flap) |

What the game does automatically (`scripts/art/creature_slot.gd`):

- **Scale:** measures the model and scales it to the size above, whatever units it was made in.
- **Ground:** puts the lowest point of the model on the ground or perch.
- **Clips:** matches clip names case-insensitively and ignores prefixes such as `Armature|`;
  `Falcon_Fly_Loop` also counts as `fly`. Missing clips are fine — the model just holds still.

What the model should have:

- **One GLB** (glTF binary) with its textures embedded, one skinned mesh or a few meshes.
- **Facing:** head toward **+Z in Godot** (that is **-Y in Blender**, the default glTF export).
  If it faces another way, change `"yaw"` for that slot in `SLOTS` in `creature_slot.gd`.
- **Budget (Quest):** about 3–8k triangles, one 1024² texture (2048² at most). Loops should be
  seamless.
