# Goal: functionally the same, not the same look

Owner decision, 2026-11-19: each rebuild aims to **behave** like the
original client, not to **look** like it. A rebuild is done when it does
what the original does, action by action, against the same servers. It does
not have to match the original's pixels, fonts, window chrome or artwork.

## What counts (in scope)

- **Wire.** Login line, framing, ciphers, the packets the client sends and
  when it sends them, and how it handles every packet it receives.
- **Session flow.** Start screen to server list to login to level, server
  warps, reconnects, offline mode where the build had one, quitting.
- **Play.** Movement and collision, wake rules, sword and weapons, items,
  damage, baddies, NPCs, level links, gmaps, chat, other players.
- **Scripts.** The build's GS1 or GS2 engine: which commands and events
  exist and what they do, including show-images and GUI controls as far as
  scripts can observe them.
- **Files.** Which files the client asks for and when, what it does when one
  is missing.
- **Controls and windows as features.** A key, button or menu entry the
  original had should exist and do the same thing (the F1 options, the
  server list's account fields, the quit question). What it looks like is
  not checked.
- **Robustness.** Headless runs, stress, long sessions, hostile packets.

## What no longer gates anything (out of scope)

- Pixel or frame comparisons with the original, including the per-size
  frame checks.
- Window sizes, borders, title-bar buttons, fonts, captions' styling,
  colours and layout, as long as the control is there and works.
- Extracting and wiring each exe's own icons, bitmaps, forms and fonts.
  What is already wired stays; missing ones are not a gap.
- Title screens and logos that carry no behaviour.

Look-related work that is already merged stays. Nobody removes it; it just
stops being a reason to hold a release.

## The engine stays

The faithful engine work (`docs/engine-repro-policy.md`: Torque for early
3.x, the launcher plus engine library for mid-4.x and early 5.x, Quattro
for late 5.x and 6.x) is part of being functionally the same, because the
original ran its game on that engine. It stays the target for each folder
and a release gate, as the policy says.

## How a check is done

Side-by-side runs with the original stay the method, but the notes record
behaviour: what was sent and received, where the player ended up, what
happened after each action, and whether either side crashed. A difference
in looks alone is not filed as a gap.
