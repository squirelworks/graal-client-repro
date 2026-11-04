package javagraal;

import java.awt.BorderLayout;
import java.awt.Canvas;
import java.awt.Dimension;
import java.awt.Frame;
import java.awt.Graphics;
import java.awt.GraphicsEnvironment;
import java.awt.event.KeyAdapter;
import java.awt.event.KeyEvent;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;
import java.io.File;
import javax.imageio.ImageIO;

/**
 * Java Graal (July 2000), rebuilt. The original is a Java 1.1 applet,
 * 512x418, served from Cyberjoueur's site. It starts on level13.graal and
 * connects to the host it was loaded from on port 14802, with no start
 * window. This runs it in a window of the same size; the host it would have
 * been loaded from is --host (default listserver.graal.in). If the relay
 * cannot be reached it plays alone.
 *
 *   java -jar JavaGraal.jar                         window, relay at the default host
 *   java -jar JavaGraal.jar --host HOST[:PORT]
 *   java -jar JavaGraal.jar --offline
 *   java -jar JavaGraal.jar --keys rrdd.. --dump f.png   headless
 *
 * Arrow keys walk, Enter opens the chat line; "nickname: NAME" in chat sets
 * the nickname.
 */
public class JavaGraal extends Canvas {
  static final String TITLE = "Graal";
  public static final String DEFAULT_HOST = "listserver.graal.in";

  Game game;
  Renderer renderer;
  StringBuffer typing;

  JavaGraal(Game game, Renderer renderer) {
    this.game = game;
    this.renderer = renderer;
    setPreferredSize(new Dimension(Renderer.VIEW_W, Renderer.VIEW_H));
    setFocusable(true);
    setFocusTraversalKeysEnabled(false);
    addKeyListener(new KeyAdapter() {
      public void keyPressed(KeyEvent e) { key(e, true); }
      public void keyReleased(KeyEvent e) { key(e, false); }
      public void keyTyped(KeyEvent e) { typed(e.getKeyChar()); }
    });
  }

  void typed(char c) {
    if (typing == null || c < 32 || c == 127) return;
    if (typing.length() < 60) typing.append(c);
  }

  void key(KeyEvent e, boolean down) {
    int code = e.getKeyCode();
    synchronized (game) {
      if (typing != null) {
        if (!down) return;
        if (code == KeyEvent.VK_ENTER) { game.chat = typing.toString(); typing = null; }
        else if (code == KeyEvent.VK_ESCAPE) typing = null;
        else if (code == KeyEvent.VK_BACK_SPACE && typing.length() > 0) typing.setLength(typing.length() - 1);
        game.typing = typing == null ? null : typing.toString();
        return;
      }
      int bit = -1;
      switch (code) {
        case KeyEvent.VK_UP: bit = Game.UP; break;
        case KeyEvent.VK_LEFT: bit = Game.LEFT; break;
        case KeyEvent.VK_DOWN: bit = Game.DOWN; break;
        case KeyEvent.VK_RIGHT: bit = Game.RIGHT; break;
        case KeyEvent.VK_SPACE: case KeyEvent.VK_A:
          game.action = down;
          return;
        case KeyEvent.VK_ENTER:
          if (down) { typing = new StringBuffer(); game.typing = ""; game.keys = 0; }
          return;
        default: return;
      }
      if (down) game.keys |= 1 << bit; else game.keys &= ~(1 << bit);
    }
  }

  public void update(Graphics g) {
    paint(g);
  }

  public void paint(Graphics g) {
    synchronized (game) {
      renderer.draw(game);
    }
    g.drawImage(renderer.frame(), 0, 0, null);
  }

  static File programDir() {
    try {
      File f = new File(JavaGraal.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      return f.isFile() ? f.getParentFile() : f;
    } catch (Exception e) {
      return new File(".");
    }
  }

  static void usage() {
    System.out.println("JavaGraal [--host HOST[:PORT] | --offline] [--nick NAME] [--data DIR]");
    System.out.println("          [--level NAME] [--keys KEYS] [--dump FILE.png] [--headless]");
  }

  /** Connects to the relay; null (and a status) when it fails. */
  public static Net connect(Game game, String address) {
    String host = address;
    int port = Net.PORT;
    int colon = address.lastIndexOf(':');
    if (colon > 0) {
      try {
        port = Integer.parseInt(address.substring(colon + 1));
        host = address.substring(0, colon);
      } catch (NumberFormatException e) {
        // a bare host
      }
    }
    try {
      Net n = new Net(new Relay(host, port, 5000), game);
      game.net = n;
      return n;
    } catch (Exception e) {
      game.status = "no relay at " + host + ":" + port + ", playing alone";
      return null;
    }
  }

  public static void main(String[] args) throws Exception {
    File data = null;
    String level = null, keys = null, dump = null, host = null, nick = null;
    boolean headless = false, offline = false;
    for (int i = 0; i < args.length; i++) {
      String a = args[i];
      if (a.equals("--data") && i + 1 < args.length) data = new File(args[++i]);
      else if (a.equals("--level") && i + 1 < args.length) level = args[++i];
      else if (a.equals("--keys") && i + 1 < args.length) keys = args[++i];
      else if (a.equals("--dump") && i + 1 < args.length) dump = args[++i];
      else if (a.equals("--host") && i + 1 < args.length) host = args[++i];
      else if (a.equals("--nick") && i + 1 < args.length) nick = args[++i];
      else if (a.equals("--offline")) offline = true;
      else if (a.equals("--headless")) headless = true;
      else if (a.equals("--help") || a.equals("-h")) { usage(); return; }
      else { usage(); System.exit(2); }
    }
    Assets assets = new Assets(programDir(), data);
    Game game = new Game(assets);
    if (nick != null) game.nickname = nick;
    Renderer renderer = new Renderer(assets.tileSheet(), assets);
    if (!game.start(level)) { System.err.println(game.status); System.exit(1); }
    boolean scripted = keys != null || dump != null || headless || GraphicsEnvironment.isHeadless();
    // scripted runs stay offline unless a host is named
    if (!offline && (host != null || !scripted)) {
      if (connect(game, host != null ? host : DEFAULT_HOST) == null) System.err.println(game.status);
    }
    if (scripted) runScripted(game, renderer, keys == null ? "" : keys, dump);
    else runWindow(game, renderer);
  }

  static void runScripted(Game game, Renderer renderer, String keys, String dump) throws Exception {
    for (int i = 0; i < keys.length(); i++) {
      char c = keys.charAt(i);
      game.keys = c == 'u' ? 1 << Game.UP : c == 'l' ? 1 << Game.LEFT : c == 'd' ? 1 << Game.DOWN : c == 'r' ? 1 << Game.RIGHT : 0;
      game.action = c == 'a';
      game.tick();
      if (game.net != null) { game.net.tick(); Thread.sleep(Game.TICK_MS); }
    }
    System.out.println("level " + game.level.name + " x " + game.x + " y " + game.y
        + (game.signText != null ? " sign" : "") + (game.assets.usingStandIn ? " (stand-in graphics)" : ""));
    if (dump != null) {
      renderer.draw(game);
      ImageIO.write(renderer.frame(), "png", new File(dump));
    }
    if (game.net != null) game.net.close();
  }

  static void runWindow(final Game game, Renderer renderer) throws Exception {
    final Frame f = new Frame(TITLE);
    final JavaGraal c = new JavaGraal(game, renderer);
    f.setLayout(new BorderLayout());
    f.add(c, BorderLayout.CENTER);
    f.pack();
    f.setResizable(false);
    f.addWindowListener(new WindowAdapter() {
      public void windowClosing(WindowEvent e) {
        if (game.net != null) game.net.close();
        System.exit(0);
      }
    });
    f.setVisible(true);
    c.requestFocus();
    long next = System.currentTimeMillis();
    while (true) {
      synchronized (game) {
        game.tick();
        if (game.net != null) game.net.tick();
      }
      c.repaint();
      next += Game.TICK_MS;
      long wait = next - System.currentTimeMillis();
      if (wait > 0) Thread.sleep(wait); else next = System.currentTimeMillis();
    }
  }
}
