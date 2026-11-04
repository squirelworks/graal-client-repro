package zo2;

import java.io.File;

/**
 * Checks for the Zelda Online 2 rebuild. No test framework: each check
 * prints on failure, and the program exits 1 if any failed.
 *
 * With ZO2_DATA set to a folder of original .zelda levels, every level in it
 * is also decoded (skipped when unset).
 */
public class TestZO2 {
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
    signs();
    arrays();
    standInLevels();
    walking();
    pushing();
    linksAndSigns();
    encodings();
    lobby();
    multiplayer();
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

  static void encodings() {
    check(Net.roomFor("level1.zelda").equals("Zlevel11.6"), "room name per level");
    check(Net.idFromSid(Net.sid(1234)).equals("00001234"), "two-character sender id");
    check(Net.sid(1).equals(" !"), "sid 1");
    long t = 912345678901L;
    check(Net.untime10(Net.time10(t)) == t && Net.time10(t).length() == 10, "login time, base 128");
  }

  /** A raw client on the lobby, for checking the server's lines. */
  static class Raw {
    Relay r;
    Raw(int port) throws Exception { r = new Relay("127.0.0.1", port, 2000); }
    String next() throws Exception {
      for (int i = 0; i < 200; i++) {
        String l = r.poll();
        if (l != null) return l;
        Thread.sleep(10);
      }
      return null;
    }
  }

  static void lobby() throws Exception {
    gserv.GServ g = new gserv.GServ(0, java.net.InetAddress.getByName("127.0.0.1"));
    g.start();
    try {
      Raw a = new Raw(g.port()), b = new Raw(g.port()), c = new Raw(g.port());
      a.r.send("NZlevel1.6#alice");
      check("I00000001".equals(a.next()), "first id");
      b.r.send("NZlevel1.6#bob");
      check("I00000002".equals(b.next()), "second id");
      check("+00000001alice".equals(b.next()), "newcomer sees the players already there");
      check("+00000002bob".equals(a.next()), "players see the newcomer");
      c.r.send("NZlevel2.6#carol");
      check("I00000003".equals(c.next()), "third id");
      b.r.send("P00000001");
      check("P00000002".equals(a.next()) && "P00000001".equals(b.next()), "party linked both ways");
      a.r.send("Dhello");
      check("Dhello".equals(b.next()), "D relayed inside the party, unchanged");
      b.r.send("-");
      check("-00000002".equals(a.next()), "- withdraws from the list");
      b.r.send("C");
      check("C00000002".equals(a.next()), "C leaves the party");
      a.r.send("Dagain");
      check(b.next() == null, "no relay after leaving");
      a.r.close(); b.r.close(); c.r.close();
    } finally {
      g.stop();
    }
  }

  static void multiplayer() throws Exception {
    gserv.GServ g = new gserv.GServ(0, java.net.InetAddress.getByName("127.0.0.1"));
    g.start();
    try {
      Game a = standIn(), b = standIn();
      a.nickname = "alice"; b.nickname = "bob";
      b.colours = new int[] {4, 5, 6, 7};
      Net na = new Net(new Relay("127.0.0.1", g.port(), 2000), a);
      Net nb = new Net(new Relay("127.0.0.1", g.port(), 2000), b);
      a.net = na; b.net = nb;
      nb.loginTime = na.loginTime + 1;
      b.keys = 1 << Game.RIGHT;
      for (int i = 0; i < 40; i++) {
        a.tick(); na.tick();
        if (i == 20) b.keys = 0;
        b.tick(); nb.tick();
        Thread.sleep(15);
      }
      Net.Peer pb = (Net.Peer) na.peers.get(nb.myId);
      check(pb != null, "a sees b");
      check(pb != null && pb.nick.equals("bob"), "nickname over D");
      check(pb != null && pb.x == b.x && pb.y == b.y, "position over D (" + (pb == null ? "" : pb.x + "," + pb.y) + " vs " + b.x + "," + b.y + ")");
      check(pb != null && pb.colours.length == 4 && pb.colours[1] == 5, "colours over D");
      Net.Peer pa = (Net.Peer) nb.peers.get(na.myId);
      check(pa != null && pa.nick.equals("alice"), "b sees a");
      check(na.leader() && !nb.leader(), "earliest login time leads");
      // b chats, then walks out of the level: a drops b
      b.chat = "hi";
      for (int i = 0; i < 6; i++) { b.tick(); nb.tick(); a.tick(); na.tick(); Thread.sleep(15); }
      check(pb != null && pb.chat.equals("hi"), "chat over D");
      b.enter("level2.zelda", 1, 30.5);
      for (int i = 0; i < 10; i++) { b.tick(); nb.tick(); a.tick(); na.tick(); Thread.sleep(15); }
      check(na.peers.get(nb.myId) == null && !nb.myId.equals(pb.id), "level change leaves the room");
      check(nb.room.equals("Zlevel21.6"), "new room joined (" + nb.room + ")");
      na.close(); nb.close();
    } finally {
      g.stop();
    }
  }

  static void realLevels() throws Exception {
    String dir = System.getenv("ZO2_DATA");
    if (dir == null) {
      System.out.println("skip: ZO2_DATA not set (original levels)");
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
