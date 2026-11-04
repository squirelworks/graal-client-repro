/* Rooms: loading from the pack, the live map, walls, links and signs.

   A room is one 32x32 BG map (256x256 pixels). The loader writes the whole
   map to VRAM with the screen off and the camera scrolls over it. */
#include <gb/gb.h>
#include <gb/cgb.h>
#include <string.h>
#include "game.h"
#include "pak.h"

uint8_t room_id = 0xFF, room_tileset = 0xFF;
uint8_t map[1024];
uint8_t attr[1024];
uint8_t nlinks, ntexts, nnpcs;
uint16_t links_off, texts_off;
int16_t warp_room = -1, warp_x, warp_y;
static uint8_t walk[32];
static uint8_t buf[512];

/* animated tiles of the room's tileset */
#define MAX_ANIM 4
static uint8_t nanim, anim_frame;
static uint8_t anim_tile[MAX_ANIM], anim_n[MAX_ANIM];
static uint16_t anim_off[MAX_ANIM];

static void load_tileset(uint8_t ts)
{
    uint8_t id = ts ? PK_TILES1 : PK_TILES0;
    uint8_t i;
    /* tiles 0-127 to VRAM bank 0, 128-255 to bank 1, at the same numbers */
    for (i = 0; i != 8; i++) {
        pak_read(id, (uint16_t)i * 512, buf, 512);
        VBK_REG = i >= 4 ? 1 : 0;
        set_bkg_data(i * 32, 32, buf);
    }
    VBK_REG = 0;
    pak_read(PK_WALK, ts ? 32 : 0, walk, 32);
    /* animated tiles: tileset 0's list, then tileset 1's */
    {
        uint16_t off = 0;
        uint8_t n, t, k;
        n = pak_byte(PK_ANIM, 0);
        off = 1;
        for (t = 0; t != ts; t++) {
            for (k = 0; k != n; k++)
                off += 2 + (uint16_t)pak_byte(PK_ANIM, off + 1) * 16;
            n = pak_byte(PK_ANIM, off);
            off++;
        }
        nanim = n > MAX_ANIM ? MAX_ANIM : n;
        for (k = 0; k != nanim; k++) {
            anim_tile[k] = pak_byte(PK_ANIM, off);
            anim_n[k] = pak_byte(PK_ANIM, off + 1);
            anim_off[k] = off + 2;
            off += 2 + (uint16_t)anim_n[k] * 16;
        }
    }
    room_tileset = ts;
}

void anim_step(void)
{
    uint8_t k;
    anim_frame++;
    for (k = 0; k != nanim; k++) {
        pak_read(PK_ANIM, anim_off[k] + (uint16_t)(anim_frame % anim_n[k]) * 16, buf, 16);
        VBK_REG = anim_tile[k] >= 128 ? 1 : 0;
        set_bkg_data(anim_tile[k], 1, buf);
    }
    VBK_REG = 0;
}

void room_load(uint8_t r, int16_t x, int16_t y)
{
    uint8_t id = PK_ROOM0 + r;
    uint8_t ts, ps, i;
    uint16_t npcs_off;
    DISPLAY_OFF;
    room_id = r;
    ts = pak_byte(id, 0);
    ps = pak_byte(id, 1);
    nlinks = pak_byte(id, 2);
    ntexts = pak_byte(id, 3);
    nnpcs = pak_byte(id, 4);
    links_off = 5 + 2048;
    texts_off = links_off + (uint16_t)nlinks * 8;
    npcs_off = texts_off + (uint16_t)ntexts * 4;
    if (ts != room_tileset)
        load_tileset(ts);
    pak_read(PK_BGPAL, 1 + (uint16_t)ps * 64, buf, 64);
    set_bkg_palette(0, 8, (palette_color_t *)buf);
    pak_read(id, 5, map, 1024);
    pak_read(id, 5 + 1024, attr, 1024);
    VBK_REG = 1;
    set_bkg_tiles(0, 0, 32, 32, attr);
    VBK_REG = 0;
    set_bkg_tiles(0, 0, 32, 32, map);
    /* people: entity 0 is the player, the rest come from the room */
    for (i = 1; i != MAX_ENT; i++)
        ents[i].active = 0;
    for (i = 0; i != nnpcs && i + 1 < MAX_ENT; i++) {
        pak_read(id, npcs_off + (uint16_t)i * 16, buf, 16);
        ent_spawn_npc(i + 1, buf);
    }
    objs_reset();
    ents[0].x = x;
    ents[0].y = y;
    ents[0].state = ST_IDLE;
    ents[0].ktimer = 0;
    ents[0].carry = 0;
    player_frozen = 0;
    ents_palettes();
    draw_frame();
    DISPLAY_ON;
}

/* pixel coordinates; outside the room counts as a wall */
uint8_t tile_solid_px(int16_t px, int16_t py)
{
    uint8_t t;
    if (px < 0 || py < 0 || px > 255 || py > 255)
        return 1;
    t = map[((uint16_t)(py >> 3) << 5) | (px >> 3)];
    return !(walk[t >> 3] & (1 << (t & 7)));
}

void map_set(uint8_t tx, uint8_t ty, uint8_t t)
{
    uint16_t i = ((uint16_t)ty << 5) | tx;
    uint8_t a = (attr[i] & 0xF7) | (t >= 128 ? 0x08 : 0);
    map[i] = t;
    if (a != attr[i]) {
        attr[i] = a;
        VBK_REG = 1;
        set_bkg_tile_xy(tx, ty, a);
        VBK_REG = 0;
    }
    set_bkg_tile_xy(tx, ty, t);
}

void room_restore_tile(uint8_t tx, uint8_t ty)
{
    uint16_t i = ((uint16_t)ty << 5) | tx;
    map_set(tx, ty, pak_byte(PK_ROOM0 + room_id, 5 + i));
}

/* The link test point is the player's centre moved one half pixel the way
   the player faces (the demo crosses at x 496 going east and at x 16 going
   west, in half pixels). */
void links_check(void)
{
    ent_t *p = &ents[0];
    int16_t hx = p->x, hy = p->y;
    uint8_t i, tx, ty, l[8];
    if (p->dir == D_UP) hy--;
    else if (p->dir == D_DOWN) hy++;
    else if (p->dir == D_LEFT) hx--;
    else hx++;
    if (hx < 0 || hy < 0 || hx >= ROOM_UNITS || hy >= ROOM_UNITS)
        return;
    tx = hx >> 4;
    ty = hy >> 4;
    for (i = 0; i != nlinks; i++) {
        pak_read(PK_ROOM0 + room_id, links_off + (uint16_t)i * 8, l, 8);
        if (tx >= l[0] && tx < l[0] + l[2] && ty >= l[1] && ty < l[1] + l[3]) {
            warp_room = l[6];
            warp_x = l[4] == 0xFF ? p->x : (int16_t)l[4] * TILE_UNITS;
            warp_y = l[5] == 0xFF ? p->y : (int16_t)l[5] * TILE_UNITS;
            return;
        }
    }
}

/* A sign's text: the faced tile lies in the 2x2 block at the text's spot.
   Texts at (0, 0) belong to people and events, not to the map. */
uint8_t text_at(uint8_t tx, uint8_t ty)
{
    uint8_t i, t[2];
    for (i = 0; i != ntexts; i++) {
        pak_read(PK_ROOM0 + room_id, texts_off + (uint16_t)i * 4, t, 2);
        if (t[0] == 0 && t[1] == 0)
            continue;
        if (tx >= t[0] && tx <= t[0] + 1 && ty >= t[1] && ty <= t[1] + 1)
            return i;
    }
    return 0xFF;
}
