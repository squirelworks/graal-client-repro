/* The window: the text box and the Select menu.

   Both are drawn with the font's own tiles in VRAM bank 1, framed by the
   font's corner, side and top tiles (flipped for the other edges), in BG
   palette 7; capitals and punctuation use the pack's capitals palette.

   The text box is nine rows at the bottom of the screen with its three
   lines of 18 characters on every second row. It slides up; a new press of
   a direction other than the one the player faces shows the next three
   lines, and after the last page it closes. Select fills the screen with
   the character menu: three heads, the middle one's name, and what B and A
   do. Left and right turn it, changing the player's character. */
#include <gb/gb.h>
#include <gb/cgb.h>
#include "game.h"
#include "pak.h"

uint8_t text_open, menu_open;
uint8_t win_y = 144, win_target = 144;

#define TEXT_Y    72
#define MENU_Y    0
#define PAGE      54

#define FT_ARROW_R 0x4D
#define FT_ARROW_L 0x4E
#define FT_CORNER  0x4F
#define FT_SIDE    0x50
#define FT_TOP     0x51

#define A_PRIO     0x80
#define A_FLIPY    0x40
#define A_FLIPX    0x20
#define A_BANK1    0x08

static uint8_t row[20], arow[20];
static uint16_t text_off;
static uint8_t text_len, text_page;
static uint8_t caps_pal;

void ui_init(void)
{
    uint8_t buf[512];
    uint8_t i, n;
    /* font: VRAM bank 1, from tile 0 */
    n = pak_byte(PK_FONT, 0);
    caps_pal = pak_byte(PK_FONT, 1) & 7;
    if (n > 128)
        n = 128;
    VBK_REG = 1;
    for (i = 0; i < n; i += 32) {
        pak_read(PK_FONT, 2 + (uint16_t)i * 16, buf, 512);
        set_bkg_data(i, n - i < 32 ? n - i : 32, buf);
    }
    VBK_REG = 0;
    /* sprite tiles: VRAM bank 0 from 128 */
    n = pak_byte(PK_SPRITES, 0);
    if (n > 112)
        n = 112;
    for (i = 0; i < n; i += 32) {
        pak_read(PK_SPRITES, 1 + (uint16_t)i * 16, buf, 512);
        set_sprite_data(128 + i, n - i < 32 ? n - i : 32, buf);
    }
    move_win(7, 144);
    SHOW_WIN;
}

static uint8_t glyph_attr(uint8_t c)
{
    uint8_t pal = 7;
    if ((c >= 0x21 && c <= 0x3A) || c >= 0x5F)
        pal = caps_pal;
    return A_PRIO | A_BANK1 | pal;
}

static void put_row(uint8_t y)
{
    VBK_REG = 1;
    set_win_tiles(0, y, 20, 1, arow);
    VBK_REG = 0;
    set_win_tiles(0, y, 20, 1, row);
}

/* top (edge 0), inside (1) or bottom (2) of the frame */
static void frame_row(uint8_t y, uint8_t edge)
{
    uint8_t i, base = A_PRIO | A_BANK1 | 7 | (edge == 2 ? A_FLIPY : 0);
    for (i = 0; i != 20; i++) {
        row[i] = edge == 1 ? 0 : FT_TOP;
        arow[i] = base;
    }
    row[0] = row[19] = edge == 1 ? FT_SIDE : FT_CORNER;
    arow[19] |= A_FLIPX;
    put_row(y);
}

/* a row of text inside the frame, from game codes; columns 1 to 18 */
static void text_row(uint8_t y, const uint8_t *codes, uint8_t n, uint8_t col)
{
    uint8_t i, c;
    frame_row(y, 1);
    for (i = 0; i != n && col + i < 19; i++) {
        c = codes[i];
        if (c < 0x20)
            c = 0x20;
        row[col + i] = c - 0x20;
        arow[col + i] = glyph_attr(c);
    }
    put_row(y);
}

static void draw_page(void)
{
    uint8_t line, buf[18], n;
    uint16_t at = (uint16_t)text_page * PAGE;
    frame_row(0, 0);
    for (line = 0; line != 7; line++)
        frame_row(1 + line, 1);
    frame_row(8, 2);
    for (line = 0; line != 3; line++) {
        if (at < text_len) {
            n = text_len - at > 18 ? 18 : (uint8_t)(text_len - at);
            pak_read(PK_ROOM0 + room_id, text_off + at, buf, n);
            text_row(2 + line * 2, buf, n, 1);
        }
        at += 18;
    }
}

void text_show(uint8_t idx)
{
    uint8_t rec[4];
    uint16_t i;
    if (idx >= ntexts)
        return;
    pak_read(PK_ROOM0 + room_id, texts_off + (uint16_t)idx * 4, rec, 4);
    text_off = rec[2] | (rec[3] << 8);
    for (i = 0; i != 255 && pak_byte(PK_ROOM0 + room_id, text_off + i); i++)
        ;
    text_len = (uint8_t)i;
    text_page = 0;
    text_open = 1;
    if (!menu_open) {
        draw_page();
        win_target = TEXT_Y;
    }
    sfx(SFX_TEXT);
}

void text_input(void)
{
    uint8_t d = 0xFF;
    if (pressed & J_UP) d = D_UP;
    else if (pressed & J_DOWN) d = D_DOWN;
    else if (pressed & J_LEFT) d = D_LEFT;
    else if (pressed & J_RIGHT) d = D_RIGHT;
    if (d == 0xFF || d == ents[0].dir)
        return;
    text_page++;
    if ((uint16_t)text_page * PAGE >= text_len) {
        text_open = 0;
        win_target = 144;
        keys = pressed = 0;             /* the press that closed it is used up */
        event_text_closed();
        return;
    }
    draw_page();
}

/* ---- the Select menu */
static uint8_t wrap(int8_t k)
{
    while (k < 0) k += 31;
    while (k >= 31) k -= 31;
    return (uint8_t)k;
}

/* A menu slot: the head's front view (its left half, drawn mirrored) in the
   character's first palette over its body in the second. */
static void load_head(uint8_t ctype, uint8_t slot)
{
    uint8_t buf[32], pal[16];
    uint16_t rec = 1 + (uint16_t)ctype * CHAR_REC;
    uint8_t h = pak_byte(PK_CHARS, rec + CH_HEAD);
    pak_read(PK_HEADS, 1 + (uint16_t)h * 128, buf, 32);
    set_sprite_data((uint8_t)(SP_HEADS + slot * 2), 2, buf);
    pak_read(PK_CHARS, rec + CH_PAL, pal, 16);
    set_sprite_palette(slot * 2, 2, (palette_color_t *)pal);
}

static const uint8_t lbl_b[8] = { 0x22, 0x4F, 0x4E, 0x4E, 0x49, 0x48, 0x20, 0x22 };   /* "Button B" */
static const uint8_t lbl_a[8] = { 0x22, 0x4F, 0x4E, 0x4E, 0x49, 0x48, 0x20, 0x21 };   /* "Button A" */
static uint8_t menu_aitem;

static void menu_draw(void)
{
    uint8_t k = ents[0].type, i, name[NAME_LEN], n, pal[8];
    frame_row(0, 0);
    for (i = 1; i != 17; i++) {
        frame_row(i, 1);
        if ((i >= 5 && i <= 8) || (i >= 14 && i <= 16)) {
            /* where the heads and icons sit, sprites show over the window */
            for (n = 4; n != 16; n++)
                arow[n] = A_BANK1 | 7;
            if (i == 7) {
                row[1] = row[2] = FT_ARROW_L;
                row[17] = row[18] = FT_ARROW_R;
                arow[1] = arow[2] = arow[17] = arow[18] = A_PRIO | A_BANK1 | caps_pal;
            }
            put_row(i);
        }
    }
    frame_row(17, 2);
    /* the middle character's name, centred */
    pak_read(PK_CHARS, 1 + (uint16_t)k * CHAR_REC, name, NAME_LEN);
    for (n = 0; n != NAME_LEN && name[n]; n++)
        ;
    if (n)
        text_row(9, name, n, 1 + (18 - n) / 2);
    text_row(13, lbl_b, 8, 1);
    for (i = 0; i != 8; i++) {
        row[11 + i] = lbl_a[i] - 0x20;
        arow[11 + i] = glyph_attr(lbl_a[i]);
    }
    put_row(13);
    /* heads, as sprites over the window: left, middle (two frames), right */
    load_head(wrap((int8_t)k - 1), 0);
    load_head(k, 1);
    load_head(wrap((int8_t)k + 1), 2);
    /* the sword's colour and the A item */
    n = pak_byte(PK_CHARS, 1 + (uint16_t)k * CHAR_REC + CH_SWORD);
    pak_read(PK_SWORDPAL, (uint16_t)(n > 2 ? 0 : n) * 8, pal, 8);
    set_sprite_palette(PAL_SWORD, 1, (palette_color_t *)pal);
    menu_aitem = pak_byte(PK_CHARS, 1 + (uint16_t)k * CHAR_REC + CH_AITEM);
    /* the A icon's palette: the bush's for lifting, else the other objects' */
    pak_read(PK_OBJPAL, menu_aitem == A_LIFT ? 0 : 8, pal, 8);
    set_sprite_palette(PAL_OBJ_B, 1, (palette_color_t *)pal);
}

void menu_toggle(void)
{
    menu_open = !menu_open;
    sfx(SFX_MENU);
    if (menu_open) {
        menu_draw();
        win_target = MENU_Y;
    } else {
        ents_palettes();
        if (text_open) {
            draw_page();
            win_target = TEXT_Y;
        } else {
            win_target = 144;
        }
    }
}

void menu_input(void)
{
    if (pressed & J_LEFT) {
        ents[0].type = wrap((int8_t)ents[0].type - 1);
    } else if (pressed & J_RIGHT) {
        ents[0].type = wrap((int8_t)ents[0].type + 1);
    } else {
        return;
    }
    sfx(SFX_MENU);
    menu_draw();
}

void menu_sprites(void)
{
    int16_t y = (int16_t)scy + win_y;
    uint8_t i, x;
    for (i = 0; i != 3; i++) {
        x = 32 + i * 40;
        spr8(scx + x, y + 47, (uint8_t)(SP_HEADS + i * 2), i * 2);
        spr8(scx + x + 8, y + 47, (uint8_t)(SP_HEADS + i * 2), (i * 2) | S_FLIPX);
        spr16(scx + x, y + 60, SP_MENU_BODY, i * 2 + 1);
    }
    spr16(scx + 32, y + 116, SP_ICONS, PAL_SWORD);
    if (menu_aitem != A_NONE)
        spr16(scx + 112, y + 116, SP_ICONS + menu_aitem * 4, PAL_OBJ_B);
}

void ui_frame(void)
{
    if (win_y < win_target) {
        win_y += 8;
        if (win_y > win_target)
            win_y = win_target;
    } else if (win_y > win_target) {
        win_y -= 8;
        if (win_y < win_target)
            win_y = win_target;
    }
    move_win(7, win_y);
}
