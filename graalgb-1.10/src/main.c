/* Graal Game Boy Color rebuild: start-up and the frame loop.

   As in the demo, there is no title screen: the game opens in the first
   room. The CGB runs in double speed; the screen, scrolling and window
   move every frame and the game logic runs on every second frame (30 Hz). */
#include <gb/gb.h>
#include <gb/cgb.h>
#include "game.h"
#include "pak.h"

uint8_t keys, pressed;
uint8_t tick;
uint8_t scx, scy;
static uint8_t last_keys;
static uint8_t frame_no;

static void logic(void)
{
    keys = joypad();
    pressed = keys & ~last_keys;
    last_keys = keys;
    tick++;

    if (pressed & J_START)
        music_toggle();
    if (pressed & J_SELECT)
        menu_toggle();
    if (menu_open) {
        menu_input();
    } else {
        if (text_open)
            text_input();
        ents_tick();
        objs_tick();
        if (warp_room >= 0) {
            uint8_t r = (uint8_t)warp_room;
            warp_room = -1;
            room_load(r, warp_x, warp_y);
        }
    }
    draw_frame();
}

void main(void)
{
    uint8_t buf[7];
    DISPLAY_OFF;
    if (_cpu != CGB_TYPE || !pak_init()) {
        /* needs a Game Boy Color and an asset pack */
        DISPLAY_ON;
        while (1)
            wait_vbl_done();
    }
    cpu_fast();
    SPRITES_8x16;
    sfx_init();
    ui_init();
    pak_read(PK_START, 0, buf, 7);
    ents_reset();
    ents[0].active = 1;
    ents[0].dir = buf[5];
    ents[0].type = buf[6];
    ents[0].text = 0xFF;
    room_load(buf[0], buf[1] | (buf[2] << 8), buf[3] | (buf[4] << 8));
    SHOW_BKG;
    SHOW_SPRITES;
    while (1) {
        wait_vbl_done();
        SCX_REG = scx;
        SCY_REG = scy;
        ui_frame();
        frame_no++;
        if ((frame_no & 15) == 0)
            anim_step();
        if (frame_no & 1)
            logic();
    }
}
