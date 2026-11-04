package zo2;

import java.awt.BorderLayout;
import java.awt.Button;
import java.awt.Canvas;
import java.awt.Checkbox;
import java.awt.Choice;
import java.awt.Dimension;
import java.awt.Frame;
import java.awt.Graphics;
import java.awt.GraphicsEnvironment;
import java.awt.GridLayout;
import java.awt.Label;
import java.awt.Panel;
import java.awt.TextField;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.KeyAdapter;
import java.awt.event.KeyEvent;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;
import java.io.File;
import javax.imageio.ImageIO;

/**
 * Zelda Online 2 "local version" (July 1998), rebuilt. The original is a
 * Java 1.1 application: a start window with "One-Player mode" and
 * "Multiplayer mode", a server address field and the player's options
 * (nickname, showing your own name, the sprite colours), then the game in a
 * 512x448 view. Multiplayer goes through the GServ lobby on port 14801
 * (see Net and gserv.GServ).
 *
 *   java -jar ZeldaOnline2.jar                       start window
 *   java -jar ZeldaOnline2.jar --one-player          straight into the game
 *   java -jar ZeldaOnline2.jar --server HOST[:PORT] --nick NAME
 *   java -jar ZeldaOnline2.jar --keys rrdd.. --dump f.png   headless
 */
public class ZeldaOnline2 extends Canvas {
  static final String TITLE = "Zelda Online";
  /** The address field is pre-filled with this, never with a local address. */
  public static final String DEFAULT_SERVER = "listserver.graal.in";

  Game game;
  Renderer renderer;
  StringBuffer typing; // the chat line being typed, or null

  ZeldaOnline2(Game game, Renderer renderer) {
    this.game = game;
    this.renderer = renderer;
    setPreferredSize(new Dimension(Renderer.VIEW_W * Renderer.SCALE, Renderer.VIEW_H * Renderer.SCALE));
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
          if (down && game.net != null) { typing = new StringBuffer(); game.typing = ""; game.keys = 0; }
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
    g.drawImage(renderer.frame(), 0, 0, Renderer.VIEW_W * Renderer.SCALE, Renderer.VIEW_H * Renderer.SCALE, null);
  }

  static File programDir() {
    try {
      File f = new File(ZeldaOnline2.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      return f.isFile() ? f.getParentFile() : f;
    } catch (Exception e) {
      return new File(".");
    }
  }

  static void usage() {
    System.out.println("ZeldaOnline2 [--one-player | --server HOST[:PORT]] [--nick NAME] [--data DIR]");
    System.out.println("             [--level NAME] [--keys KEYS] [--dump FILE.png] [--headless]");
  }

  /** Connects a game to a GServ lobby; null (and a status) when it fails. */
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
      game.status = "cannot connect to " + host + ":" + port + ": " + e.getMessage();
      return null;
    }
  }

  public static void main(String[] args) throws Exception {
    File data = null;
    String level = null, keys = null, dump = null, server = null, nick = null;
    boolean headless = false, onePlayer = false;
    for (int i = 0; i < args.length; i++) {
      String a = args[i];
      if (a.equals("--data") && i + 1 < args.length) data = new File(args[++i]);
      else if (a.equals("--level") && i + 1 < args.length) level = args[++i];
      else if (a.equals("--keys") && i + 1 < args.length) keys = args[++i];
      else if (a.equals("--dump") && i + 1 < args.length) dump = args[++i];
      else if (a.equals("--server") && i + 1 < args.length) server = args[++i];
      else if (a.equals("--nick") && i + 1 < args.length) nick = args[++i];
      else if (a.equals("--one-player")) onePlayer = true;
      else if (a.equals("--headless")) headless = true;
      else if (a.equals("--help") || a.equals("-h")) { usage(); return; }
      else { usage(); System.exit(2); }
    }
    final Assets assets = new Assets(programDir(), data);
    final Game game = new Game(assets);
    if (nick != null) game.nickname = nick;
    final Renderer renderer = new Renderer(assets.tileSheet());
    boolean scripted = keys != null || dump != null || headless || GraphicsEnvironment.isHeadless();
    if (scripted || onePlayer || server != null) {
      if (!game.start(level)) { System.err.println(game.status); System.exit(1); }
      if (server != null && connect(game, server) == null) { System.err.println(game.status); System.exit(1); }
      if (scripted) runScripted(game, renderer, keys == null ? "" : keys, dump);
      else runWindow(game, renderer);
      return;
    }
    startWindow(game, renderer, level);
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

  /** The start window: mode buttons, server address and the options. */
  static void startWindow(final Game game, final Renderer renderer, final String level) {
    final Frame f = new Frame(TITLE);
    f.setLayout(new BorderLayout());
    Panel opts = new Panel(new GridLayout(0, 2, 6, 4));
    final TextField address = new TextField(DEFAULT_SERVER, 24);
    final TextField nickname = new TextField(game.nickname, 16);
    final Checkbox ownName = new Checkbox("Show your own name");
    final String[] parts = {"Cap", "Cap edge", "Belt", "Coat"};
    final Choice[] colour = new Choice[4];
    opts.add(new Label("Server address:"));
    opts.add(address);
    opts.add(new Label("Nickname:"));
    opts.add(nickname);
    opts.add(new Label(""));
    opts.add(ownName);
    for (int i = 0; i < 4; i++) {
      colour[i] = new Choice();
      for (int k = 0; k < Colours.NAMES.length; k++) colour[i].add(Colours.NAMES[k]);
      colour[i].select(game.colours[i]);
      opts.add(new Label(parts[i] + " colour:"));
      opts.add(colour[i]);
    }
    final Label status = new Label(" ");
    Panel buttons = new Panel(new GridLayout(1, 2, 8, 0));
    Button one = new Button("One-Player mode");
    Button multi = new Button("Multiplayer mode");
    buttons.add(one);
    buttons.add(multi);
    Panel south = new Panel(new BorderLayout());
    south.add(buttons, BorderLayout.CENTER);
    south.add(status, BorderLayout.SOUTH);
    f.add(new Label("Zelda Online", Label.CENTER), BorderLayout.NORTH);
    f.add(opts, BorderLayout.CENTER);
    f.add(south, BorderLayout.SOUTH);

    class Go implements ActionListener {
      boolean multiplayer;
      Go(boolean m) { multiplayer = m; }
      public void actionPerformed(ActionEvent e) {
        game.nickname = nickname.getText().trim().length() > 0 ? nickname.getText().trim() : "unknown";
        game.showOwnName = ownName.getState();
        for (int i = 0; i < 4; i++) game.colours[i] = colour[i].getSelectedIndex();
        if (!game.start(level)) { status.setText(game.status); return; }
        if (multiplayer && connect(game, address.getText().trim()) == null) {
          status.setText(game.status);
          return;
        }
        f.dispose();
        new Thread() {
          public void run() {
            try { runWindow(game, renderer); } catch (Exception ex) { ex.printStackTrace(); System.exit(1); }
          }
        }.start();
      }
    }
    one.addActionListener(new Go(false));
    multi.addActionListener(new Go(true));
    f.addWindowListener(new WindowAdapter() {
      public void windowClosing(WindowEvent e) { System.exit(0); }
    });
    f.pack();
    f.setVisible(true);
  }

  static void runWindow(final Game game, Renderer renderer) throws Exception {
    final Frame f = new Frame(TITLE);
    final ZeldaOnline2 c = new ZeldaOnline2(game, renderer);
    f.add(c);
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
