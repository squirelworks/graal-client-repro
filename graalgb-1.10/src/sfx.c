/* Sound: one-shot effects on the two pulse channels and the noise channel.

   Start toggles the music. The demo's music player reads its song from
   cartridge RAM, which the cartridge does not have, so in the demo Start
   silences the game until it is reset. This rebuild does the same: there
   is no song, and Start turns the sound off. */
#include <gb/gb.h>
#include <gb/hardware.h>
#include "game.h"

uint8_t muted;

void sfx_init(void)
{
    NR52_REG = 0x80;
    NR50_REG = 0x77;
    NR51_REG = 0xFF;
}

static void noise(uint8_t env, uint8_t poly)
{
    NR41_REG = 0x00;
    NR42_REG = env;
    NR43_REG = poly;
    NR44_REG = 0x80;
}

static void pulse(uint8_t sweep, uint8_t env, uint16_t freq)
{
    NR10_REG = sweep;
    NR11_REG = 0x80;
    NR12_REG = env;
    NR13_REG = (uint8_t)freq;
    NR14_REG = 0x80 | ((freq >> 8) & 7);
}

void sfx(uint8_t n)
{
    if (muted)
        return;
    switch (n) {
    case SFX_SWORD: noise(0x81, 0x22); break;
    case SFX_LIFT:  pulse(0x16, 0x82, 0x600); break;
    case SFX_THROW: pulse(0x1E, 0x82, 0x700); break;
    case SFX_BREAK: noise(0xA2, 0x45); break;
    case SFX_TEXT:
        NR21_REG = 0x80; NR22_REG = 0x61; NR23_REG = 0xC0; NR24_REG = 0x87;
        break;
    case SFX_BOMB:  noise(0xF4, 0x71); break;
    case SFX_HIT:   pulse(0x2C, 0xA2, 0x500); break;
    case SFX_MENU:
        NR21_REG = 0x80; NR22_REG = 0x51; NR23_REG = 0x80; NR24_REG = 0x86;
        break;
    default: break;
    }
}

void music_toggle(void)
{
    /* no song: the player turns the volume and the channel routing off */
    muted = 1;
    NR50_REG = 0;
    NR51_REG = 0;
}
