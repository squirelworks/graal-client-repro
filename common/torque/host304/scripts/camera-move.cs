// One TorqueScript file for the 3.04 host.
//
// The runner executes each statement. It is not the stock console and
// it does not load main.cs.
//
// Camera is a stock TGE class. The 3.04 note says it has three methods
// and does not name them, so setTransform is provisional.
// Adventure is the registered GuiGraalCtrl. moveUp's body is unknown;
// the host logs the call.

new Camera(LabCam);
LabCam.setTransform("1 0 10 1 0 0 0");
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
