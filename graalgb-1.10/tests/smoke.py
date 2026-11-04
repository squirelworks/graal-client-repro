"""Smoke test of the Graal Game Boy Color rebuild in an emulator (PyBoy,
Game Boy Color mode, no window). It plays the stand-in ROM through the
demo's main actions and reads the game's state from WRAM by the symbols in
GraalGB.noi.

Usage: python3 -I smoke.py BUILD_DIR [SHOTS_DIR]
  BUILD_DIR  holds GraalGB.gbc and GraalGB.noi (build/graalgb-1.10)
Needs: pip install pyboy
"""
import os
import sys

from pyboy import PyBoy
from pyboy.utils import WindowEvent as W

BUTTONS = {
    'up': (W.PRESS_ARROW_UP, W.RELEASE_ARROW_UP),
    'down': (W.PRESS_ARROW_DOWN, W.RELEASE_ARROW_DOWN),
    'left': (W.PRESS_ARROW_LEFT, W.RELEASE_ARROW_LEFT),
    'right': (W.PRESS_ARROW_RIGHT, W.RELEASE_ARROW_RIGHT),
    'a': (W.PRESS_BUTTON_A, W.RELEASE_BUTTON_A),
    'b': (W.PRESS_BUTTON_B, W.RELEASE_BUTTON_B),
    'select': (W.PRESS_BUTTON_SELECT, W.RELEASE_BUTTON_SELECT),
    'start': (W.PRESS_BUTTON_START, W.RELEASE_BUTTON_START),
}
ENT_SIZE = 26          # sizeof(ent_t) in src/game.h
# offsets in ent_t
X, Y, TYPE, DIR, STATE, CARRY, EVSTEP = 0, 2, 4, 5, 6, 7, 17


class Game:
    def __init__(self, build, shots):
        self.sym = {}
        with open(os.path.join(build, 'GraalGB.noi')) as f:
            for line in f:
                p = line.split()
                if len(p) == 3 and p[0] == 'DEF':
                    self.sym[p[1]] = int(p[2], 16)
        self.pb = PyBoy(os.path.join(build, 'GraalGB.gbc'), window='null', cgb=True,
                        sound_emulated=False)
        self.m = self.pb.memory
        self.shots = shots
        self.n = 0
        self.run(240)

    def run(self, frames):
        self.pb.tick(frames, self.shots is not None)

    def hold(self, b, frames):
        self.pb.send_input(BUTTONS[b][0])
        self.run(frames)
        self.pb.send_input(BUTTONS[b][1])
        self.run(4)

    def tap(self, b):
        self.hold(b, 4)

    def u8(self, name, off=0):
        return self.m[self.sym[name] + off]

    def w16(self, name, v):
        a = self.sym[name]
        self.m[a] = v & 255
        self.m[a + 1] = (v >> 8) & 255

    def ent(self, i, field, size=1):
        a = self.sym['_ents'] + ENT_SIZE * i + field
        v = self.m[a] | (self.m[a + 1] << 8 if size == 2 else 0)
        return v - 0x10000 if size == 2 and v & 0x8000 else v

    def set_ent(self, i, field, v):
        self.m[self.sym['_ents'] + ENT_SIZE * i + field] = v

    def warp(self, room, x, y):
        self.w16('_warp_x', x)
        self.w16('_warp_y', y)
        self.w16('_warp_room', room)
        self.run(40)

    def shot(self, name):
        if self.shots is None:
            return
        self.n += 1
        self.pb.screen.image.save(os.path.join(self.shots, '%02d_%s.png' % (self.n, name)))


FAILS = []


def check(what, ok, detail=''):
    print('%s  %s %s' % ('ok  ' if ok else 'FAIL', what, detail))
    if not ok:
        FAILS.append(what)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    shots = argv[2] if len(argv) > 2 else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    g = Game(argv[1], shots)

    # start: room 0, no title screen, the player in the middle facing down
    g.shot('start')
    check('starts in room 0', g.u8('_room_id') == 0)
    check('player starts at (256, 256) facing down',
          (g.ent(0, X, 2), g.ent(0, Y, 2), g.ent(0, DIR)) == (256, 256, 2),
          str((g.ent(0, X, 2), g.ent(0, Y, 2), g.ent(0, DIR))))
    check('the window is closed', g.u8('_text_open') == 0 and g.u8('_menu_open') == 0)

    # walking: 8 half pixels a logic tick (4 pixels, every second frame)
    x0 = g.ent(0, X, 2)
    g.hold('right', 20)
    dx = g.ent(0, X, 2) - x0
    check('walks right about 2 pixels a frame', 70 <= dx <= 96, 'moved %d half pixels in ~24 frames' % dx)
    g.shot('walked')
    g.hold('right', 160)
    check('the east link leads to room 2', g.u8('_room_id') == 2, 'room %d' % g.u8('_room_id'))
    check('arrives at the west edge, same row', g.ent(0, X, 2) < 160 and g.ent(0, Y, 2) == 256,
          str((g.ent(0, X, 2), g.ent(0, Y, 2))))
    g.shot('room2')
    g.hold('left', 40)
    check('the west link leads back to room 0', g.u8('_room_id') == 0)
    check('arrives at the east edge', g.ent(0, X, 2) > 440, str(g.ent(0, X, 2)))

    # a sign: up into the post north of the start
    g.warp(0, 264, 256)
    g.hold('up', 40)
    check('walking up into a sign opens its text', g.u8('_text_open') == 1)
    check('the text box slides up', g.u8('_win_y') < 144, 'window y %d' % g.u8('_win_y'))
    g.shot('sign')
    g.tap('up')
    check('pressing the way you face does not turn the page', g.u8('_text_open') == 1)
    for b in ('left', 'right', 'left', 'right'):
        if g.u8('_text_open'):
            g.tap(b)
    check('other directions page through and close it', g.u8('_text_open') == 0)

    # the sword
    g.pb.send_input(BUTTONS['b'][0])
    g.run(6)
    check('B swings the sword', g.ent(0, STATE) == 3)
    g.shot('sword')
    g.pb.send_input(BUTTONS['b'][1])
    g.run(30)
    check('the swing ends', g.ent(0, STATE) != 3)

    # the Select menu: a free pick over all 31 characters
    g.tap('select')
    g.run(30)
    check('Select opens the menu', g.u8('_menu_open') == 1)
    g.shot('menu')
    g.tap('right')
    check('right picks the next character', g.ent(0, TYPE) == 1)
    g.tap('left')
    g.tap('left')
    check('left wraps round to the last one', g.ent(0, TYPE) == 30)
    g.tap('right')
    g.tap('select')
    g.run(20)
    check('Select closes it', g.u8('_menu_open') == 0 and g.ent(0, TYPE) == 0)

    # lift and throw (character 0): the bush at tiles (6, 20) in room 4
    g.warp(4, 144, 336)
    g.hold('left', 2)
    g.run(8)
    g.tap('a')
    check('A in front of a bush lifts it', g.ent(0, STATE) == 9)
    g.run(30)
    check('then it is carried', g.ent(0, CARRY) == 1)
    g.shot('carry')
    g.tap('a')
    g.run(4)
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('A throws it', g.ent(0, CARRY) == 0 and (2 in kinds or 3 in kinds), str(kinds))
    g.run(40)
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('it breaks and is gone', all(k == 0 for k in kinds), str(kinds))

    # character 2's bomb and character 7's boomerang, in the open middle of room 0
    g.warp(0, 256, 256)
    g.set_ent(0, TYPE, 2)
    g.tap('a')
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('character 2 puts a bomb down with A', 4 in kinds, str(kinds))
    g.run(176)          # about 110 frames, then about 70 flashing
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('the bomb blows up', 5 in kinds, str(kinds))
    g.shot('blast')
    g.run(60)
    g.set_ent(0, TYPE, 7)
    g.tap('a')
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('character 7 throws a boomerang with A', 6 in kinds, str(kinds))
    g.run(70)
    kinds = [g.u8('_objs', i * 10) for i in range(4)]
    check('the boomerang comes back', 6 not in kinds, str(kinds))
    g.set_ent(0, TYPE, 0)

    # the captive in room 4: talk, then it shows how to lift and throw
    g.warp(4, 272, 336)
    g.hold('up', 30)
    check('walking into the captive opens its text', g.u8('_text_open') == 1)
    for b in ('left', 'right', 'left', 'right', 'left'):
        if g.u8('_text_open'):
            g.tap(b)
    g.run(20)
    g.shot('captive')
    ev = g.ent(1, EVSTEP)
    check('the captive starts its show', ev >= 2, 'step %d' % ev)
    g.run(160)
    check('then the second text opens', g.u8('_text_open') == 1 and g.ent(1, EVSTEP) == 6,
          'text %d, step %d' % (g.u8('_text_open'), g.ent(1, EVSTEP)))
    g.shot('captive2')

    # every room loads
    for r in range(7):
        g.warp(r, 256, 256)
        check('room %d loads' % r, g.u8('_room_id') == r, 'room %d' % g.u8('_room_id'))
    g.pb.stop(save=False)
    print('%d failed' % len(FAILS) if FAILS else 'all passed')
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
