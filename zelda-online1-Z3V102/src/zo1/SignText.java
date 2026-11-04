package zo1;

/**
 * Sign text: each byte minus 32 indexes the 97-entry sign alphabet that
 * Zelda Online already had and later Graal kept (graal_analysis
 * formats/sign-text.md). '#' slots are glyph codes (button icons, arrows,
 * hearts); they are shown as '#' plus the glyph letter, as the editor
 * writes them. Code 96 is a line break.
 */
public class SignText {
  public static final String ALPHABET =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      + "!?-.,#>()#####\"####':/~&### <####;\n";

  static String glyph(int k) {
    switch (k) {
      case 91: return "A";
      case 92: return "B";
      case 93: return "X";
      case 94: return "Y";
      case 77: return "u";
      case 78: return "d";
      case 79: return "l";
      case 80: return "r";
      case 74: return "h";
      case 71: return "x";
      case 72: return "y";
      case 73: return "z";
      case 87: return "4";
      case 67: return ".";
      default: return "";
    }
  }

  public static String decode(byte[] enc) {
    StringBuffer r = new StringBuffer();
    for (int i = 0; i < enc.length; i++) {
      int k = (enc[i] & 0xFF) - 32;
      if (k < 0) continue; // controls are not shown
      char c = k < ALPHABET.length() ? ALPHABET.charAt(k) : '?';
      if (c == '#' && k != 86) {
        r.append('#').append(glyph(k));
        if (k == 74 || k == 87) i++; // two-code glyphs
      } else {
        r.append(c);
      }
    }
    return r.toString();
  }

  /** Plain text to sign bytes (letters, digits, punctuation, space, newline). */
  public static byte[] encode(String s) {
    byte[] out = new byte[s.length()];
    int n = 0;
    for (int i = 0; i < s.length(); i++) {
      int k = ALPHABET.indexOf(s.charAt(i));
      if (s.charAt(i) == '#') k = 86;
      if (k < 0) k = ALPHABET.indexOf('?');
      out[n++] = (byte) (k + 32);
    }
    return out;
  }
}
