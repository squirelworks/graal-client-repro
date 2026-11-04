package zo1;

import java.util.Vector;

/**
 * arrays.dat: a list of typed integer arrays. Each starts with a 32-bit
 * big-endian header, kind in the high 16 bits (0 = flat int array, 1 = an
 * array of arrays) and the count in the low 16 bits; values are big-endian
 * 32-bit ints. The first array is the list of tiles a player can walk on
 * (graal_analysis client-internals/precursors-and-fan-builds.md).
 */
public class Arrays {
  /** Each element is an int[] or an Object[] of nested elements. */
  public Vector items = new Vector();

  int p;
  byte[] d;

  public static Arrays parse(byte[] d) {
    Arrays a = new Arrays();
    a.d = d;
    while (a.p + 4 <= d.length) a.items.addElement(a.read(0));
    a.d = null;
    return a;
  }

  int int32() {
    if (p + 4 > d.length) throw new IllegalArgumentException("arrays.dat ends early");
    int v = ((d[p] & 0xFF) << 24) | ((d[p + 1] & 0xFF) << 16) | ((d[p + 2] & 0xFF) << 8) | (d[p + 3] & 0xFF);
    p += 4;
    return v;
  }

  Object read(int depth) {
    if (depth > 8) throw new IllegalArgumentException("arrays.dat nests too deep");
    int h = int32();
    int kind = (h >>> 16) & 0xFFFF, count = h & 0xFFFF;
    if (kind == 0) {
      int[] v = new int[count];
      for (int i = 0; i < count; i++) v[i] = int32();
      return v;
    }
    Object[] v = new Object[count];
    for (int i = 0; i < count; i++) v[i] = read(depth + 1);
    return v;
  }

  /** Item i if it is a flat array, else null. */
  public int[] flat(int i) {
    if (i >= items.size()) return null;
    Object o = items.elementAt(i);
    return o instanceof int[] ? (int[]) o : null;
  }

  /** Writes a list of flat arrays (tests and stand-ins). */
  public static byte[] write(int[][] arrays) {
    java.io.ByteArrayOutputStream o = new java.io.ByteArrayOutputStream();
    for (int i = 0; i < arrays.length; i++) {
      put(o, arrays[i].length);
      for (int k = 0; k < arrays[i].length; k++) put(o, arrays[i][k]);
    }
    return o.toByteArray();
  }

  static void put(java.io.ByteArrayOutputStream o, int v) {
    o.write(v >>> 24); o.write(v >>> 16); o.write(v >>> 8); o.write(v);
  }
}
