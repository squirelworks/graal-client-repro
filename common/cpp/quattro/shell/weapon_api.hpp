// What GS2 weapon scripts ask of the Quattro program beyond the machine:
// the commands, events and `player` members in the order of Graal_analysis
// npc-library/gs2-weapon-corpus-2026-11-14.md ("Implementation order"),
// written on Program in shell/weapon_api.cpp. This header holds the
// show-image store those commands fill.
//
// Show-images (corpus step 5; client-internals/showimg-particles-and-gs2-format.md
// for the engines' TShowImg): each is a script object whose members are its
// fields (image, x, y, layer, red, green, blue, alpha, zoom, mode, partx,
// party, partw, parth, text, font, style, polygon, ani, dir), so
// `findimg(i).x = ...` and `changeimg*` change the same thing. They are
// numbered per script object (the object running the command).
//
// Rebuild choices (README.md, "GS2 weapon scripts"): layers 0 to 3 are drawn
// over the level and its players in level tiles; layer 4 and up over the HUD
// in window pixels. A show-image starts on layer 1.
#pragma once

#include "../../gs2/gs2.hpp"

#include <map>
#include <utility>
#include <vector>

namespace Quattro::Shell {

class ShowImages {
 public:
  // The show-image `index` of `owner`; made (on layer 1, colours 1, zoom 1)
  // when `create` and missing.
  gs2::VarPtr find(const gs2::Var* owner, int index, bool create);
  void hide(const gs2::Var* owner, int index);
  void hide_range(const gs2::Var* owner, int from, int to);
  // A show-image object that was destroyed, or every one of an owner that
  // went. False when `v` is no show-image.
  bool drop(const gs2::Var* v);
  void drop_owner(const gs2::Var* owner);
  void clear() { imgs_.clear(); }
  size_t size() const { return imgs_.size(); }

  // Drawing order: by layer, then owner order of first use, then index.
  std::vector<gs2::VarPtr> in_order() const;

 private:
  std::map<std::pair<const gs2::Var*, int>, gs2::VarPtr> imgs_;
};

}  // namespace Quattro::Shell
