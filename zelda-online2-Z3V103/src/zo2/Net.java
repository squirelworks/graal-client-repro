package zo2;

import java.util.Enumeration;
import java.util.Hashtable;

/**
 * Multiplayer through the GServ lobby, as Zelda Online 2 used it
 * (graal_analysis client-internals/precursors-and-fan-builds.md, the
 * precursor runs, and protocol/relay-1998.md for the D payloads):
 *
 * - Every level is its own room: "Z" + the level file name without its
 *   extension + "1.6", e.g. Zlevel11.6. The client joins with the name "def"
 *   and sends its real nickname later inside D.
 * - On a level change it sends C and -, then joins the new room.
 * - It answers the first + with P for that player straight away. On P it
 *   pushes its whole state: login time, position, chat, nickname, colours
 *   and carried object.
 * - D lines are "D" + sender id (two base-128 characters) + type + payload.
 *   Numbers are one character each, value + 32; positions are half tiles.
 * - The level leader is the peer with the earliest login time (ties: lower
 *   id); it runs the baddies.
 */
public class Net {
  public static final int PORT = 14801;

  public static class Peer {
    public String id;
    public double x = -1, y = -1;
    public int dir = Game.DOWN, frame;
    public String nick = "", chat = "";
    public int[] colours = new int[0];
    public long loginTime = Long.MAX_VALUE;
    public boolean here = true; // false after an I (left the level)
  }

  Relay relay;
  Game game;
  public String myId = "";
  int myNum;
  public long loginTime;
  public Hashtable peers = new Hashtable();
  String room = "";
  String levelName = "";
  boolean askedParty;
  double sentX = -999, sentY = -999;
  int sentDir = -1, sentFrame = -1;
  String sentChat = "";
  String sentNickname, sentColours;
  int tickCount;

  public Net(Relay relay, Game game) {
    this.relay = relay;
    this.game = game;
    loginTime = System.currentTimeMillis();
  }

  public static String roomFor(String level) {
    int dot = level.lastIndexOf('.');
    String base = dot < 0 ? level : level.substring(0, dot);
    return "Z" + base + "1.6";
  }

  /** "0000nnnn" to the two-character id used inside D. */
  public static String sid(int n) {
    return "" + (char) (n / 128 + 32) + (char) (n % 128 + 32);
  }

  public static String idFromSid(String s) {
    int n = (s.charAt(0) - 32) * 128 + (s.charAt(1) - 32);
    String d = "000" + n;
    return "0000" + d.substring(d.length() - 4);
  }

  public static String time10(long t) {
    StringBuffer b = new StringBuffer();
    for (int i = 0; i < 10; i++) {
      b.append((char) (t % 128 + 32));
      t /= 128;
    }
    return b.toString();
  }

  public static long untime10(String s) {
    long t = 0;
    for (int i = Math.min(10, s.length()) - 1; i >= 0; i--) t = t * 128 + (s.charAt(i) - 32);
    return t;
  }

  static char c(int v) {
    return (char) (v + 32);
  }

  void d(char type, String payload) {
    if (myId.length() == 0) return;
    relay.send("D" + sid(myNum) + type + payload);
  }

  String position() {
    return "" + c((int) Math.round(game.x * 2)) + c((int) Math.round(game.y * 2)) + c(game.walkFrame * 4 + game.dir);
  }

  void pushState() {
    d('T', time10(loginTime));
    d('P', position());
    d('C', game.chat);
    pushAppearance(true);
    d('O', " ");
  }

  /** Options change the game state; the regular network tick publishes it. */
  void pushAppearance(boolean force) {
    if (myId.length() == 0) return;
    if (force || !game.nickname.equals(sentNickname)) {
      d('N', game.nickname);
      sentNickname = game.nickname;
    }
    StringBuffer s = new StringBuffer();
    s.append(c(game.colours.length));
    for (int i = 0; i < game.colours.length; i++) s.append(c(game.colours[i]));
    String colours = s.toString();
    if (force || !colours.equals(sentColours)) {
      d('S', colours);
      sentColours = colours;
    }
  }

  void join() {
    levelName = game.level.name;
    room = roomFor(levelName);
    peers.clear();
    askedParty = false;
    relay.send("N" + room + "#def");
  }

  /** Called once per game tick, after Game.tick(). */
  public void tick() {
    tickCount++;
    if (game.level != null && !game.level.name.equals(levelName)) {
      if (levelName.length() > 0) {
        relay.send("C");
        relay.send("-");
      }
      myId = "";
      join();
    }
    String l;
    while ((l = relay.poll()) != null) receive(l);

    // position every 2 ticks while it changes
    if (myId.length() > 0 && tickCount % 2 == 0) {
      if (game.x != sentX || game.y != sentY || game.dir != sentDir || game.walkFrame != sentFrame) {
        d('P', position());
        sentX = game.x; sentY = game.y; sentDir = game.dir; sentFrame = game.walkFrame;
      }
    }
    if (!game.chat.equals(sentChat)) {
      d('C', game.chat);
      sentChat = game.chat;
    }
    pushAppearance(false);
  }

  public void receive(String l) {
    if (l.length() == 0) return;
    char cmd = l.charAt(0);
    String arg = l.substring(1);
    switch (cmd) {
      case 'I':
        myId = arg.length() >= 8 ? arg.substring(0, 8) : arg;
        try { myNum = Integer.parseInt(myId.substring(4)); } catch (Exception e) { myNum = 0; }
        sentX = -999;
        sentNickname = null;
        sentColours = null;
        break;
      case '+':
        if (arg.length() >= 8) {
          String id = arg.substring(0, 8);
          if (!askedParty && !id.equals(myId)) {
            askedParty = true;
            relay.send("P" + id);
          }
        }
        break;
      case '-':
        peers.remove(arg);
        break;
      case 'P':
        peer(arg);
        pushState();
        break;
      case 'C':
        peers.remove(arg);
        break;
      case 'D':
        if (arg.length() >= 3) data(idFromSid(arg.substring(0, 2)), arg.charAt(2), arg.substring(3));
        break;
      default:
        break;
    }
  }

  Peer peer(String id) {
    Peer p = (Peer) peers.get(id);
    if (p == null) {
      p = new Peer();
      p.id = id;
      peers.put(id, p);
    }
    return p;
  }

  void data(String id, char type, String s) {
    if (id.equals(myId)) return;
    Peer p = peer(id);
    switch (type) {
      case 'P':
        if (s.length() >= 3) {
          p.x = (s.charAt(0) - 32) / 2.0;
          p.y = (s.charAt(1) - 32) / 2.0;
          int f = s.charAt(2) - 32;
          p.dir = f & 3;
          p.frame = f >> 2;
          p.here = true;
        }
        break;
      case 'C': p.chat = s; break;
      case 'N': p.nick = s; break;
      case 'T': p.loginTime = untime10(s); break;
      case 'I': p.here = false; break;
      case 'S':
        if (s.length() >= 1) {
          int n = Math.min(s.charAt(0) - 32, s.length() - 1);
          p.colours = new int[Math.max(0, n)];
          for (int i = 0; i < p.colours.length; i++) p.colours[i] = s.charAt(i + 1) - 32;
        }
        break;
      default:
        break; // B, M, H, E, O, W, A, D: later
    }
  }

  /** Whether this client is the level leader: earliest login time, ties to the lower id. */
  public boolean leader() {
    for (Enumeration e = peers.elements(); e.hasMoreElements();) {
      Peer p = (Peer) e.nextElement();
      if (p.loginTime < loginTime || p.loginTime == loginTime && p.id.compareTo(myId) < 0) return false;
    }
    return true;
  }

  public void close() {
    relay.send("C");
    relay.send("-");
    relay.close();
  }
}
