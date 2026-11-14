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
 * Java 1.1 application: a "Zelda Start" window with "One-Player mode" and
 * "Multiplayer mode", a server address field, Play and Cancel; then the
 * game window, a 512x448 view that opens on the title screen, with a chat
 * field and an Options button (nickname, showing your own name, the sprite
 * colours) under it. Multiplayer goes through the GServ lobby on port 14801
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
  public static final String DEFAULT_SERVER = "127.0.0.1";

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

  int swallow = -1; // the key that left the title, until it is let go

  void key(KeyEvent e, boolean down) {
    int code = e.getKeyCode();
    synchronized (game) {
      if (game.title) {
        // any key leaves it, as in Zelda Online 1; a modifier alone does not
        if (down && code != KeyEvent.VK_SHIFT && code != KeyEvent.VK_CONTROL
            && code != KeyEvent.VK_ALT && code != KeyEvent.VK_META) {
          game.title = false;
          swallow = code;
        }
        return;
      }
      if (code == swallow) {
        if (!down) swallow = -1;
        return;
      }
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

  java.awt.image.BufferedImage titleImage;

  public void paint(Graphics g) {
    synchronized (game) {
      if (game.title) {
        if (titleImage == null) titleImage = renderer.title();
        g.drawImage(titleImage, 0, 0, null);
        return;
      }
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

  /**
   * The start window, "Zelda Start", 568x380 as measured (isolated lab,
   * 2026-11-13): a teal panel at (14, 14)-(171, 286) with two figures, the
   * title "Zelda online" in grey bold and four lines about the game, the
   * two modes (One-Player selected), the server address, a line at y 323,
   * then Play (100x28 at 341, 341) and Cancel (at 455, 341). The original
   * fills the address with 127.0.0.1; the rebuild keeps that loopback
   * default and starts in One-Player mode. The description is the
   * rebuild's own words.
   */
  static void startWindow(final Game game, final Renderer renderer, final String level) {
    final Frame f = new Frame("Zelda Start");
    f.setLayout(null);
    f.setResizable(false);
    f.setBackground(new java.awt.Color(192, 192, 192));
    Canvas art = new Canvas() {
      public void paint(Graphics g) {
        g.setColor(new java.awt.Color(0, 128, 128));
        g.fillRect(0, 0, getWidth(), getHeight());
        java.awt.image.BufferedImage fig = new java.awt.image.BufferedImage(32, 24, java.awt.image.BufferedImage.TYPE_INT_ARGB);
        Graphics fg = fig.getGraphics();
        renderer.drawFigure(fg, 0, 4, Game.DOWN, 0, false, false, game.colours);
        renderer.drawFigure(fg, 16, 4, Game.LEFT, 0, false, false, new int[] {4, 5, 6, 7});
        fg.dispose();
        g.drawImage(fig, (getWidth() - 96) / 2, getHeight() / 2 - 36, 96, 72, null);
      }
    };
    final Label status = new Label(" ");
    final TextField address = new TextField(DEFAULT_SERVER);
    java.awt.CheckboxGroup modes = new java.awt.CheckboxGroup();
    final Checkbox one = new Checkbox("One-Player mode (124k)", modes, true);
    final Checkbox multi = new Checkbox("Multiplayer mode (133k)", modes, false);
    Label title = new Label("Zelda online");
    title.setFont(new java.awt.Font("Dialog", java.awt.Font.BOLD, 18));
    title.setForeground(java.awt.Color.darkGray);
    String[] about = {
      "An adventure in a world of 8x8 tiles.",
      "Play alone, or meet other players",
      "on a server and walk the same levels.",
      "Choose a mode and press Play.",
    };
    Canvas line = new Canvas() {
      public void paint(Graphics g) {
        g.setColor(java.awt.Color.gray);
        g.drawLine(0, 0, getWidth(), 0);
        g.setColor(java.awt.Color.white);
        g.drawLine(0, 1, getWidth(), 1);
      }
    };
    Button play = new Button("Play");
    Button cancel = new Button("Cancel");
    Label ip = new Label("Server IP:");
    f.add(art); f.add(title);
    for (int i = 0; i < about.length; i++) f.add(new Label(about[i]));
    f.add(one); f.add(multi); f.add(ip); f.add(address); f.add(status);
    f.add(line); f.add(play); f.add(cancel);
    f.setVisible(false);
    f.addNotify();
    java.awt.Insets in = f.getInsets();
    f.setSize(568 + in.left + in.right, 380 + in.top + in.bottom);
    int ox = in.left, oy = in.top;
    art.setBounds(ox + 14, oy + 14, 171 - 14, 286 - 14);
    title.setBounds(ox + 186, oy + 14, 370, 30);
    for (int i = 0, k = 0; i < f.getComponentCount(); i++) {
      java.awt.Component c = f.getComponent(i);
      if (c instanceof Label && c != title && c != ip && c != status) {
        c.setBounds(ox + 186, oy + 52 + k * 18, 370, 18);
        k++;
      }
    }
    one.setBounds(ox + 186, oy + 140, 370, 22);
    multi.setBounds(ox + 186, oy + 164, 370, 22);
    ip.setBounds(ox + 186, oy + 200, 80, 22);
    address.setBounds(ox + 270, oy + 200, 280, 22);
    status.setBounds(ox + 186, oy + 260, 370, 22);
    line.setBounds(ox + 14, oy + 323, 568 - 28, 2);
    play.setBounds(ox + 341, oy + 341, 100, 28);
    cancel.setBounds(ox + 455, oy + 341, 100, 28);

    play.addActionListener(new ActionListener() {
      public void actionPerformed(ActionEvent e) {
        if (!game.start(level)) { status.setText(game.status); return; }
        if (multi.getState() && connect(game, address.getText().trim()) == null) {
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
    });
    cancel.addActionListener(new ActionListener() {
      public void actionPerformed(ActionEvent e) { System.exit(0); }
    });
    f.addWindowListener(new WindowAdapter() {
      public void windowClosing(WindowEvent e) { System.exit(0); }
    });
    f.setVisible(true);
  }

  /** The Options window: nickname, showing your own name, the colours. */
  static void optionsWindow(Frame owner, final Game game) {
    final java.awt.Dialog d = new java.awt.Dialog(owner, "Options", true);
    d.setLayout(new BorderLayout());
    Panel opts = new Panel(new GridLayout(0, 2, 6, 4));
    final TextField nickname = new TextField(game.nickname, 16);
    final Checkbox ownName = new Checkbox("Show your own name", game.showOwnName);
    final String[] parts = {"Cap", "Cap edge", "Belt", "Coat"};
    final Choice[] colour = new Choice[4];
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
    Button ok = new Button("OK");
    ok.addActionListener(new ActionListener() {
      public void actionPerformed(ActionEvent e) {
        synchronized (game) {
          game.nickname = nickname.getText().trim().length() > 0 ? nickname.getText().trim() : "unknown";
          game.showOwnName = ownName.getState();
          for (int i = 0; i < 4; i++) game.colours[i] = colour[i].getSelectedIndex();
        }
        d.dispose();
      }
    });
    d.addWindowListener(new WindowAdapter() {
      public void windowClosing(WindowEvent e) { d.dispose(); }
    });
    Panel south = new Panel();
    south.add(ok);
    d.add(opts, BorderLayout.CENTER);
    d.add(south, BorderLayout.SOUTH);
    d.pack();
    d.setVisible(true);
  }

  static void runWindow(final Game game, Renderer renderer) throws Exception {
    final Frame f = new Frame(TITLE);
    final ZeldaOnline2 c = new ZeldaOnline2(game, renderer);
    game.title = true;
    // under the 512x448 view: the chat field and the Options button (the
    // window is 512x482 inside, isolated lab 2026-11-13)
    final TextField chat = new TextField();
    Button options = new Button("Options");
    Panel bar = new Panel(new BorderLayout(4, 0));
    bar.add(chat, BorderLayout.CENTER);
    bar.add(options, BorderLayout.EAST);
    bar.setPreferredSize(new Dimension(Renderer.VIEW_W * Renderer.SCALE, 482 - Renderer.VIEW_H * Renderer.SCALE));
    chat.addActionListener(new ActionListener() {
      public void actionPerformed(ActionEvent e) {
        synchronized (game) { game.chat = chat.getText(); }
        chat.setText("");
        c.requestFocus();
      }
    });
    options.addActionListener(new ActionListener() {
      public void actionPerformed(ActionEvent e) {
        optionsWindow(f, game);
        c.requestFocus();
      }
    });
    f.setLayout(new BorderLayout());
    f.add(c, BorderLayout.CENTER);
    f.add(bar, BorderLayout.SOUTH);
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
