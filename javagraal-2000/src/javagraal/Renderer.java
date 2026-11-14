package javagraal;

import java.awt.Color;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.image.BufferedImage;

/**
 * Draws one frame: the applet's 512x418 box, 16 pixels per board tile. The
 * board fills the top 512x384; the chat field is the 30 rows from y 386
 * (isolated lab, 2026-11-13).
 * An 8-pixel tile sheet is drawn at double size. The view follows the
 * player and stops at the board edges. Players are the rebuild's own
 * stand-in figure; level NPCs show their image (the script is ignored, as
 * Java Graal ignored it).
 */
public class Renderer {
  public static final int VIEW_W = 512, VIEW_H = 418, SCALE = 1, U = 16;
  /** The board view and the chat field under it. */
  public static final int GAME_H = 384, CHAT_Y = 386, CHAT_H = 30;

  BufferedImage sheet;
  int ts;
  BufferedImage frame = new BufferedImage(VIEW_W, VIEW_H, BufferedImage.TYPE_INT_RGB);
  java.util.Hashtable images = new java.util.Hashtable();
  Assets assets;

  public Renderer(BufferedImage sheet) {
    this.sheet = sheet;
    this.ts = TileSheet.tileSize(sheet.getHeight());
  }

  public Renderer(BufferedImage sheet, Assets assets) {
    this(sheet);
    this.assets = assets;
  }

  BufferedImage image(String name) {
    if (assets == null) return null;
    Object o = images.get(name);
    if (o == null) {
      BufferedImage im = assets.image(name);
      images.put(name, im == null ? (Object) Boolean.FALSE : im);
      return im;
    }
    return o instanceof BufferedImage ? (BufferedImage) o : null;
  }

  public BufferedImage frame() {
    return frame;
  }

  public void draw(Game g) {
    java.awt.Graphics2D gr = (java.awt.Graphics2D) frame.getGraphics();
    gr.setColor(Color.black);
    gr.fillRect(0, 0, VIEW_W, VIEW_H);
    if (g.title) {
      drawTitle(gr);
      gr.dispose();
      return;
    }
    gr.setClip(0, 0, VIEW_W, GAME_H);
    // the view is centred on the 32x32 body (clamping at the board's edges
    // is the rebuild's own; the lab runs did not reach an edge)
    int px = (int) Math.round(g.x * U), py = (int) Math.round(g.y * U);
    int camX = clamp(px + U - VIEW_W / 2, 0, 64 * U - VIEW_W);
    int camY = clamp(py + U - GAME_H / 2, 0, 64 * U - GAME_H);
    int tx0 = camX / U, ty0 = camY / U;
    for (int ty = ty0; ty <= ty0 + GAME_H / U + 1 && ty < 64; ty++) {
      for (int tx = tx0; tx <= tx0 + VIEW_W / U + 1 && tx < 64; tx++) {
        int t = g.level.tile(tx, ty);
        int dx = tx * U - camX, dy = ty * U - camY;
        int sx = TileSheet.sx(t, ts), sy = TileSheet.sy(t, ts);
        gr.drawImage(sheet, dx, dy, dx + U, dy + U, sx, sy, sx + ts, sy + ts, null);
      }
    }
    for (int i = 0; i < g.level.npcs.size(); i++) {
      Level.Npc n = (Level.Npc) g.level.npcs.elementAt(i);
      BufferedImage im = n.image.length() == 0 ? null : image(n.image);
      if (im != null) gr.drawImage(im, n.x * U - camX, n.y * U - camY, null);
    }
    // the figures and text below are drawn in 8-pixel tile units, doubled
    java.awt.geom.AffineTransform keep = gr.getTransform();
    gr.scale(2, 2);
    camX /= 2; camY /= 2;
    px /= 2; py /= 2;
    if (g.net != null) {
      for (java.util.Enumeration e = g.net.peers.elements(); e.hasMoreElements();) {
        Net.Peer p = (Net.Peer) e.nextElement();
        if (!p.here || p.x < 0) continue;
        int ox = (int) Math.round(p.x * 8) - camX, oy = (int) Math.round(p.y * 8) - camY;
        drawFigure(gr, ox, oy, p.dir, p.frame, false, false, p.colours);
        drawText(gr, p.chat, ox, oy - 4);
        drawText(gr, p.nick, ox, oy + 24 + 6);
      }
    }
    drawPlayer(gr, g, px - camX, py - camY);
    drawText(gr, g.chat, px - camX, py - camY - 4);
    if (g.showOwnName) drawText(gr, g.nickname, px - camX, py - camY + 24 + 6);
    gr.setTransform(keep);
    if (g.signText != null) drawSign(gr, g.signText);
    gr.setClip(null);
    drawChatField(gr, g.typing);
    gr.dispose();
  }

  static int clamp(int v, int lo, int hi) {
    return v < lo ? lo : v > hi ? hi : v;
  }

  /**
   * Chat and names: no bubble. Bold serif text in black over a white copy
   * shifted one pixel right and down, centred on the player (x + 12 pixels
   * at the original's scale 2).
   */
  void drawText(Graphics gr, String text, int x, int y) {
    if (text == null || text.length() == 0) return;
    gr.setFont(new Font("Serif", Font.BOLD, 10));
    FontMetrics fm = gr.getFontMetrics();
    int tx = x + 6 - fm.stringWidth(text) / 2;
    gr.setColor(Color.white);
    gr.drawString(text, tx + 1, y + 1);
    gr.setColor(Color.black);
    gr.drawString(text, tx, y);
  }

  void drawPlayer(Graphics gr, Game g, int x, int y) {
    drawFigure(gr, x, y, g.dir, g.walkFrame, g.moving, g.pushing(), g.colours);
  }

  void drawFigure(Graphics gr, int x, int y, int dir, int frame, boolean moving, boolean pushing, int[] colours) {
    int bob = moving && (frame & 1) == 1 ? 1 : 0;
    // shadow, coat, belt, head, cap with its edge
    gr.setColor(new Color(0, 0, 0, 80));
    gr.fillOval(x + 2, y + 13, 12, 4);
    gr.setColor(Colours.get(colours, 3));
    gr.fillRect(x + 3, y + 6 + bob, 10, 8);
    gr.setColor(Colours.get(colours, 2));
    gr.fillRect(x + 3, y + 10 + bob, 10, 1);
    gr.setColor(new Color(250, 200, 150));
    gr.fillOval(x + 3, y - 1 + bob, 10, 9);
    gr.setColor(Colours.get(colours, 0));
    gr.fillRect(x + 3, y - 1 + bob, 10, 3);
    gr.setColor(Colours.get(colours, 1));
    gr.fillRect(x + 3, y + 2 + bob, 10, 1);
    // a mark on the facing side
    gr.setColor(Color.black);
    switch (dir) {
      case Game.UP: break;
      case Game.DOWN: gr.fillRect(x + 5, y + 4 + bob, 2, 2); gr.fillRect(x + 9, y + 4 + bob, 2, 2); break;
      case Game.LEFT: gr.fillRect(x + 4, y + 4 + bob, 2, 2); break;
      case Game.RIGHT: gr.fillRect(x + 10, y + 4 + bob, 2, 2); break;
    }
    if (pushing) {
      // arms out in front
      gr.setColor(new Color(250, 200, 150));
      int ax = dir == Game.LEFT ? x : dir == Game.RIGHT ? x + 12 : x + 6;
      int ay = dir == Game.UP ? y + 4 : dir == Game.DOWN ? y + 12 : y + 8;
      gr.fillRect(ax, ay, 4, 3);
    }
  }

  /**
   * The title screen: black, the logo in a 307x117 box at (100, 130) and
   * "Press any key to start!" in white from x 151, baseline 319 (isolated lab,
   * 2026-11-13). The logo is the original's picture, which is not here: a
   * plain outline and the name stand in for it.
   */
  void drawTitle(Graphics gr) {
    gr.setColor(new Color(90, 90, 90));
    gr.drawRect(100, 130, 307 - 1, 117 - 1);
    gr.setColor(Color.white);
    gr.setFont(new Font("Serif", Font.BOLD, 64));
    FontMetrics fm = gr.getFontMetrics();
    gr.drawString(JavaGraal.TITLE, 100 + (307 - fm.stringWidth(JavaGraal.TITLE)) / 2, 130 + 117 / 2 + fm.getAscent() / 3);
    gr.setFont(new Font("Dialog", Font.BOLD, 16));
    gr.drawString("Press any key to start!", 151, 319);
  }

  /** The chat field under the board, with the line being typed. */
  void drawChatField(Graphics gr, String typing) {
    gr.setColor(new Color(192, 192, 192));
    gr.fillRect(0, GAME_H, VIEW_W, VIEW_H - GAME_H);
    gr.setColor(Color.white);
    gr.fillRect(0, CHAT_Y, VIEW_W, CHAT_H);
    gr.setColor(Color.gray);
    gr.drawRect(0, CHAT_Y, VIEW_W - 1, CHAT_H - 1);
    if (typing == null) return;
    gr.setColor(Color.black);
    gr.setFont(new Font("Dialog", Font.PLAIN, 14));
    gr.drawString(typing + "_", 6, CHAT_Y + CHAT_H - 9);
  }

  void drawSign(Graphics gr, String text) {
    int bx = 32, by = GAME_H - 120, bw = VIEW_W - 64, bh = 100;
    gr.setColor(new Color(0, 0, 60));
    gr.fillRect(bx, by, bw, bh);
    gr.setColor(Color.white);
    gr.drawRect(bx, by, bw - 1, bh - 1);
    gr.setFont(new Font("Dialog", Font.PLAIN, 16));
    FontMetrics fm = gr.getFontMetrics();
    int ly = by + 4 + fm.getAscent();
    java.util.StringTokenizer st = new java.util.StringTokenizer(text, "\n");
    while (st.hasMoreTokens() && ly < by + bh) {
      gr.drawString(st.nextToken(), bx + 6, ly);
      ly += fm.getHeight();
    }
  }
}
