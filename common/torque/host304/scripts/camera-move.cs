// One TorqueScript file for the 3.04 host.
//
// The runner executes each statement. It is not the stock console and
// it does not load main.cs.
//
// Script-bound keys are the binds below. Hardcoded key bytes stay in
// GuiGraalCtrl and are not named here.
// Camera is a stock TGE class. setTransform moves it.
// Canvas.setContent(AdventureGui) opens the GuiGraalCtrl level view.

new ActionMap(moveMap);
moveMap.bind(keyboard, up, moveUp);
moveMap.bind(keyboard, left, moveLeft);
moveMap.bind(keyboard, down, moveDown);
moveMap.bind(keyboard, right, moveRight);
moveMap.bind(keyboard, a, doA);
moveMap.bind(keyboard, s, doS);
moveMap.bind(keyboard, d, doD);
moveMap.bind(keyboard, q, doQ);
moveMap.bind(keyboard, p, doP);
moveMap.bind(keyboard, m, doM);
moveMap.bind(keyboard, t, doMicro);
moveMap.bind(keyboard, f3, bringUpOptions);
moveMap.bind(keyboard, f7, showPlayerList);
moveMap.bind(keyboard, f8, showServerList);
moveMap.bind(keyboard, escape, escapeFromGame);
moveMap.bind(keyboard, unset, showLoadLevel);

new ActionMap(GlobalActionMap);
GlobalActionMap.bindCmd(keyboard, f1, contextHelp);
GlobalActionMap.bindCmd(keyboard, f2, ToggleConsole);
GlobalActionMap.bind(keyboard, alt-enter, toggleFullScreen);

Canvas.setContent(AdventureGui);

new Camera(LabCam);
LabCam.setTransform("1 0 10 1 0 0 0");
moveMap.fire(up, 1);
Adventure.moveUp(1);
Adventure.moveLeft(1);
Adventure.moveDown(1);
Adventure.moveRight(1);
Adventure.doA(1);
Adventure.doS(1);
Adventure.doD(1);
Adventure.doQ(1);
Adventure.doP(1);
Adventure.doM(1);
Adventure.doMicro(1);
Adventure.setChat("hi");
Adventure.setPassWord("x");
Adventure.openServerList();
Adventure.selectServer("lab");
Adventure.selectServerCategory("all");
Adventure.startOfflineMode();
Adventure.connectToSelectedServer();
Adventure.serverDirectConnect("loopback");
Adventure.privateMessageSend();
Adventure.playerListOpenPlayer(1);
Adventure.playerListProfile(1);
Adventure.updateLoadLevelFields();
Adventure.loadLevel("onlinestartlocal.nw", "30", "30");
Adventure.updatePlayerProfile(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
Adventure.updatePlayerMuted(0);
Adventure.updateMidiVolume();
Adventure.updateMp3Volume();
Adventure.updateRadioVolume();
Adventure.updateMicroActivationLevel();
Adventure.updateGraalOptions();
