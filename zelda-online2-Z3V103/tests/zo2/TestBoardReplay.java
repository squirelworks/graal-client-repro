package zo2;

import java.awt.image.BufferedImage;
import java.net.InetAddress;
import java.util.Vector;

/** Generated fixtures through real loopback GServ/Relay/Net and Game boards.
 * No original board bytes or original-program execution. */
final class TestBoardReplay {
  static class Wire extends Relay {
    final Vector<String> sent = new Vector<String>();
    Wire(int port) throws Exception { super("127.0.0.1", port, 2000); }
    public void send(String line) { sent.addElement(line); super.send(line); }
    int boards() {
      int count = 0;
      for (String line : sent) if (line.length() >= 4 && line.charAt(0) == 'D' && line.charAt(3) == 'B') count++;
      return count;
    }
  }

  static void check(boolean ok, String what) { TestZO2.check(ok, "board replay: " + what); }
  static Game game() {
    Game g = new Game(new Assets(null, null));
    check(g.start("level1.zelda"), "generated stand-in starts");
    return g;
  }
  static Net connect(Game g, int port) throws Exception {
    Net n = new Net(new Wire(port), g);
    g.net = n;
    return n;
  }
  static Wire wire(Net n) { return (Wire) n.relay; }
  static void pump(int ticks, Net... clients) throws Exception {
    for (int i = 0; i < ticks; i++) {
      for (Net n : clients) n.tick();
      Thread.sleep(5);
    }
  }
  static void paired(Net... clients) throws Exception {
    for (int i = 0; i < 400; i++) {
      pump(1, clients);
      boolean ready = true;
      for (Net n : clients) {
        ready &= n.myId.length() == 8 && n.peers.size() == clients.length - 1;
        for (Object p : n.peers.values()) ready &= ((Net.Peer) p).loginTime >= 0;
      }
      if (ready) return;
    }
    throw new AssertionError("loopback clients did not pair and exchange timestamps");
  }
  static String boardLine(Net sender, String payload) {
    return "D" + Net.sid(sender.myNum) + "B" + payload;
  }

  static void run() throws Exception {
    gserv.GServ server = new gserv.GServ(0, InetAddress.getByName("127.0.0.1"));
    server.start();
    Net a = null, b = null, c = null;
    try {
      Game ga = game(), gb = game();
      a = connect(ga, server.port());
      b = connect(gb, server.port());
      a.loginTime = 100; b.loginTime = 200;
      paired(a, b);
      check(a.leader() && !b.leader(), "known older timestamp controls two peers");

      // Six distinct values prove whole coordinates, high-first words and X-major
      // order instead of a row-major decoder that passes square/uniform tests.
      int[] tiles = {128, 257, 386, 515, 644, 773};
      BoardChange rectangle = new BoardChange(28, 20, 2, 3, tiles);
      String payload = rectangle.encode();
      check(payload.charAt(0) == Net.c(28) && payload.charAt(1) == Net.c(20) &&
        payload.charAt(2) == Net.c(19) && payload.charAt(3) == Net.c(1) &&
        payload.charAt(4) == Net.c(0), "independent wire anchors");
      int bSent = wire(b).boards();
      Renderer rendered = new Renderer(StandIn.sheet());
      gb.x = 30; gb.y = 29;
      rendered.draw(gb);
      int beforePixel = rendered.frame().getRGB(104, 32);
      check(ga.modifyBoard(28, 20, 2, 3, tiles), "real local board mutation sends B");
      tiles[0] = 999; // history must own its values
      pump(30, a, b);
      check(gb.level.tile(28, 20) == 128 && gb.level.tile(28, 22) == 386 &&
        gb.level.tile(29, 20) == 515 && gb.level.tile(29, 22) == 773, "remote Game board receives x-major rectangle");
      check(gb.level.tile(14, 10) != 128, "coordinates were not divided by two");
      check(wire(b).boards() == bSent, "remote B has no network echo");
      check(ga.boardHistory.size() == 1 && gb.boardHistory.size() == 1, "both visits retain immutable history");

      rendered.draw(gb);
      BufferedImage after = rendered.frame();
      check(after.getRGB(104, 32) != beforePixel &&
        after.getRGB(104, 32) == StandIn.sheet().getRGB(TileSheet.sx(128), TileSheet.sy(128)),
        "received tile reaches production renderer");

      int old = gb.level.tile(28, 20), history = gb.boardHistory.size();
      // Unknown B and T must neither create a peer nor trigger replay.
      b.receive("D" + Net.sid(9999) + "Nunsolicited");
      b.receive("D" + Net.sid(9999) + "B" + new BoardChange(28, 20, 1, 1, new int[]{12}).encode());
      b.receive("D" + Net.sid(9999) + "T" + Net.time10(300));
      check(gb.level.tile(28, 20) == old && b.peers.size() == 1, "unknown sender rejected");
      b.receive(boardLine(a, payload.substring(0, payload.length() - 1)));
      b.receive(boardLine(a, payload + "x"));
      b.receive(boardLine(a, "" + Net.c(63) + Net.c(63) + Net.c(19) + payload.substring(3)));
      b.receive(boardLine(a, payload.substring(0, 3) + "\u001f" + payload.substring(4)));
      check(gb.level.tile(28, 20) == old && gb.boardHistory.size() == history &&
        wire(b).boards() == bSent, "malformed rectangles rejected atomically without echo/history");

      // The documented top-left quirk is deliberately not reproduced. A
      // uniform replacement must still detect another destination changing.
      int top = ga.level.tile(28, 20);
      check(ga.modifyBoard(28, 20, 2, 1, new int[]{top, top}), "per-cell detector retains real change");
      pump(20, a, b);
      int count = ga.boardHistory.size();
      check(!ga.modifyBoard(28, 20, 2, 1, new int[]{top, top}) && ga.boardHistory.size() == count,
        "unchanged duplicate is not a new history event");

      // P pushes ordinary state, never board history; T from a known peer is
      // the trigger, and delivery is to the whole party including old peers.
      int beforeP = wire(a).boards();
      a.receive("P" + b.myId);
      check(wire(a).boards() == beforeP, "P alone does not replay board");
      pump(20, a, b);
      Game gc = game();
      c = connect(gc, server.port()); c.loginTime = 300;
      int oldPeerBoards = wire(a).boards();
      paired(a, b, c);
      pump(30, a, b, c);
      check(gc.level.tile(28, 20) == 128 && gc.level.tile(29, 20) == 128 &&
        gc.level.tile(29, 22) == 773, "late peer receives ordered history after T");
      check(wire(a).boards() >= oldPeerBoards + ga.boardHistory.size(), "T replay publishes entire history");
      Net.Peer first = (Net.Peer) a.peers.get(b.myId), second = (Net.Peer) a.peers.get(c.myId);
      first.loginTime = 20; second.loginTime = 30;
      a.peerOrder.clear(); a.peerOrder.add(first); a.peerOrder.add(second);
      check(a.leaderCandidate().equals(second.id), "later older-than-local peer replaces earlier candidate");
      a.peerOrder.clear(); a.peerOrder.add(second); a.peerOrder.add(first);
      check(a.leaderCandidate().equals(first.id), "source comparison retains encounter-order effect");
      String originalId = a.myId;
      a.myId = "00000009";
      a.peerOrder.clear(); a.peerOrder.add(first);
      first.loginTime = -1;
      check(a.leaderCandidate().equals(a.myId), "unknown negative peer cannot replace positive local time");
      first.loginTime = 20; second.loginTime = -1;
      a.peerOrder.add(second);
      check(a.leaderCandidate().equals(first.id), "unknown negative peer cannot replace known older candidate");
      a.loginTime = -1;
      a.peerOrder.clear(); a.peerOrder.add(first);
      check(a.leaderCandidate().equals(a.myId), "nonnegative peer does not automatically replace negative local time");
      first.loginTime = -2;
      check(a.leaderCandidate().equals(first.id), "negative candidate permits lower-id negative peer");
      a.loginTime = 100; first.loginTime = 100; second.loginTime = 100;
      a.peerOrder.clear(); a.peerOrder.add(first); a.peerOrder.add(second);
      check(a.leaderCandidate().equals(first.id), "equal-local timestamps compare with retained candidate identity");
      a.peerOrder.clear(); a.peerOrder.add(second); a.peerOrder.add(first);
      check(a.leaderCandidate().equals(first.id), "equal-local lexical tie survives reverse encounter order");
      a.myId = originalId;
      first.loginTime = 200; second.loginTime = 300;
      a.peerOrder.clear(); a.peerOrder.add(first); a.peerOrder.add(second);
      int beforeTimestamp = wire(a).boards();
      b.relay.send("D" + Net.sid(b.myNum) + "T" + Net.time10(200));
      pump(25, a, b, c);
      check(wire(a).boards() >= beforeTimestamp + ga.boardHistory.size(), "existing-peer T replays to party");
      check(gb.level.tile(29, 20) == 128 && gc.level.tile(29, 20) == 128, "old and new peers retain latest overlapping value");

      long oldVisitTime = b.loginTime;
      check(!gb.enter("missing-generated.zelda", 0, 0) && gb.boardHistory.size() > 0,
        "failed load preserves current visit history");
      check(gb.enter("level1.zelda", 30, 29), "same filename reload succeeds");
      check(gb.boardHistory.isEmpty() && b.loginTime != oldVisitTime && gb.level.tile(28, 20) != 128,
        "successful reload clears history and renews timestamp before network replay");
      pump(35, a, b, c);
      check(gb.level.tile(29, 22) == 773, "same-room re-entry can recover current party history");
      check(gb.enter("level2.zelda", 1, 30), "different room load");
      pump(25, a, b, c);
      check(b.peers.isEmpty(), "rebuilt lobby actually isolates changed room");
      check(gb.enter("level1.zelda", 30, 29), "return load");
      paired(a, b, c);
      pump(25, a, b, c);
      check(gb.level.tile(29, 22) == 773, "returning peer receives remaining leader history");
    } finally {
      if (a != null) a.close();
      if (b != null) b.close();
      if (c != null) c.close();
      server.stop();
    }
  }
}
