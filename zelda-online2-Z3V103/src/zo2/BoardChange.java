package zo2;

/** B's published rectangle contract; no original program or tile tables.
 * Validation is rebuild policy: reject the complete malformed rectangle. */
final class BoardChange {
  final int x, y, width, height;
  private final int[] tiles; // x-major, unlike Level's row-major board

  BoardChange(int x, int y, int width, int height, int[] values) {
    if (x < 0 || y < 0 || width < 1 || width > Level.W || height < 1 || height > 7 ||
        x > Level.W - width || y > Level.H - height || width * 8 + height > 223 ||
        values == null || values.length != width * height)
      throw new IllegalArgumentException("invalid board rectangle");
    for (int value : values)
      if (value < 0 || value > 16383) throw new IllegalArgumentException("invalid board tile");
    this.x = x; this.y = y; this.width = width; this.height = height;
    tiles = values.clone();
  }

  String encode() {
    StringBuilder out = new StringBuilder();
    out.append(Net.c(x)).append(Net.c(y)).append(Net.c(width * 8 + height));
    for (int tile : tiles) out.append(Net.c(tile / 128)).append(Net.c(tile % 128));
    return out.toString();
  }

  static BoardChange decode(String data) {
    if (data.length() < 3) throw new IllegalArgumentException("short board rectangle");
    int size = data.charAt(2) - 32, w = size / 8, h = size % 8;
    if (size < 0 || size > 223 || w < 1 || h < 1 || data.length() != 3 + 2 * w * h)
      throw new IllegalArgumentException("invalid board rectangle length");
    int[] tiles = new int[w * h];
    for (int i = 0; i < tiles.length; i++) {
      int hi = data.charAt(3 + 2 * i) - 32, lo = data.charAt(4 + 2 * i) - 32;
      if (hi < 0 || hi > 127 || lo < 0 || lo > 127)
        throw new IllegalArgumentException("invalid board tile encoding");
      tiles[i] = hi * 128 + lo;
    }
    return new BoardChange(data.charAt(0) - 32, data.charAt(1) - 32, w, h, tiles);
  }

  boolean apply(Level board) {
    boolean changed = false;
    for (int dx = 0; dx < width; dx++)
      for (int dy = 0; dy < height; dy++) {
        int dest = x + dx + (y + dy) * Level.W;
        int tile = tiles[dx * height + dy];
        // Deliberate rebuild policy: compare each destination. The source-only
        // top-left detector quirk is not reproduced; see README fidelity limit.
        changed |= board.tiles[dest] != tile;
        board.tiles[dest] = tile;
      }
    return changed;
  }
}
