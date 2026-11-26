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

## Predicted by the rebuild

```
R1 radius 1, 2 per cell, scale 2: 18 cubes
  (121.67, -137.56)
  (123.56, -135.53)
  (131.45, -139.32)
  (129.61, -134.63)
  (136.76, -132.86)
  (135.57, -137.36)
  (122.33, -124.84)
  (121.29, -124.11)
  (130.06, -131.60)
  (131.46, -127.21)
  (134.94, -130.03)
  (133.66, -126.30)
  (117.37, -123.11)
  (120.97, -119.68)
  (124.57, -122.89)
  (128.16, -116.59)
  (132.68, -120.26)
  (132.36, -118.44)

R2 radius 2, 2 per cell, scale 1: 50 cubes
  (111.21, -143.97)
  (115.59, -140.19)
  (117.97, -144.44)
  (121.89, -143.03)
  (131.15, -141.08)
  (127.70, -142.87)
  (133.43, -147.57)
  (132.25, -145.71)
  (140.50, -145.81)
  (140.37, -144.56)
  (111.79, -132.20)
  (114.49, -132.81)
  (121.67, -137.56)
  (123.56, -135.53)
  (131.45, -139.32)
  (129.61, -134.63)
  (136.76, -132.86)
  (135.57, -137.36)
  (144.95, -134.58)
  (141.63, -136.45)
  (111.87, -126.42)
  (114.86, -126.77)
  (122.33, -124.84)
  (121.29, -124.11)
  (130.06, -131.60)
  (131.46, -127.21)
  (134.94, -130.03)
  (133.66, -126.30)
  (142.74, -124.68)
  (143.59, -129.40)
  (111.09, -121.65)
  (112.22, -118.78)
  (117.37, -123.11)
  (120.97, -119.68)
  (124.57, -122.89)
  (128.16, -116.59)
  (132.68, -120.26)
  (132.36, -118.44)
  (140.46, -119.89)
  (140.30, -121.16)
  (112.51, -114.89)
  (113.42, -110.83)
  (120.81, -115.25)
  (123.10, -111.23)
  (128.89, -108.13)
  (129.06, -108.01)
  (135.11, -110.55)
  (137.00, -109.42)
  (145.30, -111.15)
  (143.18, -113.70)
```
