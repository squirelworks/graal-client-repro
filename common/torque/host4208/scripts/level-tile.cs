// Provisional line script. The 4.2.0.8 engine has no Torque console.
// TServerLevel is the level object the engine note names.
// openLevel and placeTile are stubs of the level and 2D tile path.
// startOfflineMode loads offlinetutorial.gmap.

new TServerLevel(level);
level.openLevel("offlinetutorial.gmap");
level.placeTile(0, 0, 1);
