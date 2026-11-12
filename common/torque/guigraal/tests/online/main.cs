// Written for the tq-play online test: a stand-in install root, not a
// Graal script. The control names are the ones GuiGraalCtrl and the
// shipped scripts use; the two functions do what the shipped menu buttons
// do (switch to the list, connect).
new GuiCanvas(Canvas) {};
new GuiControl(MainMenuGui) {
  new GuiTextEditCtrl(NickEdit) {};
  new GuiTextEditCtrl(AccountEdit) {};
  new GuiTextEditCtrl(PassEdit) {};
};
new GuiControl(ServerListGui) {
  new GuiTextListCtrl(ServerList) {};
  new GuiTextEditCtrl(ServerLanguage) {};
  new GuiTextEditCtrl(ServerGraalVersion) {};
  new GuiTextEditCtrl(ServerHomepage) {};
  new GuiMLTextCtrl(ServerDescription) {};
  new GuiTextEditCtrl(ServerDirectName) {};
};
new GuiControl(AdventureGui) {
  new GuiGraalCtrl(Adventure) {
    new GuiTextEditCtrl(ChatBar) {};
  };
};
function switchToServerList() {
  $pref::Graal::nickname = NickEdit.getValue();
  $pref::Graal::accountname = AccountEdit.getValue();
  Adventure.setPassWord(PassEdit.getValue());
  Canvas.setContent(ServerListGui);
  Adventure.openServerList();
}
function ServerList::onSelect(%this, %row) { Adventure.selectServer(%row); }
function connectPressed() {
  if (strlen(ServerDirectName.getValue()) > 0) Adventure.serverDirectConnect(ServerDirectName.getValue());
  else Adventure.connectToSelectedServer();
}
function onExit() {}
Canvas.setContent(MainMenuGui);
NickEdit.setText("online nick");
