# render: the Graal3D world renderer

The 3D view of the 4.20 to 5.12 clients, drawn from the ghosts the link
holds (plan: milestone 1 of the world renderer). It takes a scene (the
objects with their shapes, the server's Camera, the Sun and the Sky) and a
file resolver, and draws one frame into 32-bit pixels someone else owns.
It does not depend on the UDP link, so the Frankenstein 6.037 client can
link it beside its own world.

| File | Does |
|---|---|
| `math.hpp` | Vectors and matrices; the clients' rotation rule (a positive angle about +z turns right, about +x tilts down) |
| `mesh.*` | The one shape every reader produces: meshes, materials, collision meshes kept apart |
| `read_3ds.*` | `.3ds`: objects, vertices, texture coordinates, faces, face groups, materials with diffuse colour and texture name. `Col-` meshes are collision only; faces with no material are not drawn |
| `read_dts.*` | Torque `.dts`, versions 19 to 24 (the clients accept up to 24; 5.12 from 17): the three streams with their guards, nodes in their default pose, objects at the highest drawn detail level, standard and skin meshes (a child mesh shares its parent's vertices), triangle lists, strips and fans, the material list with each material's translucent flag. Below 23 the skins come in a list of their own, drawn with their detail level; below 22 the older sequence and node-state layout. Versions 17 and 18 (the pre-block stream), sorted and decal meshes are refused with a named error |
| `read_dif.*` | Torque `.dif`, InteriorResource 44 with Interior 0 (the clients' only accepted versions): the first detail level's points, planes, texgens, windings and surfaces, one mesh per material with texgen texture coordinates, surfaces drawn as strips. Both winding widths and both lightmap field widths are read; the marker materials (`NULL`, `ORIGIN`, `TRIGGER`, `FORCEFIELD`, `EMITTER`) are not drawn. Lightmaps, portals, zones, other detail levels and the extra sections after the interiors are skipped |
| `texture.*`, `stb_impl.cpp` | Textures (PNG, JPEG, GIF, BMP, TGA through `stb_image`) and the `Frame` view onto the caller's pixels |
| `resources.*` | Loads only the images the 5.12 draws, by content whatever the name (8-bit PNG, JPEG, GIF; GIF transparency as white; `kAll` for everything `stb_image` reads). Finds files by lower-case name in any subfolder of the roots (`levels3d/` by default), tries the image extensions on a texture named without one (`sky_fr`), the bare name of one named with one (a 5.x client stores downloads bare), and the extensions added to a material name with a dot of its own (`base.marble`), caches what loaded, and forgets misses on `rescan()` |
| `terrain.*` | The 5.12's streamed terrain (Graal_analysis `torque/terrain-512.md`): the chunk decoder (heights from their two-pass deltas, material ids per square, hole modes 0 to 2), a corrupt zlib stream applied as zeros as the client does, `heights.info` one name per line, the cache folder's `heights<x>-<y>.dat`, the client's re-encoding of a chunk (mode 2, used ids ascending, blends with the larger share first, its two-pass writer) and its stamp, and the 256 by 256 grid as one mesh centred on the origin |
| `scene.*` | The scene from a `GhostTable`: every `GameObject` with a shape, the named `Camera` and the field of view, the first `Sun` and `Sky`, the `TerrainBlock`'s settings, and each `WaterBlock` 1024 or more a side as a surface. A caller adds the terrain's shape as an object (`SceneObject::direct`) |
| `raster.*` | The software rasteriser: perspective-correct textured triangles, depth buffer, clipping to the near and far planes and to the view sides with a guard band (so a face reaching behind the camera, such as a sky-box face, is still drawn), bilinear texture filtering (held at the edges for sky-box faces), per-vertex light and fog |
| `draw.*` | One frame: the sky box, then each object lit by the sun and fogged toward the sky's fog colour |

The library exports `graal3dengine_renderFrame`, `graal3dengine_addResourceFolder`
and `graal3dengine_rescanResources` for the hosts (`include/graal3dengine.h`).

## What it was written from

- Graal_analysis `torque/udp-session.md` §8 (the `GameObject`, `Camera`,
  `Sun` and `Sky` updates), `graal3d/torque-engine-4x.md` and
  `torque/engine-and-formats.md` (the formats and `Col-` hulls),
  `client-internals/mac-ppc-runtime-surface-2026-11-09.md` (where files go
  under `levels3d`).
- The Seihai gserver's lab notes (`bin/docs/graal3d.md` in
  seihai-gserver-v2): the rotation rule, the 5.x client drawing only
  through a Camera, extension-less sky textures, a `.3ds` with no material
  loading but not drawn.
- The `.dts` layout: Torque3D's `ts/tsShape.cpp`, `ts/tsMesh.cpp` and
  `ts/tsShapeOldRead.cpp` (versions 19 to 21)
  (MIT, GarageGames), cross-checked with the Marble Blast web port's
  `dts_parser.ts` (MIT). The version bounds are the clients' own
  (Graal_analysis `torque/stock-tge-reference-mbg-2026-11-25.md`, the
  [bin 5.12] reads). Checked
  locally on 26 version-24 shapes from the Marble Blast Gold demo and the
  two version-24 Torque3D sample shapes (not in the repo).
- The `.dif` layout: the Marble Blast web port's `hx_dif` reader (MIT). Checked locally on the 32
  version-44 interiors of the Marble Blast Gold demo (not in the repo);
  a 128,000-case byte mutation of them under ASan found no faults.
- The public 3D Studio chunk format. Nothing from a decompile; no original
  Graal file is in the repo or its tests (the tests write their own shapes
  and textures).

## What is the rebuild's own

The pixels: the original draws through OpenGL, and no pixel match is
claimed (`docs/functional-parity.md`). Also, until a lab run checks them
side by side with a real 5.12:

- Nothing past the Sky's visible distance is drawn (1000 units without a
  Sky); fog rises linearly from half that distance.
- The sky box: front +y, right +x, back -y, left -x, top +z, bottom -z,
  each upright from inside; top and bottom with their top edge toward +y.
  Cloud layers, fog volumes and the solid colour are read but not drawn.
- Per-vertex lighting `ambient + colour * max(0, n . -direction)`; both
  sides of every triangle are drawn; texels under half alpha are cut out
  (for a `.dts`, only on a translucent material: an opaque Torque
  material's alpha is its environment-map amount).
- The terrain: each square's primary material only, each texture
  repeating every 8 squares, the grid wrapping at its far edges. Water: a
  flat unlit surface at its opacity, its texture every 16 m.
- A textured material draws its texture unmodulated; an untextured one its
  diffuse colour. A material whose texture is missing or undrawable draws
  white, as the 5.12 does (lab, 2026-11-25).
- Textures are filtered bilinearly, as a `GL_LINEAR` texture draws, with no
  mipmaps; sky-box faces are held at their edges, other textures wrap.

## Not yet

- [ ] The hosts presenting the frame in `GraalControl3D` (milestone 2)
- [ ] `.dts` versions 17 and 18 (no real 19 to 21 shape checked yet), sorted and decal meshes, IFL materials, the
  material flags past translucency (additive, self-illuminated, wrap)
- [ ] `.dif` lightmaps, other detail levels, interior versions other than 0
- [ ] `.ft` shapes (milestone 5); they are logged and skipped
- [ ] Animation threads (`GameObject` section 8)
- [ ] Terrain material blending and the client's terrain texture scale;
  water waves, reflection and shore; replicators (milestone 6)
- [ ] A terrain cache in the link (the stamps are computed; the link still
  asks for every chunk)
- [ ] `.dds`, `.jp2`, `.mng` textures
