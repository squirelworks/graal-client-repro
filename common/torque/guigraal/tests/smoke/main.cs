// Written for the tq-play smoke test: a stand-in install root, not a Graal
// script. It builds the controls GuiGraalCtrl uses and the one script hook
// a key binding would call.
new GuiCanvas(Canvas) {};
new GuiControl(MainMenuGui) {};
new GuiControl(AdventureGui) {
  new GuiGraalCtrl(Adventure) {
    new GuiTextEditCtrl(ChatBar) {};
  };
};
function moveRight(%val) { Adventure.moveRight(%val); }
function onExit() {}
$pref::Graal::nickname = "smoke";
Canvas.setContent(MainMenuGui);
