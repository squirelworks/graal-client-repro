using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace Worlds614 {

public struct Rgb {
    public byte R, G, B;
    public Rgb(byte r, byte g, byte b) { R = r; G = g; B = b; }
}

/* A local-only yard. The file format is the one in worlds/local-yard.txt.
   It is not a Graal level, gmap, or 6.114 asset. */
public sealed class LocalWorld {
    public string Name = "local-yard";
    public int Tile = 8;
    public int Width;
    public int Height;
    public char[] Cells;
    public int SpawnX;
    public int SpawnY;
    public int EntityX;
    public int EntityY;
    public bool HasEntity;
    public Rgb Floor = new Rgb(46, 120, 64);
    public Rgb WallColour = new Rgb(92, 64, 48);
    public Rgb Player = new Rgb(230, 200, 40);
    public Rgb Entity = new Rgb(40, 120, 200);
    public Rgb Outline = new Rgb(255, 255, 255);

    public static LocalWorld Parse(string text) {
        if (text == null) throw new FormatException("missing world");
        LocalWorld world = new LocalWorld();
        List<string> rows = new List<string>();
        bool grid = false;
        string[] lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        for (int i = 0; i < lines.Length; i++) {
            string line = lines[i];
            if (!grid) {
                string trimmed = line.Trim();
                if (trimmed.Length == 0 || trimmed[0] == '#') continue;
                if (trimmed == "grid") {
                    grid = true;
                    continue;
                }
                ApplyHeader(world, trimmed);
                continue;
            }
            if (line.Length == 0) continue;
            rows.Add(line);
        }
        if (!grid || rows.Count == 0) throw new FormatException("world has no grid");
        world.Height = rows.Count;
        world.Width = rows[0].Length;
        if (world.Width < 1) throw new FormatException("empty row");
        world.Cells = new char[world.Width * world.Height];
        bool spawn = false;
        for (int y = 0; y < rows.Count; y++) {
            string row = rows[y];
            if (row.Length != world.Width) throw new FormatException("jagged grid");
            for (int x = 0; x < world.Width; x++) {
                char cell = row[x];
                if (cell != '#' && cell != '.' && cell != '@' && cell != 'E')
                    throw new FormatException("bad cell");
                world.Cells[y * world.Width + x] = cell;
                if (cell == '@') {
                    if (spawn) throw new FormatException("two spawns");
                    spawn = true;
                    world.SpawnX = x;
                    world.SpawnY = y;
                } else if (cell == 'E') {
                    if (world.HasEntity) throw new FormatException("two entities");
                    world.HasEntity = true;
                    world.EntityX = x;
                    world.EntityY = y;
                }
            }
        }
        if (!spawn) throw new FormatException("no spawn");
        return world;
    }

    public static LocalWorld Load(string path) {
        return Parse(File.ReadAllText(path));
    }

    public bool InBounds(int x, int y) {
        return x >= 0 && y >= 0 && x < Width && y < Height;
    }

    public char Cell(int x, int y) {
        return Cells[y * Width + x];
    }

    public bool Wall(int x, int y) {
        if (!InBounds(x, y)) return true;
        return Cell(x, y) == '#';
    }

    static void ApplyHeader(LocalWorld world, string line) {
        string[] parts = line.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return;
        if (parts[0] == "name" && parts.Length >= 2) {
            world.Name = parts[1];
            return;
        }
        if (parts[0] == "tile" && parts.Length == 2) {
            world.Tile = int.Parse(parts[1], CultureInfo.InvariantCulture);
            if (world.Tile < 1 || world.Tile > 64) throw new FormatException("tile");
            return;
        }
        if (parts[0] == "color" && parts.Length == 5) {
            Rgb rgb = new Rgb(
                ParseByte(parts[2]),
                ParseByte(parts[3]),
                ParseByte(parts[4]));
            if (parts[1] == "floor") world.Floor = rgb;
            else if (parts[1] == "wall") world.WallColour = rgb;
            else if (parts[1] == "player") world.Player = rgb;
            else if (parts[1] == "entity") world.Entity = rgb;
            else if (parts[1] == "outline") world.Outline = rgb;
            else throw new FormatException("color");
            return;
        }
        throw new FormatException("header");
    }

    static byte ParseByte(string text) {
        int value = int.Parse(text, CultureInfo.InvariantCulture);
        if (value < 0 || value > 255) throw new FormatException("color byte");
        return (byte)value;
    }
}

}
