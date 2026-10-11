# Third-party notices

Mafateeh (مفاتيح) is © Aboden Games — عبودين قيمز and released under the [MIT license](../LICENSE).
Everything below keeps its own license. Original game content (code, Blender sources, models,
animations, textures, sounds, level designs) is part of Mafateeh and covered by the MIT license.

## Web version (repository root)

| Component | License | Notice |
|---|---|---|
| three.js (`vendor/three.module.js`) | MIT | [THREE-LICENSE.txt](THREE-LICENSE.txt) |

## Native Meta Quest version (`quest-native/`)

| Component | Version | License | Notice |
|---|---|---|---|
| Godot Engine (runtime in the APK) | 4.6.3-stable | MIT | [GODOT-LICENSE.txt](GODOT-LICENSE.txt) |
| Libraries bundled inside Godot | 4.6.3-stable | various (MIT, BSD, Apache-2.0, zlib, …) | [GODOT-THIRDPARTY.txt](GODOT-THIRDPARTY.txt) |
| Godot OpenXR Vendors plugin | 5.1.0-stable | MIT | [`quest-native/addons/godotopenxrvendors/LICENSE`](../quest-native/addons/godotopenxrvendors/LICENSE) |
| Khronos OpenXR loader (shipped with the plugin) | per plugin | Apache-2.0 | [`…/meta/LICENSE-LOADER`](../quest-native/addons/godotopenxrvendors/meta/LICENSE-LOADER) |
| Meta OpenXR Mobile SDK headers/libraries used by the plugin | per plugin | Oculus SDK License | [`…/meta/LICENSE-SDK`](../quest-native/addons/godotopenxrvendors/meta/LICENSE-SDK) |
| Godot Meta Toolkit (Meta Platform SDK bindings, store entitlement check) | 1.0.3-stable | MIT; bundled Meta Platform SDK under its own terms | [`…/godot_meta_toolkit/LICENSE.txt`](../quest-native/addons/godot_meta_toolkit/LICENSE.txt), [`THIRD_PARTY_NOTICES.txt`](../quest-native/addons/godot_meta_toolkit/THIRD_PARTY_NOTICES.txt) |
| Cairo typeface (Arabic + Latin subsets) | @fontsource/cairo 5.1.0 | SIL Open Font License 1.1 | [`quest-native/assets/fonts/OFL-Cairo.txt`](../quest-native/assets/fonts/OFL-Cairo.txt) |

The trimmed OpenXR Vendors plugin also carries the license files of its other vendor
back-ends (Khronos, Android XR, Pico, Magic Leap); those back-ends are not enabled or packaged.

Build-only tools (not shipped in the APK): Blender 5.2.2 (`bpy`, GPL, used to author the
character and kit), Python with NumPy/SciPy/Pillow (used to generate sounds, textures and
the icon), Android SDK/NDK and Gradle (downloaded by the CI build).
