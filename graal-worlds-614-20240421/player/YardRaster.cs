using System.IO;

namespace Worlds614 {

/* Solid-colour raster of the local yard. Drawn by this program, not taken
   from a Graal install. A PPM file is not a Unity frame. */
public static class YardRaster {
    public static void Write(string path, LocalWorld world, PlayerSim sim, CameraView camera) {
        int tile = world.Tile;
        int width = world.Width * tile;
        int height = world.Height * tile;
        byte[] pixels = new byte[width * height * 3];
        for (int y = 0; y < world.Height; y++) {
            for (int x = 0; x < world.Width; x++) {
                Rgb colour = world.Wall(x, y) ? world.WallColour : world.Floor;
                if (sim.HasEntity && x == sim.EntityX && y == sim.EntityY) colour = world.Entity;
                if (x == sim.X && y == sim.Y) colour = world.Player;
                Fill(pixels, width, x * tile, y * tile, tile, tile, colour);
            }
        }
        int x0 = camera.OriginX * tile;
        int y0 = camera.OriginY * tile;
        int x1 = (camera.OriginX + camera.Width) * tile - 1;
        int y1 = (camera.OriginY + camera.Height) * tile - 1;
        for (int x = x0; x <= x1; x++) {
            Plot(pixels, width, height, x, y0, world.Outline);
            Plot(pixels, width, height, x, y1, world.Outline);
        }
        for (int y = y0; y <= y1; y++) {
            Plot(pixels, width, height, x0, y, world.Outline);
            Plot(pixels, width, height, x1, y, world.Outline);
        }
        using (FileStream file = File.Create(path)) {
            byte[] header = System.Text.Encoding.ASCII.GetBytes(
                "P6\n" + width + " " + height + "\n255\n");
            file.Write(header, 0, header.Length);
            file.Write(pixels, 0, pixels.Length);
        }
    }

    static void Fill(byte[] pixels, int width, int x, int y, int w, int h, Rgb colour) {
        for (int yy = 0; yy < h; yy++) {
            for (int xx = 0; xx < w; xx++)
                Plot(pixels, width, int.MaxValue, x + xx, y + yy, colour);
        }
    }

    static void Plot(byte[] pixels, int width, int height, int x, int y, Rgb colour) {
        if (x < 0 || y < 0 || x >= width) return;
        if (height != int.MaxValue && y >= height) return;
        int at = (y * width + x) * 3;
        if (at < 0 || at + 2 >= pixels.Length) return;
        pixels[at] = colour.R;
        pixels[at + 1] = colour.G;
        pixels[at + 2] = colour.B;
    }
}

}
