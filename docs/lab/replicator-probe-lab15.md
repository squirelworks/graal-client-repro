# Lab 15: replicator placement against the rebuild's prediction

A kit for checking `common/cpp/graal3dengine/render/replicate.cpp` against
a real 5.12. Only the setup and our predicted numbers are here; shots and
logs stay in the lab share.

## Setup

- Our own gserver, flat terrain at z 0 (the lab's flat world).
- The player's avatar (the control object) at its spawn, (128, -128).
  Cover centres on the avatar, not the camera (Graal_analysis PR #968).
- A camera straight above the avatar at (128, -128, 40), looking down,
  field of view 90, so the view spans about 80 m.
- One `DynamicShapeReplicator`, `shapefiles` = `lp_white.3ds` (the 1 m
  lighting-probe cube), seed 1, box x/y -1024..1024, z -100..100, allow
  terrain only, shaperotate 0..0, offsetz 0.

| Run | Radius | Per cell (min = max) | Scale (min = max) |
|---|---|---|---|
| R1 | 1 | 2 | 2 |
| R2 | 2 | 2 | 1 |

On the 5.12, radius 1, one per cell and scale 1 grow nothing, and so
does raising any one of them alone (2 per cell, scale 2) or nearly so
(radius 2: a couple of cubes). Raising any two grows a full patch
(replicators-512.md). So each run raises two.

## What to record

The world x, y of every cube's centre (screen position to world: 1 px =
80 m / screen width, the screen centre at (128, -128)), and the count.

## Pass

- The same count as below, and every cube within 0.5 m of a predicted
  position: the cell grid, the per-cell R250 seed and the x/y draws match.
- R2's nine middle cells hold the same cubes as R1 (same cells, same
  stream), at half the size.
- A count that matches with positions that don't: the per-cell stream
  matches, the x/y draws don't. A different count: the cell grid or the
  count draw differs.

## First result (old kit, real 5.12)

The first run (radius 1, 2 per cell and 1 per cell, scale 1) drew 18 and
10 cubes with the old prediction missing every one by 1 to 6 m. Fitting
the measured centres showed three differences, now fixed in
`replicate.cpp`:

- `R250::next()` returns the updated word shifted right once (31 bits),
  as stock Torque's `randI`, and a copy's offset is that over 2^31.
- With min equal to max the cell draws no count: its first number goes
  to the first copy's x.
- Each copy uses 9 numbers: x, y, then the shape and turn z/y/x and
  scale z/y/x (7), so the second copy starts at the 10th.

With those, all 17 measured R1 cubes and all 9 measured R2 cubes sit
within 0.5 m of ours (mean 0.1 m). `tests/render_test.cpp` checks the
17 measured centres.

## Predicted by the rebuild (after the fix)

```
R1 radius 1, 2 per cell, scale 2: 18 cubes
  (119.46, -137.17)
  (118.95, -136.22)
  (130.75, -136.27)
  (124.84, -133.19)
  (133.90, -137.62)
  (138.86, -134.21)
  (120.84, -124.83)
  (123.97, -125.35)
  (124.12, -128.97)
  (129.58, -124.27)
  (139.29, -130.53)
  (139.10, -131.17)
  (122.22, -123.32)
  (118.98, -117.51)
  (125.38, -123.72)
  (130.93, -121.92)
  (136.68, -123.66)
  (132.83, -119.82)

R2 radius 2, 2 per cell, scale 1: 50 cubes
  (114.65, -142.40)
  (115.97, -144.21)
  (117.92, -143.01)
  (121.54, -141.06)
  (129.32, -140.43)
  (127.11, -146.15)
  (132.60, -143.29)
  (137.53, -143.87)
  (147.81, -143.75)
  (142.04, -143.81)
  (112.01, -138.10)
  (110.99, -132.75)
  (119.46, -137.17)
  (118.95, -136.22)
  (130.75, -136.27)
  (124.84, -133.19)
  (133.90, -137.62)
  (138.86, -134.21)
  (145.16, -137.52)
  (140.81, -139.19)
  (109.41, -126.06)
  (113.97, -128.57)
  (120.84, -124.83)
  (123.97, -125.35)
  (124.12, -128.97)
  (129.58, -124.27)
  (139.29, -130.53)
  (139.10, -131.17)
  (146.70, -130.63)
  (141.52, -126.21)
  (110.94, -122.46)
  (112.90, -117.89)
  (122.22, -123.32)
  (118.98, -117.51)
  (125.38, -123.72)
  (130.93, -121.92)
  (136.68, -123.66)
  (132.83, -119.82)
  (144.08, -123.77)
  (142.85, -123.85)
  (108.30, -109.74)
  (115.89, -113.29)
  (123.51, -109.59)
  (117.99, -112.45)
  (126.85, -109.56)
  (131.91, -109.47)
  (138.19, -110.45)
  (133.57, -113.50)
  (145.39, -109.35)
  (147.12, -114.41)
```

