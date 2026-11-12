// The console classes the shipped 3.04 scripts create with `new`
// (Graal_analysis torque/study-torque-clients.md section 5; all 31 are
// registered in the 3.04 engine, section 5.1), plus GuiCanvas, which the
// engine creates for createCanvas().
//
// Parents: every GUI control is a GuiControl and every GuiControl is a
// SimGroup (its children are its members). Intermediate stock classes
// between a control and GuiControl are not read for 3.04, so each control
// links straight to GuiControl (rebuild policy). Only the data model is
// here; drawing, awake order and input are later stages.

#include "engine.hpp"

namespace Torque {

void register_classes_304(Engine& e) {
  e.add_class({"GuiControl", "SimGroup", true, true, true});
  e.add_class({"GuiCanvas", "GuiControl", true, true, true});
  for (const char* control : {
           "GuiTextCtrl", "GuiButtonCtrl", "GuiTextEditCtrl", "GuiScrollCtrl", "GuiWindowCtrl",
           "GuiCheckBoxCtrl", "GuiPopUpMenuCtrl", "GuiTextListCtrl", "GuiMLTextCtrl", "GuiSliderCtrl",
           "GuiChunkedBitmapCtrl", "GuiTreeViewCtrl", "GuiInspector", "GuiControlListPopUp",
           "GuiMLTextEditCtrl", "GuiBitmapBorderCtrl", "GuiBitmapCtrl", "GuiRadioCtrl", "GuiConsole",
           "GuiConsoleEditCtrl", "GuiConsoleTextCtrl", "GuiEditCtrl", "GuiFrameSetCtrl",
           "GuiProgressCtrl", "GuiInputCtrl", "GuiGraalCtrl"})
    e.add_class({control, "GuiControl", true, true, true});
  e.add_class({"GuiControlProfile", "SimObject", true, false, false});
  e.add_class({"GuiCursor", "SimObject", true, false, false});

  // The canvas holds one content control. Waking it (onWake) and drawing
  // are the GUI stage; this stores it and tells the host.
  e.add_function("GuiCanvas", "setContent", 3, 3, "canvas.setContent(ctrl)", [](Engine& en, SimObject* canvas, Args& a) {
    if (!canvas) return std::string();
    SimObject* content = en.find_object(a[2]);
    canvas->set_field("content", content ? std::to_string(content->id) : std::string());
    if (content && en.on_set_content) en.on_set_content(canvas, content);
    return std::string();
  });
  e.add_function("GuiCanvas", "getContent", 2, 2, "canvas.getContent()", [](Engine&, SimObject* canvas, Args&) {
    const std::string id = canvas ? canvas->field("content") : std::string();
    return id.empty() ? std::string("-1") : id;
  });
}

} // namespace Torque
