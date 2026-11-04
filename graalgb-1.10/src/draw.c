/* Camera and sprites. The camera keeps the player in the middle of the
   screen and stops at the room's edges. Sprites are 8x16; people are drawn
   front to back by their Y so that the nearer one wins. */
#include <gb/gb.h>
#include "game.h"

static uint8_t nspr;

void spr_begin(void)
{
    nspr = 0;
}

/* x, y: the sprite's top-left in room pixels */
void spr8(int16_t x, int16_t y, uint8_t tile, uint8_t prop)
{
    int16_t sx = x - scx, sy = y - scy;
    if (nspr >= 40 || sx <= -8 || sx >= 160 || sy <= -16 || sy >= 144)
        return;
    set_sprite_tile(nspr, tile);
    set_sprite_prop(nspr, prop);
    move_sprite(nspr, (uint8_t)(sx + 8), (uint8_t)(sy + 16));
    nspr++;
}

/* a 16x16 picture made of two 8x16 halves (tile, tile + 2) */
void spr16(int16_t x, int16_t y, uint8_t tile, uint8_t prop)
{
    if (prop & S_FLIPX) {
        spr8(x, y, tile + 2, prop);
        spr8(x + 8, y, tile, prop);
    } else {
        spr8(x, y, tile, prop);
        spr8(x + 8, y, tile + 2, prop);
    }
}

void spr_end(void)
{
    while (nspr < 40) {
        move_sprite(nspr, 0, 0);
        nspr++;
    }
}

/* the sword: [dir][phase] picture and top-left offset from the centre */
#define SW_V  0
#define SW_H  1
#define SW_D  2
typedef struct { uint8_t pic, prop; int8_t dx, dy; } sword_t;
static const sword_t sword_pose[4][3] = {
    /* up: from the left side to straight up */
    { { SW_H, S_FLIPX, -24, -10 }, { SW_D, S_FLIPX, -20, -22 }, { SW_V, 0, -6, -26 } },
    /* left: from above to straight left */
    { { SW_V, 0, -10, -26 }, { SW_D, S_FLIPX, -22, -20 }, { SW_H, S_FLIPX, -26, -6 } },
    /* down: from the right side to straight down */
    { { SW_H, 0, 8, -6 }, { SW_D, S_FLIPY, 6, 4 }, { SW_V, S_FLIPY, -2, 8 } },
    /* right: from above to straight right */
    { { SW_V, 0, 2, -26 }, { SW_D, 0, 6, -20 }, { SW_H, 0, 10, -6 } },
};

static void draw_sword(ent_t *e, int16_t cx, int16_t cy)
{
    uint8_t ph = e->timer > 8 ? 0 : e->timer > 4 ? 1 : 2;
    const sword_t *s = &sword_pose[e->dir][ph];
    uint8_t prop = PAL_SWORD | s->prop;
    if (s->pic == SW_V)
        spr8(cx + s->dx, cy + s->dy, SP_SWORD_V, prop);
    else
        spr16(cx + s->dx, cy + s->dy, s->pic == SW_H ? SP_SWORD_H : SP_SWORD_D, prop);
}

static void draw_ent(uint8_t i)
{
    ent_t *e = &ents[i];
    int16_t cx = e->x >> 1, cy = e->y >> 1;
    uint8_t pal = i < 5 ? i : 4;
    uint8_t step = (e->state == ST_WALK && (e->frame & 2)) ? 4 : 0;
    uint8_t tile, prop = pal;
    if (e->blink & 1)
        return;
    if (e->state == ST_SWORD)
        draw_sword(e, cx, cy);
    if (e->carry || e->state == ST_LIFT) {
        /* facing the screen with both arms up, the load over the head */
        tile = SP_CARRY + step;
        if (e->carry)
            spr16(cx - 8, cy - 18, SP_LOOK0 + (e->carry - 1) * 4, (e->carry - 1) ? PAL_OBJ_B : PAL_OBJ_A);
    } else if (e->dir == D_UP) {
        tile = SP_UP + step;
    } else if (e->dir == D_DOWN) {
        tile = SP_DOWN + step;
    } else {
        tile = SP_RIGHT + step;
        if (e->dir == D_LEFT)
            prop |= S_FLIPX;
    }
    spr16(cx - 8, cy - 8, tile, prop);
}

static void draw_objs(void)
{
    uint8_t i;
    obj_t *o;
    int16_t x, y;
    for (i = 0; i != MAX_OBJ; i++) {
        o = &objs[i];
        x = (o->x >> 1) - 8;
        y = (o->y >> 1) - 8;
        switch (o->kind) {
        case OB_LIFTING:
        case OB_THROWN:
            spr16(x, y, SP_LOOK0 + o->look * 4, o->look ? PAL_OBJ_B : PAL_OBJ_A);
            break;
        case OB_PIECES: {
            uint8_t d = (8 - o->timer) * 2;
            spr8(x - d, y - d, SP_LEAF, PAL_OBJ_A);
            spr8(x + 8 + d, y - d, SP_LEAF, PAL_OBJ_A | S_FLIPX);
            spr8(x - d, y + 4 + d, SP_LEAF, PAL_OBJ_A | S_FLIPY);
            spr8(x + 8 + d, y + 4 + d, SP_LEAF, PAL_OBJ_A | S_FLIPX | S_FLIPY);
            break;
        }
        case OB_BOMB:
            spr16(x, y, (o->timer < 35 && (o->timer & 2)) ? SP_FLASH : SP_BOMB, PAL_OBJ_B);
            break;
        case OB_BLAST: {
            uint8_t k;
            spr16(x, y, SP_BLAST, PAL_OBJ_B);
            for (k = 16; k <= 32; k += 16) {
                spr16(x - k, y, SP_BLAST, PAL_OBJ_B);
                spr16(x + k, y, SP_BLAST, PAL_OBJ_B);
                spr16(x, y - k, SP_BLAST, PAL_OBJ_B);
                spr16(x, y + k, SP_BLAST, PAL_OBJ_B);
            }
            break;
        }
        case OB_BOOM: {
            uint8_t t = SP_BOOM;
            if (o->phase & 2)
                t += 2;
            spr8(x + 4, y + 4, t, PAL_OBJ_B);
            break;
        }
        default:
            break;
        }
    }
}

void draw_frame(void)
{
    int16_t c;
    uint8_t order[MAX_ENT], n = 0, i, j, t;
    ent_t *p = &ents[0];
    c = (p->x >> 1) - 80;
    scx = c < 0 ? 0 : c > 96 ? 96 : (uint8_t)c;
    c = (p->y >> 1) - 72;
    scy = c < 0 ? 0 : c > 112 ? 112 : (uint8_t)c;
    spr_begin();
    if (menu_open) {
        menu_sprites();
        spr_end();
        return;
    }
    for (i = 0; i != MAX_ENT; i++)
        if (ents[i].active)
            order[n++] = i;
    /* nearest (largest Y) first */
    for (i = 1; i < n; i++)
        for (j = i; j && ents[order[j]].y > ents[order[j - 1]].y; j--) {
            t = order[j];
            order[j] = order[j - 1];
            order[j - 1] = t;
        }
    draw_objs();
    for (i = 0; i != n; i++)
        draw_ent(order[i]);
    spr_end();
}
