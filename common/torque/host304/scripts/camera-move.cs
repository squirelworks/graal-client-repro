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
