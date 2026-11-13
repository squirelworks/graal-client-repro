// JPEG pictures for the Torque GUI (3.153's graalscreen3d.jpg and the
// other .jpg menu art), decoded with stb_image (common/cpp/third_party/stb).
// Stock TGE 1.2 reads .jpg as well as .png bitmaps, and a bitmap named
// without an extension is tried as .png first, then .jpg.
#pragma once

#include "image.hpp"

#include <cstddef>
#include <cstdint>
#include <string>

namespace Torque::Gui {

// Decodes a baseline or progressive JPEG to opaque RGBA. On failure `out`
// is unchanged and `error` names the problem. The size limits are the PNG
// reader's (kMaxImageSide, kMaxImagePixels).
bool decode_jpeg(const std::uint8_t* data, std::size_t size, Image& out, std::string& error);

}  // namespace Torque::Gui
