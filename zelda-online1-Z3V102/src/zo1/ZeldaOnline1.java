package zo1;

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
 * Zelda Online 1 (May 1998), rebuilt. The original was a single-player Java
 * applet shown at scale 2 in a 512x448 box, starting on level1.zelda. This
 * runs it in a window of the same size, or headless for tests.
 *
 *   java -jar ZeldaOnline1.jar                     window
 *   java -jar ZeldaOnline1.jar --data DIR          files from another folder
 *   java -jar ZeldaOnline1.jar --level NAME        another start level
 *   java -jar ZeldaOnline1.jar --keys rrrr..uu --dump out.png
 *                                                  headless: one key per tick
 *                                                  (u l d r, a = read, . = none)
 */
public class ZeldaOnline1 extends Canvas {
  static final String TITLE = "Zelda Online";

  Game game;
  Renderer renderer;
  java.awt.image.BufferedImage titleImage;

  ZeldaOnline1(Game game, Renderer renderer) {
    this.game = game;
    this.renderer = renderer;
    setPreferredSize(new Dimension(Renderer.VIEW_W * Renderer.SCALE, Renderer.VIEW_H * Renderer.SCALE));
    setFocusable(true);
    addKeyListener(new KeyAdapter() {
      public void keyPressed(KeyEvent e) { key(e.getKeyCode(), true); }
      public void keyReleased(KeyEvent e) { key(e.getKeyCode(), false); }
    });
  }

  int swallow = -1; // the key that left the title, until it is let go

  void key(int code, boolean down) {
    synchronized (game) {
      if (game.title) {
        // any key leaves it (Enter, Up, 'a' and Space were tried); a click
        // does not. A modifier alone is not a key here.
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
    }
    int bit = -1;
    switch (code) {
      case KeyEvent.VK_UP: bit = Game.UP; break;
      case KeyEvent.VK_LEFT: bit = Game.LEFT; break;
      case KeyEvent.VK_DOWN: bit = Game.DOWN; break;
      case KeyEvent.VK_RIGHT: bit = Game.RIGHT; break;
      case KeyEvent.VK_SPACE: case KeyEvent.VK_ENTER: case KeyEvent.VK_A:
        game.action = down;
        return;
      default: return;
    }
    synchronized (game) {
      if (down) game.keys |= 1 << bit; else game.keys &= ~(1 << bit);
    }
  }

  public void update(Graphics g) {
    paint(g);
  }

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
      File f = new File(ZeldaOnline1.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      return f.isFile() ? f.getParentFile() : f;
    } catch (Exception e) {
      return new File(".");
    }
  }

  static void usage() {
    System.out.println("ZeldaOnline1 [--data DIR] [--level NAME] [--keys KEYS] [--dump FILE.png] [--headless] [--title]");
  }

  public static void main(String[] args) throws Exception {
    File data = null;
    String level = null, keys = null, dump = null;
    boolean headless = false, titleArg = false;
    for (int i = 0; i < args.length; i++) {
      String a = args[i];
      if (a.equals("--data") && i + 1 < args.length) data = new File(args[++i]);
      else if (a.equals("--level") && i + 1 < args.length) level = args[++i];
      else if (a.equals("--keys") && i + 1 < args.length) keys = args[++i];
      else if (a.equals("--dump") && i + 1 < args.length) dump = args[++i];
      else if (a.equals("--headless")) headless = true;
      else if (a.equals("--title")) titleArg = true;
      else if (a.equals("--help") || a.equals("-h")) { usage(); return; }
      else { usage(); System.exit(2); }
    }
    Assets assets = new Assets(programDir(), data);
    Game game = new Game(assets);
    Renderer renderer = new Renderer(assets.tileSheet());
    if (!game.start(level)) {
      System.err.println(game.status);
      System.exit(1);
    }
    boolean scripted = keys != null || dump != null || headless || GraphicsEnvironment.isHeadless();
    // the window opens on the title screen; a scripted run skips it unless
    // --title asks for it (then its first key leaves it)
    game.title = !scripted || titleArg;
    if (scripted) {
      runScripted(game, renderer, keys == null ? "" : keys, dump);
      return;
    }
    runWindow(game, renderer);
  }

  /** One key letter per tick. Prints where the player ended up. */
  static void runScripted(Game game, Renderer renderer, String keys, String dump) throws Exception {
    for (int i = 0; i < keys.length(); i++) {
      char c = keys.charAt(i);
      if (game.title) { game.title = false; continue; }
      game.keys = c == 'u' ? 1 << Game.UP : c == 'l' ? 1 << Game.LEFT : c == 'd' ? 1 << Game.DOWN : c == 'r' ? 1 << Game.RIGHT : 0;
      game.action = c == 'a';
      game.tick();
    }
    System.out.println("level " + game.level.name + " x " + game.x + " y " + game.y
        + (game.signText != null ? " sign" : "") + (game.assets.usingStandIn ? " (stand-in graphics)" : ""));
    if (dump != null) {
      if (game.title) {
        ImageIO.write(renderer.title(), "png", new File(dump));
        return;
      }
      renderer.draw(game);
      ImageIO.write(renderer.frame(), "png", new File(dump));
    }
  }

  static void runWindow(final Game game, Renderer renderer) throws Exception {
    final Frame f = new Frame(TITLE);
    final ZeldaOnline1 c = new ZeldaOnline1(game, renderer);
    f.add(c);
    f.pack();
    f.setResizable(false);
    f.addWindowListener(new WindowAdapter() {
      public void windowClosing(WindowEvent e) { System.exit(0); }
    });
    f.setVisible(true);
    c.requestFocus();
    long next = System.currentTimeMillis();
    while (true) {
      synchronized (game) {
        game.tick();
      }
      c.repaint();
      next += Game.TICK_MS;
      long wait = next - System.currentTimeMillis();
      if (wait > 0) Thread.sleep(wait); else next = System.currentTimeMillis();
    }
  }
}
