package javagraal;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;

/**
 * The rebuild's own stand-in graphics and levels, drawn here in code, so the
 * program runs with nothing next to it. None of it comes from the original
 * game. A pics1.gif, arrays.dat or level file from an install replaces it.
 */
public class StandIn {
  public static final String SECOND = "standin2.graal";
  public static final int GRASS = 0, GRASS2 = 1, PATH = 16, TREE = 32, WATER = 33,
      SIGN = 48, WALL = 49, DOOR = 50;

  public static BufferedImage sheet() {
    BufferedImage im = new BufferedImage(512, 256, BufferedImage.TYPE_INT_RGB);
    Graphics2D g = im.createGraphics();
    g.setColor(Color.black);
    g.fillRect(0, 0, 512, 256);
    for (int t = 0; t < 2048; t++) {
      int x = TileSheet.sx(t), y = TileSheet.sy(t);
      switch (t) {
        case GRASS:
          fill(g, x, y, new Color(72, 160, 72));
          break;
        case GRASS2:
          fill(g, x, y, new Color(72, 160, 72));
          g.setColor(new Color(240, 220, 90));
          g.fillRect(x + 2, y + 2, 2, 2);
          g.fillRect(x + 5, y + 5, 2, 2);
          break;
        case PATH:
          fill(g, x, y, new Color(200, 170, 110));
          break;
        case TREE:
          fill(g, x, y, new Color(30, 90, 40));
          g.setColor(new Color(20, 60, 25));
          g.fillOval(x + 1, y + 1, 6, 6);
          break;
        case WATER:
          fill(g, x, y, new Color(50, 90, 200));
          g.setColor(new Color(150, 190, 255));
          g.drawLine(x + 1, y + 3, x + 4, y + 3);
          break;
        case SIGN:
          fill(g, x, y, new Color(72, 160, 72));
          g.setColor(new Color(120, 80, 40));
          g.fillRect(x + 1, y + 1, 6, 4);
          g.fillRect(x + 3, y + 5, 2, 3);
          break;
        case WALL:
          fill(g, x, y, new Color(150, 150, 160));
          g.setColor(new Color(100, 100, 110));
          g.drawLine(x, y + 4, x + 7, y + 4);
          break;
        case DOOR:
          fill(g, x, y, new Color(40, 30, 20));
          break;
        default:
          break;
      }
    }
    g.dispose();
    return im;
  }

  static void fill(Graphics2D g, int x, int y, Color c) {
    g.setColor(c);
    g.fillRect(x, y, 8, 8);
  }

  public static boolean[] walkable() {
    boolean[] w = new boolean[4096];
    w[GRASS] = w[GRASS2] = w[PATH] = w[DOOR] = true;
    return w;
  }

  /** A stand-in level file (GR-V1.00 bytes), or null for other names. */
  public static byte[] level(String name) {
    int[] t = new int[64 * 64];
    String links, sign;
    if (name.equals(Game.START_LEVEL)) {
      border(t);
      for (int x = 20; x < 64; x++) { set(t, x, 31, PATH); set(t, x, 32, PATH); }
      for (int y = 30; y < 34; y++) for (int x = 60; x < 64; x++) set(t, x, y, PATH);
      for (int y = 10; y < 16; y++) for (int x = 40; x < 50; x++) set(t, x, y, WATER);
      set(t, 30, 26, SIGN); set(t, 31, 26, SIGN);
      for (int i = 0; i < 40; i++) set(t, 5 + (i * 7) % 54, 5 + (i * 11) % 54, GRASS2);
      links = SECOND + " 63 30 1 4 1 -1\n";
      sign = sign(30, 26, "Welcome! These are stand-in\ngraphics. Put a Java Graal copy\nnext to the program.");
    } else if (name.equals(SECOND)) {
      border(t);
      for (int y = 30; y < 34; y++) for (int x = 0; x < 4; x++) set(t, x, y, PATH);
      for (int y = 20; y < 28; y++) for (int x = 20; x < 34; x++) set(t, x, y, WALL);
      set(t, 26, 27, DOOR); set(t, 27, 27, DOOR);
      links = Game.START_LEVEL + " 0 30 1 4 61 -1\n";
      sign = "";
    } else {
      return null;
    }
    ByteArrayOutputStream o = new ByteArrayOutputStream();
    byte[] m = "GR-V1.00".getBytes();
    o.write(m, 0, m.length);
    byte[] b = Level.encodeBoard(t, 12);
    o.write(b, 0, b.length);
    byte[] l = (links + "#\n").getBytes();
    o.write(l, 0, l.length);
    o.write(0xFF); o.write(0xFF); o.write(0xFF); o.write('\n');
    o.write('#'); o.write('\n'); // no NPCs
    byte[] s = sign.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);
    o.write(s, 0, s.length);
    return o.toByteArray();
  }

  static String sign(int x, int y, String text) {
    byte[] e = SignText.encode(text);
    StringBuffer r = new StringBuffer();
    r.append((char) (x + 32)).append((char) (y + 32));
    for (int i = 0; i < e.length; i++) r.append((char) (e[i] & 0xFF));
    r.append('\n');
    return r.toString();
  }

  static void border(int[] t) {
    for (int i = 0; i < t.length; i++) t[i] = GRASS;
    for (int i = 0; i < 64; i++) {
      for (int k = 0; k < 2; k++) {
        set(t, i, k, TREE); set(t, i, 63 - k, TREE);
        set(t, k, i, TREE); set(t, 63 - k, i, TREE);
      }
    }
  }

  static void set(int[] t, int x, int y, int v) {
    t[x + y * 64] = v;
  }
}
