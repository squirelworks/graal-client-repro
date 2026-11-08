// Line script. The 4.2.0.8 engine has no Torque console.
// TServerLevel is the level object. openLevel opens it and placeTile
// records one tile. keyset names are script-bound. Hardcoded key bytes
// stay in the engine key handler.

new TServerLevel(level);
level.openLevel("offlinetutorial.gmap");
level.placeTile(0, 0, 1);

keyset.bind(up);
keyset.bind(down);
keyset.bind(left);
keyset.bind(right);
keyset.bind(attack);
keyset.bind(action);
keyset.bind(map);
keyset.bind(switchtochat);
keyset.bind(itemlist);
keyset.bind(pause);
keyset.bind(microphone);
