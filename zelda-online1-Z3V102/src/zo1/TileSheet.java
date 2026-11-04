package zo1;

/**
 * Where tile t sits on pics1.gif (512x256, 8x8 tiles). The sheet is four
 * 128-pixel-wide columns of 16 tiles by 32 rows, so a 2x2 object is t, t+1,
 * t+16, t+17. Read from the layout of the sheet and the 2x2 tile groups in
 * arrays.dat.
 */
public class TileSheet {
  public static final int TILE = 8;

  public static int sx(int t) {
    t &= 2047;
    return (t / 512) * 128 + (t % 16) * TILE;
  }

  public static int sy(int t) {
    t &= 2047;
    return ((t % 512) / 16) * TILE;
  }
}
