package zo2;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Vector;
import javax.imageio.ImageIO;

/**
 * Where the game finds its files. The original read everything from its
 * working folder (the package's game/ folder): levels, arrays.dat and the
 * GIFs. The rebuild looks, in order, in:
 *
 *   --data DIR (when given)
 *   the folder the program is in (and its levels/ and game/ folders)
 *   graal-assets/zelda-online2/ in that folder
 *   graal-assets/common/ in that folder
 *
 * and else uses its own stand-in graphics and levels (StandIn). Nothing
 * above the program's folder is read.
 */
public class Assets {
  public static final String LABEL = "zelda-online2";

  Vector dirs = new Vector();
  public boolean usingStandIn;

  public Assets(File programDir, File dataDir) {
    if (dataDir != null) addDir(dataDir);
    if (programDir != null) {
      addDir(programDir);
      addDir(new File(programDir, "game"));
      addDir(new File(new File(programDir, "graal-assets"), LABEL));
      addDir(new File(new File(programDir, "graal-assets"), "common"));
    }
  }

  void addDir(File d) {
    dirs.addElement(d);
    dirs.addElement(new File(d, "levels"));
  }

  /** The first existing file of that name, or null. */
  public File find(String name) {
    for (int i = 0; i < dirs.size(); i++) {
      File f = new File((File) dirs.elementAt(i), name);
      if (f.isFile()) return f;
    }
    return null;
  }

  public static byte[] readAll(File f) throws IOException {
    InputStream in = new FileInputStream(f);
    try {
      ByteArrayOutputStream o = new ByteArrayOutputStream();
      byte[] b = new byte[8192];
      int n;
      while ((n = in.read(b)) > 0) o.write(b, 0, n);
      return o.toByteArray();
    } finally {
      in.close();
    }
  }

  /** A level from the files, else a stand-in level of that name, else null. */
  public Level level(String name) {
    File f = find(name);
    if (f != null) {
      try {
        return Level.parse(readAll(f), name);
      } catch (Exception e) {
        System.err.println("level " + name + ": " + e.getMessage());
        return null;
      }
    }
    byte[] b = StandIn.level(name);
    return b == null ? null : Level.parse(b, name);
  }

  /** The tile sheet: pics1.gif from the install, else the stand-in sheet. */
  public BufferedImage tileSheet() {
    File f = find("pics1.gif");
    if (f != null) {
      try {
        BufferedImage im = ImageIO.read(f);
        if (im != null) return im;
      } catch (IOException e) {
        System.err.println("pics1.gif: " + e.getMessage());
      }
    }
    usingStandIn = true;
    return StandIn.sheet();
  }

  /** The tile ids a player can walk on: arrays.dat's first array, else the stand-in set. */
  public boolean[] walkable() {
    File f = find("arrays.dat");
    if (f != null) {
      try {
        Arrays a = Arrays.parse(readAll(f));
        int[] ids = a.flat(0);
        if (ids != null) {
          boolean[] w = new boolean[4096];
          for (int i = 0; i < ids.length; i++)
            if (ids[i] >= 0 && ids[i] < w.length) w[ids[i]] = true;
          return w;
        }
      } catch (Exception e) {
        System.err.println("arrays.dat: " + e.getMessage());
      }
    }
    return StandIn.walkable();
  }
}
