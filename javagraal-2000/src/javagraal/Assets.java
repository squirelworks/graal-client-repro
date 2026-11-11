package javagraal;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.FileReader;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.Vector;
import javax.imageio.ImageIO;

/**
 * Where the game finds its files. The applet fetched everything relative
 * to its codebase: pics1.gif, arrays.dat, the other GIFs and levels/. The
 * rebuild looks, in order, in:
 *
 *   --data DIR (when given)
 *   the folder the program is in (and its levels/ folder)
 *   graal-assets/javagraal/ in that folder
 *   graal-assets/common/ in that folder
 *
 * In a shared root (a folder holding _clients/, the one-folder layout of
 * every client) it reads _clients/<label>/ first, then only the root
 * files its files.txt names: never a file another version's install had.
 *
 * and else uses its own stand-in graphics and levels (StandIn). Nothing
 * above the program's folder is read.
 */
public class Assets {
  public static final String LABEL = "javagraal";

  Vector dirs = new Vector();
  public boolean usingStandIn;

  /** Per entry of dirs: the root files it may give (null: all) and the
   *  entry's path below that root. */
  Vector allow = new Vector();
  Vector prefix = new Vector();

  public Assets(File programDir, File dataDir) {
    if (dataDir != null) addInstall(dataDir);
    if (programDir != null) {
      addInstall(programDir);
      addDir(new File(new File(programDir, "graal-assets"), LABEL), null, "");
      addDir(new File(new File(programDir, "graal-assets"), "common"), null, "");
    }
  }

  /** A data or program folder; the files.txt list when it is a shared root. */
  Set addInstall(File d) {
    if (!new File(d, "_clients").isDirectory()) {
      addDir(d, null, "");
      return null;
    }
    File own = new File(new File(d, "_clients"), LABEL);
    Set list = new HashSet();
    if (own.isDirectory()) {
      addDir(own, null, "");
      File ft = new File(own, "files.txt");
      if (ft.isFile()) {
        try {
          BufferedReader r = new BufferedReader(new FileReader(ft));
          try {
            String line;
            while ((line = r.readLine()) != null) {
              line = line.trim();
              if (line.length() > 0) list.add(norm(line));
            }
          } finally {
            r.close();
          }
        } catch (IOException e) {
          System.err.println(ft + ": " + e.getMessage());
        }
      }
    }
    addDir(d, list, "");
    return list;
  }

  static String norm(String rel) {
    return rel.replace('\\', '/').toLowerCase(Locale.ROOT);
  }

  void addDir(File d, Set allowed, String rel) {
    dirs.addElement(d);
    allow.addElement(allowed);
    prefix.addElement(rel);
    dirs.addElement(new File(d, "levels"));
    allow.addElement(allowed);
    prefix.addElement(rel + "levels/");
  }

  /** The first existing file of that name, or null. */
  public File find(String name) {
    for (int i = 0; i < dirs.size(); i++) {
      Set a = (Set) allow.elementAt(i);
      if (a != null && !a.contains(norm(prefix.elementAt(i) + name))) continue;
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

  /** Any GIF the levels name (NPC images), or null. */
  public BufferedImage image(String name) {
    if (name.indexOf("..") >= 0 || name.startsWith("/") || name.startsWith("\\") || name.indexOf(':') >= 0) return null;
    File f = find(name);
    if (f == null) return null;
    try {
      return ImageIO.read(f);
    } catch (IOException e) {
      return null;
    }
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
