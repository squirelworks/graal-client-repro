package zo1;

import java.awt.Color;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.image.BufferedImage;

/**
 * Draws one frame. The applet showed a 256x224 view of the board at scale 2
 * in a 512x448 box; the view follows the player and stops at the board
 * edges. The player is drawn with the rebuild's own stand-in figure.
 */
public class Renderer {
  public static final int VIEW_W = 256, VIEW_H = 224, SCALE = 2;

  BufferedImage sheet;
  BufferedImage frame = new BufferedImage(VIEW_W, VIEW_H, BufferedImage.TYPE_INT_RGB);

  public Renderer(BufferedImage sheet) {
    this.sheet = sheet;
  }

  public BufferedImage frame() {
    return frame;
  }

  public void draw(Game g) {
    Graphics gr = frame.getGraphics();
    int px = (int) Math.round(g.x * 8), py = (int) Math.round(g.y * 8);
    int camX = clamp(px + 8 - VIEW_W / 2, 0, 64 * 8 - VIEW_W);
    int camY = clamp(py + 8 - VIEW_H / 2, 0, 64 * 8 - VIEW_H);
    gr.setColor(Color.black);
    gr.fillRect(0, 0, VIEW_W, VIEW_H);
    int tx0 = camX / 8, ty0 = camY / 8;
    for (int ty = ty0; ty <= ty0 + VIEW_H / 8 + 1 && ty < 64; ty++) {
      for (int tx = tx0; tx <= tx0 + VIEW_W / 8 + 1 && tx < 64; tx++) {
        int t = g.level.tile(tx, ty);
        int dx = tx * 8 - camX, dy = ty * 8 - camY;
        int sx = TileSheet.sx(t), sy = TileSheet.sy(t);
        gr.drawImage(sheet, dx, dy, dx + 8, dy + 8, sx, sy, sx + 8, sy + 8, null);
      }
    }
    drawPlayer(gr, g, px - camX, py - camY);
    drawHud(gr, g);
    if (g.signText != null) drawSign(gr, g.signText);
    gr.dispose();
  }

  /**
   * The HUD, unscaled, where the original puts it (isolated lab, 2026-11-13):
   * its picture at (20, 12), the 8x8 magic fill at (24, 47), the counters
   * "000 / 00 / 05" from x 65, 97 and 121 on rows 24-29, and the hearts
   * at x 162, 170 and 178. The picture is the original's and is not here:
   * the rebuild draws plain stand-ins in the same places.
   */
  void drawHud(Graphics gr, Game g) {
    gr.setColor(new Color(0, 0, 0, 90));
    gr.fillRect(20, 12, 8 + 4, 44);
    gr.setColor(new Color(40, 180, 60));
    gr.fillRect(24, 47, 8, 8);
    gr.setFont(new Font("Monospaced", Font.BOLD, 8));
    drawCounter(gr, pad(g.rupees, 3), 65);
    drawCounter(gr, pad(g.bombs, 2), 97);
    drawCounter(gr, pad(g.arrows, 2), 121);
    for (int i = 0; i < g.hearts && i < 3; i++) {
      int hx = 162 + i * 8;
      gr.setColor(new Color(220, 30, 40));
      gr.fillRect(hx, 24, 3, 3);
      gr.fillRect(hx + 4, 24, 3, 3);
      gr.fillRect(hx + 1, 26, 5, 2);
      gr.fillRect(hx + 2, 28, 3, 1);
    }
  }

  static String pad(int v, int n) {
    String t = Integer.toString(Math.max(0, v));
    while (t.length() < n) t = "0" + t;
    return t;
  }

  void drawCounter(Graphics gr, String text, int x) {
    gr.setColor(Color.black);
    gr.drawString(text, x + 1, 30);
    gr.setColor(Color.white);
    gr.drawString(text, x, 29);
  }

  /**
   * The title screen at the window's scale (512x448): black, the logo
   * drawn at scale 2 from (100, 76), and "Press any key to start!" from
   * x 121 on rows 370-382 (isolated lab, 2026-11-13). The logo is the
   * original's picture and is not here: an outline and the name stand in.
   */
  public BufferedImage title() {
    BufferedImage t = new BufferedImage(VIEW_W * SCALE, VIEW_H * SCALE, BufferedImage.TYPE_INT_RGB);
    Graphics gr = t.getGraphics();
    gr.setColor(Color.black);
    gr.fillRect(0, 0, t.getWidth(), t.getHeight());
    gr.setColor(new Color(90, 90, 90));
    gr.drawRect(100, 76, 312 - 1, 200 - 1);
    gr.setColor(Color.white);
    gr.setFont(new Font("Serif", Font.BOLD, 40));
    FontMetrics fm = gr.getFontMetrics();
    String name = "Zelda Online";
    gr.drawString(name, 100 + (312 - fm.stringWidth(name)) / 2, 76 + 100 + fm.getAscent() / 3);
    gr.setFont(new Font("Dialog", Font.BOLD, 16));
    gr.drawString("Press any key to start!", 121, 382);
    gr.dispose();
    return t;
  }

  static int clamp(int v, int lo, int hi) {
    return v < lo ? lo : v > hi ? hi : v;
  }

  void drawPlayer(Graphics gr, Game g, int x, int y) {
    int bob = g.moving && (g.walkFrame & 1) == 1 ? 1 : 0;
    // shadow, body, head, cap
    gr.setColor(new Color(0, 0, 0, 80));
    gr.fillOval(x + 2, y + 13, 12, 4);
    gr.setColor(new Color(40, 140, 60));
    gr.fillRect(x + 3, y + 6 + bob, 10, 8);
    gr.setColor(new Color(110, 70, 30));
    gr.fillRect(x + 3, y + 10 + bob, 10, 1);
    gr.setColor(new Color(250, 200, 150));
    gr.fillOval(x + 3, y - 1 + bob, 10, 9);
    gr.setColor(new Color(30, 110, 50));
    gr.fillRect(x + 3, y - 1 + bob, 10, 3);
    // a mark on the facing side
    gr.setColor(Color.black);
    switch (g.dir) {
      case Game.UP: break;
      case Game.DOWN: gr.fillRect(x + 5, y + 4 + bob, 2, 2); gr.fillRect(x + 9, y + 4 + bob, 2, 2); break;
      case Game.LEFT: gr.fillRect(x + 4, y + 4 + bob, 2, 2); break;
      case Game.RIGHT: gr.fillRect(x + 10, y + 4 + bob, 2, 2); break;
    }
    if (g.pushing()) {
      // arms out in front
      gr.setColor(new Color(250, 200, 150));
      int ax = g.dir == Game.LEFT ? x : g.dir == Game.RIGHT ? x + 12 : x + 6;
      int ay = g.dir == Game.UP ? y + 4 : g.dir == Game.DOWN ? y + 12 : y + 8;
      gr.fillRect(ax, ay, 4, 3);
    }
  }

  void drawSign(Graphics gr, String text) {
    int bx = 16, by = VIEW_H - 72, bw = VIEW_W - 32, bh = 60;
    gr.setColor(new Color(0, 0, 60));
    gr.fillRect(bx, by, bw, bh);
    gr.setColor(Color.white);
    gr.drawRect(bx, by, bw - 1, bh - 1);
    gr.setFont(new Font("Dialog", Font.PLAIN, 9));
    FontMetrics fm = gr.getFontMetrics();
    int ly = by + 4 + fm.getAscent();
    java.util.StringTokenizer st = new java.util.StringTokenizer(text, "\n");
    while (st.hasMoreTokens() && ly < by + bh) {
      gr.drawString(st.nextToken(), bx + 6, ly);
      ly += fm.getHeight();
    }
  }
}
