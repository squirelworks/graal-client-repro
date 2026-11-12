#include "profile.hpp"

#include <cctype>
#include <initializer_list>
#include <utility>

namespace Quattro::Net {

namespace {

using Range = std::pair<int, int>;

std::bitset<256> ids(std::initializer_list<Range> ranges) {
  std::bitset<256> set;
  for (auto [lo, hi] : ranges)
    for (int i = lo; i <= hi; ++i) set.set(static_cast<size_t>(i));
  return set;
}

// protocol/v6x-clients.md, "Server -> client ids (6.01, 6.03)": the 6.03r7
// switch, 92 ids.
std::bitset<256> plo_603() {
  return ids({{0, 25},   {27, 40},  {42, 43},  {45, 49},  {67, 69},  {74, 74},  {82, 82},
              {84, 84},  {101, 102}, {104, 107}, {109, 109}, {111, 111}, {131, 131}, {134, 134},
              {140, 140}, {150, 151}, {153, 156}, {166, 166}, {168, 168}, {170, 170}, {172, 174},
              {176, 176}, {178, 180}, {182, 183}, {185, 187}, {189, 191}, {194, 195}, {197, 198}});
}

// protocol/v6x-clients.md, "Client -> server ids (6.01, 6.03)".
std::bitset<256> pli_603() {
  return ids({{0, 20},  {22, 24}, {26, 30}, {32, 38},  {41, 41},   {44, 48},
              {50, 50}, {79, 79}, {92, 93}, {96, 98},  {130, 130}, {152, 152},
              {154, 162}});
}

std::vector<BuildProfile> make() {
  std::vector<BuildProfile> rows;

  BuildProfile r603;
  r603.label = "6.03r7 Linux";
  r603.token = "G3D0511C";
  r603.platform = "linux";
  r603.machine_fields = 4;
  r603.plo = plo_603();
  r603.pli = pli_603();
  r603.answers_ping = true;
  rows.push_back(r603);

  // 6.01r1: the 6.03r7 receive set without 111, the send set without 160.
  BuildProfile r601 = r603;
  r601.label = "6.01r1 Linux";
  r601.token = "G3D0108A";
  r601.plo.reset(111);
  r601.pli.reset(160);
  rows.push_back(r601);

  return rows;
}

std::string lower(std::string_view s) {
  std::string out(s);
  for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return out;
}

}  // namespace

const std::vector<BuildProfile>& profiles() {
  static const std::vector<BuildProfile> rows = make();
  return rows;
}

const BuildProfile* find_profile(std::string_view label) {
  std::string want = lower(label);
  for (const auto& row : profiles()) {
    std::string full = lower(row.label);
    if (full == want) return &row;
    // The bare version ("6.03r7") picks the row whose label starts with it.
    if (full.compare(0, want.size(), want) == 0 && full.size() > want.size() && full[want.size()] == ' ')
      return &row;
  }
  return nullptr;
}

bool handles_pre_switch(int id) { return id == 100 || id == 108; }

bool needs_raw_prefix(int id) { return id == 93 || id == 163; }

}  // namespace Quattro::Net
