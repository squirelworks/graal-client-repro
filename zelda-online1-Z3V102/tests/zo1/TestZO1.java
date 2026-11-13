package zo1;

import java.io.File;

/**
 * Checks for the Zelda Online 1 rebuild. No test framework: each check
 * prints on failure, and the program exits 1 if any failed.
 *
 * With ZO1_DATA set to a folder of original .zelda levels, every level in it
 * is also decoded (skipped when unset).
 */
public class TestZO1 {
  static int checks, failed;

  static void check(boolean ok, String what) {
    checks++;
    if (!ok) {
      failed++;
      System.out.println("FAIL: " + what);
    }
  }

  public static void main(String[] args) throws Exception {
    board();
    titleHudStart();
    signs();
    arrays();
    standInLevels();
    walking();
    pushing();
    linksAndSigns();
    realLevels();
    System.out.println(checks + " checks, " + failed + " failed");
    System.exit(failed == 0 ? 0 : 1);
  }

  static void board() {
    int[] t = new int[4096];
    for (int i = 0; i < t.length; i++) t[i] = (i / 7) % 900;
    for (int w = 11; w <= 12; w++) {
      byte[] b = Level.encodeBoard(t, w);
      int[] back = new int[4096];
      Level.decodeBoard(b, 0, w, back);
      check(java.util.Arrays.equals(t, back), "board round trip at " + w + " bits");
    }
    // a double run: {double 3} 5 6, then a 4093-tile... keep it to a hand-made stream
    int[] codes = {0x800 | 0x100 | 3, 5, 6};
    byte[] b = pack(codes, 12, 4096 - 6, 9);
    int[] out = new int[4096];
    Level.decodeBoard(b, 0, 12, out);
    check(out[0] == 5 && out[1] == 6 && out[4] == 5 && out[5] == 6 && out[6] == 9, "double run");
    // 11-bit: the flag is 0x400
    int[] c11 = {0x400 | 4, 7};
    b = pack(c11, 11, 4096 - 4, 1);
    Level.decodeBoard(b, 0, 11, out);
    check(out[0] == 7 && out[3] == 7 && out[4] == 1, "11-bit single run");
    check(Level.codeWidth("Z3-V1.02") == 11 && Level.codeWidth("Z3-V1.03") == 12, "code widths");
    check(Level.codeWidth("GR-V1.00") == 0, "GR-V is not read by this build");
  }

  /** Codes, then 'rest' copies of tile 'fill' as runs of up to 255. */
  static byte[] pack(int[] codes, int w, int rest, int fill) {
    java.util.Vector v = new java.util.Vector();
    for (int i = 0; i < codes.length; i++) v.addElement(new Integer(codes[i]));
    int flag = 1 << (w - 1);
    while (rest > 0) {
      int n = Math.min(255, rest);
      v.addElement(new Integer(flag | n));
      v.addElement(new Integer(fill));
      rest -= n;
    }
    java.io.ByteArrayOutputStream o = new java.io.ByteArrayOutputStream();
    long buf = 0;
    int have = 0;
    for (int i = 0; i < v.size(); i++) {
      buf |= ((long) ((Integer) v.elementAt(i)).intValue()) << have;
      have += w;
      while (have >= 8) { o.write((int) (buf & 0xFF)); buf >>>= 8; have -= 8; }
    }
    if (have > 0) o.write((int) buf);
    return o.toByteArray();
  }

  static void signs() {
    byte[] zelda = {'9', '>', 'E', '=', ':', 'y', (byte) 0x80, '{'};
    check(SignText.decode(zelda).equals("Zelda \n#A"), "sign alphabet: " + SignText.decode(zelda));
    String s = "Hello, world 42!\nNext line?";
    check(SignText.decode(SignText.encode(s)).equals(s), "sign round trip");
  }

  static void arrays() {
    byte[] d = Arrays.write(new int[][] {{1, 2, 3}, {4096}});
    Arrays a = Arrays.parse(d);
    check(a.items.size() == 2 && a.flat(0).length == 3 && a.flat(1)[0] == 4096, "flat arrays");
    // a nested array: kind 1, two flat arrays inside
    byte[] n = {0, 1, 0, 2, 0, 0, 0, 1, 0, 0, 0, 7, 0, 0, 0, 0};
    a = Arrays.parse(n);
    Object[] o = (Object[]) a.items.elementAt(0);
    check(o.length == 2 && ((int[]) o[0])[0] == 7 && ((int[]) o[1]).length == 0, "nested arrays");
  }

  static void standInLevels() {
    Level l = Level.parse(StandIn.level("level1.zelda"), "level1.zelda");
    check(l.magic.equals("Z3-V1.03"), "stand-in magic");
    check(l.links.size() == 1 && ((Level.Link) l.links.elementAt(0)).file.equals("level2.zelda"), "stand-in link");
    check(((Level.Link) l.links.elementAt(0)).newY < 0, "keep-y link");
    check(l.signs.size() == 1 && ((Level.Sign) l.signs.elementAt(0)).text.startsWith("Welcome!"), "stand-in sign");
    check(l.tile(0, 0) == StandIn.TREE && l.tile(30, 29) == StandIn.GRASS, "stand-in board");
    check(StandIn.level("nosuch.zelda") == null, "unknown stand-in");
  }

  static Game standIn() {
    Game g = new Game(new Assets(null, null));
    g.start(null);
    return g;
  }

  static void titleHudStart() {
    Game g = new Game(new Assets(null, null));
    g.start(null);
    // the original's view origin from (23, 37), by the rebuild's rule
    int camX = 23 * 8 + 8 - Renderer.VIEW_W / 2, camY = 37 * 8 + 8 - Renderer.VIEW_H / 2;
    check(camX == 64 && camY == 192, "the start's view origin is the original's (64, 192)");
    g.title = true;
    hold(g, Game.RIGHT, 5);
    check(g.ticks == 0, "the title screen holds the board");
    Renderer r = new Renderer(g.assets.tileSheet());
    java.awt.image.BufferedImage t = r.title();
    boolean white = false;
    for (int x = 121; x < 300 && !white; x++)
      for (int y = 370; y <= 382 && !white; y++)
        white = (t.getRGB(x, y) & 0xFFFFFF) == 0xFFFFFF;
    check(t.getWidth() == 512 && t.getHeight() == 448 && white, "title: 512x448, the white line from x 121 on rows 370-382");
    g.title = false;
    r.draw(g);
    check((r.frame().getRGB(27, 50) & 0xFFFFFF) == 0x28B43C, "HUD: the magic fill at (24, 47)");
    check(g.rupees == 0 && g.bombs == 0 && g.arrows == 5 && g.hearts == 3, "HUD: 000 / 00 / 05 and three hearts");
  }

  static void hold(Game g, int dir, int ticks) {
    g.keys = dir < 0 ? 0 : 1 << dir;
    for (int i = 0; i < ticks; i++) g.tick();
  }

  static void walking() {
    Game g = standIn();
    double x0 = g.x;
    hold(g, Game.RIGHT, 4);
    check(g.x == x0 + 4 * Game.STEP, "half a tile per tick");
    check(g.dir == Game.RIGHT && g.moving, "facing right while walking");
    hold(g, -1, 1);
    check(!g.moving, "stops when released");
  }

  static void pushing() {
    Game g = standIn();
    g.x = 10; g.y = 1; // feet against the top tree rows
    hold(g, Game.UP, 1);
    hold(g, Game.UP, 16);
    check(!g.pushing() && g.push == 17, "no push pose before tick 18 (" + g.push + ")");
    hold(g, Game.UP, 1);
    check(g.pushing(), "push pose at tick 18");
    hold(g, Game.UP, 20);
    check(g.push == 18, "push counter loops 38 -> 18 (" + g.push + ")");
    hold(g, -1, 1);
    check(g.push == 0, "release resets the push counter");
  }

  static void linksAndSigns() {
    Game g = standIn();
    // under the sign at (30, 27): walk up into it
    g.x = 29.5; g.y = 27;
    hold(g, Game.UP, 4);
    check(g.signText != null && g.signText.startsWith("Welcome!"), "sign opens walking up into it");
    hold(g, -1, 1);
    g.action = true; g.tick(); g.action = false; g.tick();
    check(g.signText == null, "action closes the sign");
    // east exit
    g.x = 58; g.y = 30.5;
    g.keys = 1 << Game.RIGHT;
    for (int i = 0; i < 20 && g.level.name.equals("level1.zelda"); i++) g.tick();
    check(g.level.name.equals("level2.zelda"), "east link to level2 (" + g.level.name + ")");
    check(g.x == 1.0 && g.y == 30.5, "arrival x set, y kept (" + g.x + "," + g.y + ")");
    g.keys = 1 << Game.LEFT;
    for (int i = 0; i < 20 && g.level.name.equals("level2.zelda"); i++) g.tick();
    check(g.level.name.equals("level1.zelda") && g.x == 61.0, "west link back");
  }

  static void realLevels() throws Exception {
    String dir = System.getenv("ZO1_DATA");
    if (dir == null) {
      System.out.println("skip: ZO1_DATA not set (original levels)");
      return;
    }
    File[] fs = new File(dir).listFiles();
    int n = 0, bad = 0;
    for (int i = 0; fs != null && i < fs.length; i++) {
      if (!fs[i].getName().endsWith(".zelda")) continue;
      n++;
      try {
        Level l = Level.parse(Assets.readAll(fs[i]), fs[i].getName());
        if (l.tiles.length != 4096) bad++;
      } catch (Exception e) {
        bad++;
        System.out.println(fs[i].getName() + ": " + e.getMessage());
      }
    }
    check(n > 0 && bad == 0, n + " original levels, " + bad + " failed");
  }
}
