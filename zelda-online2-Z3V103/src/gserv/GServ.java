package gserv;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Enumeration;
import java.util.Vector;

/**
 * The lobby that Zelda Online 2 shipped with ("GServ Standalone"), rebuilt.
 * It knows nothing about the game: it groups connections into named games,
 * gives each an 8-character id ("0000" plus a 4-digit counter that wraps at
 * 9999), links players into parties and relays D lines inside a party.
 *
 * Lines, each ending in '\n' (graal_analysis protocol/relay-1998.md and
 * client-internals/precursors-and-fan-builds.md):
 *
 *   client -> server                     server -> client
 *   N<game>#<name>  join as a player     I<id8>        your id
 *   O<game>#<name>  join as an observer  +<id8><name>  a player is available
 *   S<name>         super user           -<id8>        that player left
 *   +  available again                   P<id8>        now in your party
 *   -  not available                     C<id8>        left your party
 *   P<id8>  join that player's party     D<data>       relayed, unchanged
 *   C       leave the party
 *   V<id8>  watch a player's party
 *   D<data> relay to the party
 *   H<score> high score (ignored)
 *
 *   java -jar GServ.jar [port]     (default 14801)
 */
public class GServ {
  public static final int PORT = 14801;

  ServerSocket server;
  Vector players = new Vector();
  int counter;
  volatile boolean running = true;

  /** One connection. Its party is a shared Vector of the linked players. */
  class Player extends Thread {
    Socket socket;
    OutputStream out;
    String id = "", name = "", game = "";
    boolean joined, available, observer, superUser;
    Vector party; // includes this player; null when not in one
    Vector watchers = new Vector();

    Player(Socket s) throws IOException {
      socket = s;
      out = s.getOutputStream();
      setDaemon(true);
    }

    void send(String line) {
      try {
        synchronized (this) {
          byte[] b = (line + "\n").getBytes("ISO-8859-1");
          out.write(b);
          out.flush();
        }
      } catch (IOException e) {
        close();
      }
    }

    public void run() {
      try {
        InputStream in = socket.getInputStream();
        StringBuffer line = new StringBuffer();
        int c;
        while (running && (c = in.read()) >= 0) {
          if (c == '\n') {
            String l = line.toString();
            line.setLength(0);
            if (l.endsWith("\r")) l = l.substring(0, l.length() - 1);
            if (l.length() > 0) handle(this, l);
          } else if (line.length() < 4096) {
            line.append((char) c);
          }
        }
      } catch (IOException e) {
        // closed
      }
      close();
    }

    void close() {
      synchronized (GServ.this) {
        if (!players.contains(this)) return;
        leaveParty(this);
        withdraw(this);
        players.removeElement(this);
      }
      try { socket.close(); } catch (IOException e) { }
    }
  }

  public GServ(int port) throws IOException {
    server = new ServerSocket(port, 50, InetAddress.getByName("0.0.0.0"));
  }

  public GServ(int port, InetAddress bind) throws IOException {
    server = new ServerSocket(port, 50, bind);
  }

  public int port() {
    return server.getLocalPort();
  }

  public void serve() {
    while (running) {
      try {
        Socket s = server.accept();
        s.setTcpNoDelay(true);
        Player p = new Player(s);
        synchronized (this) { players.addElement(p); }
        p.start();
      } catch (IOException e) {
        if (!running) return;
      }
    }
  }

  public void start() {
    Thread t = new Thread() {
      public void run() { serve(); }
    };
    t.setDaemon(true);
    t.start();
  }

  public void stop() {
    running = false;
    try { server.close(); } catch (IOException e) { }
    synchronized (this) {
      for (int i = players.size() - 1; i >= 0; i--) {
        try { ((Player) players.elementAt(i)).socket.close(); } catch (IOException e) { }
      }
    }
  }

  String nextId() {
    counter = counter % 9999 + 1;
    String n = "000" + counter;
    return "0000" + n.substring(n.length() - 4);
  }

  Player byId(String id) {
    for (int i = 0; i < players.size(); i++) {
      Player p = (Player) players.elementAt(i);
      if (p.joined && p.id.equals(id)) return p;
    }
    return null;
  }

  /** Whether 'to' should see 'p' in its list. */
  boolean sees(Player to, Player p) {
    if (to == p || !p.joined || p.observer || !p.available) return false;
    if (to.superUser) return true;
    if (!to.game.equals(p.game)) return false;
    if (to.observer) return p.party != null;
    return true;
  }

  String listName(Player to, Player p) {
    return to.superUser ? p.name + " (" + p.game + ")" : p.name;
  }

  void announce(Player p) {
    for (int i = 0; i < players.size(); i++) {
      Player o = (Player) players.elementAt(i);
      if (o.joined && sees(o, p)) o.send("+" + p.id + listName(o, p));
    }
  }

  void withdraw(Player p) {
    if (!p.joined || !p.available) return;
    for (int i = 0; i < players.size(); i++) {
      Player o = (Player) players.elementAt(i);
      if (o.joined && sees(o, p)) o.send("-" + p.id);
    }
    p.available = false;
  }

  void leaveParty(Player p) {
    if (p.party == null) return;
    p.party.removeElement(p);
    for (Enumeration e = p.party.elements(); e.hasMoreElements();)
      ((Player) e.nextElement()).send("C" + p.id);
    p.party = null;
  }

  synchronized void handle(Player p, String l) {
    char cmd = l.charAt(0);
    String arg = l.substring(1);
    switch (cmd) {
      case 'N':
      case 'O':
      case 'S': {
        if (p.joined) return;
        int h = arg.indexOf('#');
        p.observer = cmd == 'O';
        p.superUser = cmd == 'S';
        if (cmd == 'S') {
          p.name = arg;
        } else {
          p.game = h < 0 ? arg : arg.substring(0, h);
          p.name = h < 0 ? "" : arg.substring(h + 1);
        }
        p.id = nextId();
        p.joined = true;
        p.available = !p.observer && !p.superUser;
        p.send("I" + p.id);
        for (int i = 0; i < players.size(); i++) {
          Player o = (Player) players.elementAt(i);
          if (sees(p, o)) p.send("+" + o.id + listName(p, o));
        }
        if (p.available) announce(p);
        break;
      }
      case '+':
        if (p.joined && !p.available && !p.observer && !p.superUser) {
          p.available = true;
          announce(p);
        }
        break;
      case '-':
        withdraw(p);
        break;
      case 'P': {
        Player o = byId(arg);
        if (o == null || o == p || !p.joined) return;
        if (p.party != null && p.party == o.party) return;
        leaveParty(p);
        if (o.party == null) {
          o.party = new Vector();
          o.party.addElement(o);
        }
        for (Enumeration e = o.party.elements(); e.hasMoreElements();) {
          Player m = (Player) e.nextElement();
          m.send("P" + p.id);
          p.send("P" + m.id);
        }
        o.party.addElement(p);
        p.party = o.party;
        break;
      }
      case 'C':
        leaveParty(p);
        break;
      case 'V': {
        Player o = byId(arg);
        if (o != null && !o.watchers.contains(p)) o.watchers.addElement(p);
        break;
      }
      case 'D': {
        String line = "D" + arg;
        if (p.party != null) {
          for (Enumeration e = p.party.elements(); e.hasMoreElements();) {
            Player m = (Player) e.nextElement();
            if (m != p) m.send(line);
            for (Enumeration w = m.watchers.elements(); w.hasMoreElements();)
              ((Player) w.nextElement()).send(line);
          }
        }
        break;
      }
      default:
        break; // H and anything else: ignored
    }
  }

  public static void main(String[] args) throws Exception {
    int port = args.length > 0 ? Integer.parseInt(args[0]) : PORT;
    GServ g = new GServ(port);
    System.out.println("GServ listening on port " + g.port());
    g.serve();
  }
}
