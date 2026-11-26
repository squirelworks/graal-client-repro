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
| R1 | 1 | 2 | 1 |
| R2 | 1 | 1 | 2 |

Radius 1, one per cell and scale 1 together grow nothing on the 5.12
(PR #973), so each run relaxes one of them.

## What to record

The world x, y of every cube's centre (screen position to world: 1 px =
80 m / screen width, the screen centre at (128, -128)), and the count.

## Pass

- The same count as below, and every cube within 0.5 m of a predicted
  position: the cell grid, the per-cell R250 seed and the x/y draws match.
- R2's cubes sit where R1's first cube in each cell does (same stream,
  first copy), at twice the size.
- A count that matches with positions that don't: the per-cell stream
  matches, the x/y draws don't. A different count: the cell grid or the
  count draw differs.

## Predicted by the rebuild

```
R1 radius 1, 2 per cell, scale 1: 18 cubes
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

R2 radius 1, 1 per cell, scale 2: 9 cubes
  (121.67, -137.56)
  (131.45, -139.32)
  (136.76, -132.86)
  (122.33, -124.84)
  (130.06, -131.60)
  (134.94, -130.03)
  (117.37, -123.11)
  (124.57, -122.89)
  (132.68, -120.26)
```
