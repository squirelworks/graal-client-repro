package zo1;

import java.io.ByteArrayOutputStream;
import java.util.Vector;

/**
 * A Zelda Online level (.zelda): a 64x64 board of 8x8 tiles, then links,
 * baddies and signs.
 *
 * Board: an LSB-first bit stream of 11-bit codes (Z3-V1.02) or 12-bit codes
 * (Z3-V1.03). A code with its top bit set is a control code: the low byte is
 * a repeat count, and bit 8 makes the next run a double run (two tiles A B
 * written count times). Any other code is a tile id. Tiles fill the board
 * row by row.
 *
 * After the board: link lines "file x y w h newx newy" until "#", then
 * baddies as 4-byte records (x, y, type, '\n') until a record starting with
 * 0xFF, then sign lines (x+32, y+32, text in the sign alphabet) to the end.
 *
 * Written from graal_analysis formats/level-binary.md and
 * client-internals/precursors-and-fan-builds.md.
 */
public class Level {
  public static final int W = 64, H = 64;

  public static class Link {
    public String file;
    public double x, y, w, h, newX, newY; // newX/newY < 0: keep that coordinate
  }

  public static class Baddy {
    public int x, y, type;
  }

  public static class Sign {
    public int x, y;
    public String text;
  }

  public String magic = "";
  public String name = "";
  public int[] tiles = new int[W * H];
  public Vector links = new Vector();
  public Vector baddies = new Vector();
  public Vector signs = new Vector();

  public int tile(int x, int y) {
    if (x < 0 || y < 0 || x >= W || y >= H) return -1;
    return tiles[x + y * W];
  }

  /** The code width a magic uses, or 0 when this build cannot read it. */
  public static int codeWidth(String magic) {
    if (magic.equals("Z3-V1.02")) return 11;
    if (magic.equals("Z3-V1.03")) return 12;
    return 0;
  }

  /** Reads a level. Throws IllegalArgumentException on a broken file. */
  public static Level parse(byte[] d, String name) {
    if (d.length < 8) throw new IllegalArgumentException("level too short");
    Level lv = new Level();
    lv.name = name;
    lv.magic = new String(d, 0, 8);
    int width = codeWidth(lv.magic);
    if (width == 0) throw new IllegalArgumentException("unknown level magic " + lv.magic);
    int p = decodeBoard(d, 8, width, lv.tiles);

    // links
    while (p < d.length) {
      int e = lineEnd(d, p);
      String line = new String(d, p, e - p).trim();
      p = Math.min(d.length, e + 1);
      if (line.length() == 0 || line.equals("#")) break;
      Link l = parseLink(line);
      if (l != null) lv.links.addElement(l);
    }
    // baddies: 4-byte records; take three bytes before looking at the line end
    while (p < d.length) {
      if ((d[p] & 0xFF) == 0xFF) {
        p = Math.min(d.length, lineEnd(d, p) + 1);
        break;
      }
      if (p + 3 > d.length) { p = d.length; break; }
      Baddy b = new Baddy();
      b.x = d[p] & 0xFF; b.y = d[p + 1] & 0xFF; b.type = d[p + 2] & 0xFF;
      lv.baddies.addElement(b);
      p = Math.min(d.length, lineEnd(d, p + 3) + 1);
    }
    // signs
    while (p < d.length) {
      int e = lineEnd(d, p);
      if (e - p >= 2) {
        Sign s = new Sign();
        s.x = (d[p] & 0xFF) - 32;
        s.y = (d[p + 1] & 0xFF) - 32;
        byte[] t = new byte[e - p - 2];
        System.arraycopy(d, p + 2, t, 0, t.length);
        s.text = SignText.decode(t);
        lv.signs.addElement(s);
      }
      p = e + 1;
    }
    return lv;
  }

  static int lineEnd(byte[] d, int p) {
    while (p < d.length && d[p] != '\n') p++;
    return p;
  }

  static Link parseLink(String line) {
    String[] t = split(line);
    if (t.length < 7) return null;
    Link l = new Link();
    int n = t.length;
    StringBuffer f = new StringBuffer();
    for (int i = 0; i < n - 6; i++) {
      if (i > 0) f.append(' ');
      f.append(t[i]);
    }
    l.file = f.toString();
    try {
      l.x = Double.valueOf(t[n - 6]).doubleValue();
      l.y = Double.valueOf(t[n - 5]).doubleValue();
      l.w = Double.valueOf(t[n - 4]).doubleValue();
      l.h = Double.valueOf(t[n - 3]).doubleValue();
      l.newX = Double.valueOf(t[n - 2]).doubleValue();
      l.newY = Double.valueOf(t[n - 1]).doubleValue();
    } catch (NumberFormatException ex) {
      return null;
    }
    return l;
  }

  static String[] split(String s) {
    java.util.StringTokenizer st = new java.util.StringTokenizer(s, " ");
    String[] r = new String[st.countTokens()];
    for (int i = 0; i < r.length; i++) r[i] = st.nextToken();
    return r;
  }

  /** Decodes 4096 tiles from position p; returns the position after the last code. */
  public static int decodeBoard(byte[] d, int p, int width, int[] out) {
    int flag = 1 << (width - 1);
    int mask = (1 << width) - 1;
    long buf = 0;
    int have = 0, n = 0, count = 1;
    boolean dbl = false;
    int first = -1;
    while (n < out.length) {
      while (have < width) {
        if (p >= d.length) throw new IllegalArgumentException("board ends early");
        buf |= ((long) (d[p++] & 0xFF)) << have;
        have += 8;
      }
      int c = (int) (buf & mask);
      buf >>>= width;
      have -= width;
      if ((c & flag) != 0) {
        count = c & 0xFF;
        dbl = (c & 0x100) != 0;
        first = -1;
      } else if (dbl) {
        if (first < 0) {
          first = c;
        } else {
          for (int i = 0; i < count && n < out.length; i++) {
            out[n++] = first;
            if (n < out.length) out[n++] = c;
          }
          dbl = false; count = 1; first = -1;
        }
      } else {
        for (int i = 0; i < count && n < out.length; i++) out[n++] = c;
        count = 1;
      }
    }
    return p;
  }

  /**
   * Encodes a board with the same rules (used by the tests and the stand-in
   * level): runs of 2 or more equal tiles become a single run.
   */
  public static byte[] encodeBoard(int[] tiles, int width) {
    ByteArrayOutputStream o = new ByteArrayOutputStream();
    int flag = 1 << (width - 1);
    long buf = 0;
    int have = 0;
    int i = 0;
    int[] codes = new int[tiles.length * 2];
    int nc = 0;
    while (i < tiles.length) {
      int j = i;
      while (j < tiles.length && tiles[j] == tiles[i] && j - i < 255) j++;
      int run = j - i;
      if (run > 1) codes[nc++] = flag | run;
      codes[nc++] = tiles[i];
      i = j;
    }
    for (int k = 0; k < nc; k++) {
      buf |= ((long) codes[k]) << have;
      have += width;
      while (have >= 8) {
        o.write((int) (buf & 0xFF));
        buf >>>= 8;
        have -= 8;
      }
    }
    if (have > 0) o.write((int) (buf & 0xFF));
    return o.toByteArray();
  }
}
