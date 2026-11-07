// GuiGraalCtrl as 3.04 registers it. This is the level view.
//
// Thirty-one console methods, in registration order. Counts include the
// command name and, on a method, the object. A minimum of 2 is no script
// argument. Usage strings in the binary are empty, so the counts are
// the only signature. Each body is a stub.
//
// setNickName, setAccountName, setLanguage and retrieveAccountFields are
// 3.153 methods and are not on this table.
//
// Source: the 3.04 GUI notes. The same console names are in
// graal-3.04-G3D03014/src/TorqueHost304.pas. This file does not replace
// that list. Hardcoded key bytes are handled here. Script-bound key
// names are not.

#ifndef HOST304_GUIGRAAL_HPP
#define HOST304_GUIGRAAL_HPP

#include <string>
#include <vector>

struct GuiMethod {
  const char *name;
  int minCount;
  int maxCount;
};

int guiMethodCount();
const GuiMethod *guiMethods();
const GuiMethod *findGuiMethod(const std::string &name);

// Script arguments the count allows. -1 when min and max disagree
// (they do not, on this table).
int guiScriptArgs(const GuiMethod &method);

// One stub per console method. Each logs the call and returns.
void runGuiStub(const std::string &name, int argc, std::vector<std::string> &log);

// Canvas.setContent(AdventureGui). Wakes the level view.
bool openLevelView(std::vector<std::string> &log, std::string &error);

bool levelViewOpen();

// GuiGraalCtrl key virtual. keyByte and modifiers are the hardcoded path.
// A byte that is not one of those checks is not turned into a script key.
void onHardcodedKey(int keyByte, int modifiers, std::vector<std::string> &log);

#endif
