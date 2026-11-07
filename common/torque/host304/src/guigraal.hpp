// GuiGraalCtrl as 3.04 registers it.
//
// Thirty-one methods, in registration order. Counts include the command
// name and, on a method, the object. A minimum of 2 is no script
// argument. Usage strings in the binary are empty, so the counts are
// the only signature. Bodies are unknown: each call is a stub that logs.
//
// setNickName, setAccountName, setLanguage and retrieveAccountFields are
// 3.153 methods and are not on this table.
//
// Source: Graal_analysis torque/engine-304.md. The same names are in
// graal-3.04-G3D03014/src/TorqueHost304.pas. This file does not replace
// that list.

#ifndef HOST304_GUIGRAAL_HPP
#define HOST304_GUIGRAAL_HPP

#include <string>
#include <vector>

struct GuiMethod {
  const char *name;
  int minCount;
  int maxCount;
};

// Adventure is the native control the 2D scripts call. Created at boot.
// No control is drawn.

int guiMethodCount();
const GuiMethod *guiMethods();
const GuiMethod *findGuiMethod(const std::string &name);

// Script arguments the count allows. -1 when min and max disagree
// (they do not, on this table).
int guiScriptArgs(const GuiMethod &method);

// One stub per method. Each logs the call and returns. The body is not known.
void runGuiStub(const std::string &name, int argc, std::vector<std::string> &log);

#endif
