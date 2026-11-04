package javagraal;

/**
 * Where tile t sits on a pics1 sheet. The sheet is 32 tiles tall and made
 * of 16-tile-wide columns of 512 tiles each, so a 2x2 object is t, t+1, t+16,
 * t+17. The tile size is the sheet's height / 32: 8 for a 512x256 sheet,
 * 16 for a 1024x512 or 2048x512 one. Read from the sheets themselves.
 */
public class TileSheet {
  public static int tileSize(int sheetHeight) {
    return Math.max(1, sheetHeight / 32);
  }

  public static int sx(int t, int ts) {
    t &= 4095;
    return (t / 512) * 16 * ts + (t % 16) * ts;
  }

  public static int sy(int t, int ts) {
    t &= 4095;
    return ((t % 512) / 16) * ts;
  }

  public static int sx(int t) { return sx(t, 8); }

  public static int sy(int t) { return sy(t, 8); }
}
