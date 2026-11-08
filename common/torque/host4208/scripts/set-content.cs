// Not TorqueScript. The 4.2.0.8 engine has no console and no .dso.
// The host runs these two residual statements and nothing else.
//
// A script new of GuiGraalCtrl is discarded. The name stays an engine type.
// setContentControl is how a script object becomes the screen.
// MainMenuGui2D is the content installed when setup passes.

new GuiGraalCtrl(Adventure);
setContentControl(MainMenuGui2D);
