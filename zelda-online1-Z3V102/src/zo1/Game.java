package zo1;

/**
 * The game state and its 50 ms tick (20 Hz), as graal_analysis
 * client-internals/precursor-runs-2026-10-30.md gives the Zelda Online
 * engine's numbers:
 *
 *   walk step   half a tile per tick while a key is held
 *   corner      a quarter of the walk step sideways around a block edge
 *   push        ticks 0-17 nothing, push pose from tick 18 (frame every 4
 *               ticks), back to 18 at tick 38; releasing or turning resets
 *
 * Positions are in tiles (8 pixels). The player is 2 tiles wide; the lower
 * 2x1 tiles are the feet, which is what collides.
 */
public class Game {
  public static final int TICK_MS = 50;
  public static final double STEP = 0.5;
  public static final double SLIDE = STEP / 4;
  public static final int UP = 0, LEFT = 1, DOWN = 2, RIGHT = 3;
  public static final String START_LEVEL = "level1.zelda";

  public Assets assets;
  public boolean[] walkable;
  public Level level;
  public double x, y;
  public int dir = DOWN;
  public int walkFrame;
  public boolean moving;
  public int push;
  public int ticks;
  public String signText; // the sign being read, or null
  public String status = "";
  /** The title screen is up: the board waits for a key. */
  public boolean title;
  /** What the HUD shows; nothing in this build changes them yet. */
  public int rupees = 0, bombs = 0, arrows = 5, hearts = 3;

  // held keys, one bit per direction, and the action key
  public int keys;
  public boolean action;
  boolean actionWas;
  int keysWas;

  public Game(Assets assets) {
    this.assets = assets;
    this.walkable = assets.walkable();
  }

  public boolean enter(String name, double nx, double ny) {
    Level lv = assets.level(name);
    if (lv == null) {
      status = "cannot load " + name;
      return false;
    }
    level = lv;
    if (nx >= 0) x = nx;
    if (ny >= 0) y = ny;
    if (blocked(x, y)) findFreeSpot();
    status = name;
    return true;
  }

  /**
   * The start: level1.zelda at (23, 37), measured in the original (Mirae
   * lab, 2026-11-13: the view origin at (64, 192) and the body's left edge
   * at 184).
   */
  public boolean start(String name) {
    x = 23; y = 37;
    return enter(name == null ? START_LEVEL : name, -1, -1);
  }

  void findFreeSpot() {
    for (int r = 0; r < 64; r++)
      for (int dy = -r; dy <= r; dy++)
        for (int dx = -r; dx <= r; dx++) {
          double tx = Math.floor(x) + dx, ty = Math.floor(y) + dy;
          if (tx >= 0 && ty >= 0 && tx < 62 && ty < 62 && !blocked(tx, ty)) {
            x = tx; y = ty;
            return;
          }
        }
  }

  public boolean solid(double tx, double ty) {
    int t = level.tile((int) Math.floor(tx), (int) Math.floor(ty));
    return t < 0 || t >= walkable.length || !walkable[t];
  }

  /** Whether the feet would overlap anything solid at (px, py). */
  public boolean blocked(double px, double py) {
    return solid(px + 0.25, py + 1.0) || solid(px + 1.75, py + 1.0)
        || solid(px + 0.25, py + 1.95) || solid(px + 1.75, py + 1.95);
  }

  public void tick() {
    if (title) return;
    ticks++;
    boolean actPressed = action && !actionWas;
    int newKeys = keys & ~keysWas;
    actionWas = action;
    keysWas = keys;

    if (signText != null) {
      if (actPressed || newKeys != 0) signText = null;
      moving = false;
      return;
    }

    int dx = 0, dy = 0;
    if ((keys & (1 << UP)) != 0) dy--;
    if ((keys & (1 << DOWN)) != 0) dy++;
    if ((keys & (1 << LEFT)) != 0) dx--;
    if ((keys & (1 << RIGHT)) != 0) dx++;
    int oldDir = dir;
    if (newKeys != 0) {
      for (int d = 0; d < 4; d++) if ((newKeys & (1 << d)) != 0) dir = d;
    } else if (dx != 0 || dy != 0) {
      if (dir == UP && dy >= 0 || dir == DOWN && dy <= 0 || dir == LEFT && dx >= 0 || dir == RIGHT && dx <= 0)
        dir = dy < 0 ? UP : dy > 0 ? DOWN : dx < 0 ? LEFT : RIGHT;
    }

    moving = dx != 0 || dy != 0;
    if (!moving || dir != oldDir) push = 0;
    if (!moving) {
      walkFrame = 0;
      if (actPressed) readSign();
      return;
    }

    boolean hit = false;
    if (dx != 0) hit |= !moveX(dx * STEP);
    if (dy != 0) hit |= !moveY(dy * STEP);
    walkFrame = (walkFrame + 1) % 4;

    if (hit) {
      push++;
      if (push == 38) push = 18;
      if (dir == UP && push == 1 || actPressed) readSign();
    } else {
      push = 0;
    }
    checkLinks();
  }

  boolean moveX(double d) {
    if (!blocked(x + d, y)) { x += d; return true; }
    // corner slide: step a quarter sideways when only one foot corner is in the way
    if (!blocked(x + d, y - SLIDE * 2) && blocked(x + d, y + SLIDE * 2)) { y -= SLIDE; return false; }
    if (!blocked(x + d, y + SLIDE * 2) && blocked(x + d, y - SLIDE * 2)) { y += SLIDE; return false; }
    return false;
  }

  boolean moveY(double d) {
    if (!blocked(x, y + d)) { y += d; return true; }
    if (!blocked(x - SLIDE * 2, y + d) && blocked(x + SLIDE * 2, y + d)) { x -= SLIDE; return false; }
    if (!blocked(x + SLIDE * 2, y + d) && blocked(x - SLIDE * 2, y + d)) { x += SLIDE; return false; }
    return false;
  }

  /** The push pose shows from tick 18 of walking into something. */
  public boolean pushing() {
    return push >= 18;
  }

  void readSign() {
    if (dir != UP) return;
    int ty = (int) Math.floor(y + 1.0 - 0.01);
    int x0 = (int) Math.floor(x + 0.25), x1 = (int) Math.floor(x + 1.75);
    for (int i = 0; i < level.signs.size(); i++) {
      Level.Sign s = (Level.Sign) level.signs.elementAt(i);
      if ((s.y == ty || s.y == ty - 1) && s.x >= x0 - 1 && s.x <= x1) {
        signText = s.text;
        return;
      }
    }
  }

  void checkLinks() {
    // the feet's leading edge in the walking direction
    double cx = x + 1.0, cy = y + 1.5;
    if (dir == LEFT) cx = x + 0.25;
    if (dir == RIGHT) cx = x + 1.75;
    if (dir == UP) cy = y + 1.0;
    if (dir == DOWN) cy = y + 1.95;
    for (int i = 0; i < level.links.size(); i++) {
      Level.Link l = (Level.Link) level.links.elementAt(i);
      if (cx >= l.x && cx < l.x + l.w && cy >= l.y && cy < l.y + l.h) {
        enter(l.file, l.newX, l.newY);
        push = 0;
        return;
      }
    }
  }
}
