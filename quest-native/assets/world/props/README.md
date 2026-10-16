# Props from Motri

`camel_standing`, `camel_kneeling`, `camel_calf`, `tent`, `sheep`, `hen`, `rooster`, `crate`,
`lantern`, and for the desert camp (level 4) `shas`, `datsun`, `wayit`, `trough` and `sheep_pen`
come from the owner's Motri repository (github.com/3wasfnjd/Motri), whose base is
**Folio 2025 by Bruno Simon**, MIT licence:

> Copyright (c) 2025 Bruno Simon. Permission is hereby granted, free of charge, to any person
> obtaining a copy of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights to use, copy,
> modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to the following conditions:
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

How they were made:
1. `tools/motri/export_models.mjs` runs Motri's own model code (CamelCampModel, SheepPenModel,
   RestHousePoultryModel) in Node and writes the geometry with its vertex colours to GLB.
2. `tools/blender/import_motri.py` splits out single animals and the tent, recolours the crate
   and lantern to wood, and writes the files here.
3. `tools/motri/export_vehicles.mjs` writes Motri's parked 2026 Shas (CamelCampPickup); then
   `tools/blender/import_motri_camp.py` takes that, the Datsun feed pickup and the sheep pen
   (fence, shade, feeders, flock; without its sand pad) from the sheep pen export, and the
   water tanker and trough from the camel camp. Body-coloured faces of each vehicle are on a
   `paint_<name>` material so the game can repaint parked cars.

The floor textures `art_source/world/motri/slabs.png` and `stone-paving.png` are from the same
repository and licence; `tools/blender/build_scene1.py` uses them for the courtyard and paths.
This credit must also appear in the game's credits.
