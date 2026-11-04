package javagraal;

import java.awt.Color;

/**
 * The colour choices for the player's cap, cap edge, belt and coat. The
 * options window picks an index per part and multiplayer sends the indices
 * (D type S). The rebuild's own list: the original's colour table is not in
 * the notes yet.
 */
public class Colours {
  public static final String[] NAMES = {
    "green", "dark green", "brown", "light green", "red", "blue", "yellow", "white",
    "black", "orange", "purple", "grey"
  };
  static final Color[] RGB = {
    new Color(30, 110, 50), new Color(15, 70, 30), new Color(110, 70, 30), new Color(40, 140, 60),
    new Color(200, 40, 40), new Color(40, 70, 200), new Color(230, 210, 60), new Color(240, 240, 240),
    new Color(20, 20, 20), new Color(230, 130, 30), new Color(130, 50, 170), new Color(130, 130, 130)
  };

  public static Color get(int[] colours, int part) {
    int i = colours != null && part < colours.length ? colours[part] : part;
    if (i < 0 || i >= RGB.length) i = 0;
    return RGB[i];
  }
}
