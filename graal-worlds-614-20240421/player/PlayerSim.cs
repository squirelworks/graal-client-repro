using System;

namespace Worlds614 {

public struct StepResult {
    public int X;
    public int Y;
    public bool Blocked;
}

public struct CameraView {
    public int OriginX;
    public int OriginY;
    public int Width;
    public int Height;
}

/* Local movement. One cell per input. Walls and the other entity block.
   The camera is a window centred on the player and clamped to the yard.
   None of this is a 6.114 property encoding. */
public sealed class PlayerSim {
    public int X;
    public int Y;
    public bool HasEntity;
    public int EntityX;
    public int EntityY;

    public PlayerSim(LocalWorld world) {
        X = world.SpawnX;
        Y = world.SpawnY;
        HasEntity = world.HasEntity;
        EntityX = world.EntityX;
        EntityY = world.EntityY;
    }

    public bool Occupied(int x, int y) {
        return HasEntity && x == EntityX && y == EntityY;
    }

    public StepResult TryStep(LocalWorld world, int dx, int dy) {
        StepResult step = new StepResult();
        int nx = X + dx;
        int ny = Y + dy;
        if (world.Wall(nx, ny) || Occupied(nx, ny)) {
            step.X = X;
            step.Y = Y;
            step.Blocked = true;
            return step;
        }
        X = nx;
        Y = ny;
        step.X = X;
        step.Y = Y;
        step.Blocked = false;
        return step;
    }

    public static bool DecodeDir(string dir, out int dx, out int dy) {
        dx = 0;
        dy = 0;
        if (dir == null) return false;
        string name = dir.Trim().ToLowerInvariant();
        if (name == "n" || name == "north" || name == "up") { dy = -1; return true; }
        if (name == "s" || name == "south" || name == "down") { dy = 1; return true; }
        if (name == "w" || name == "west" || name == "left") { dx = -1; return true; }
        if (name == "e" || name == "east" || name == "right") { dx = 1; return true; }
        return false;
    }

    public static CameraView Camera(LocalWorld world, int x, int y, int width, int height) {
        CameraView view = new CameraView();
        int w = width;
        int h = height;
        if (w > world.Width) w = world.Width;
        if (h > world.Height) h = world.Height;
        if (w < 1) w = 1;
        if (h < 1) h = 1;
        int ox = x - w / 2;
        int oy = y - h / 2;
        if (ox < 0) ox = 0;
        if (oy < 0) oy = 0;
        int maxX = world.Width - w;
        int maxY = world.Height - h;
        if (ox > maxX) ox = maxX;
        if (oy > maxY) oy = maxY;
        view.OriginX = ox;
        view.OriginY = oy;
        view.Width = w;
        view.Height = h;
        return view;
    }

    public static string CameraText(LocalWorld world, PlayerSim sim, CameraView view) {
        String text = "";
        for (int y = 0; y < view.Height; y++) {
            for (int x = 0; x < view.Width; x++) {
                int wx = view.OriginX + x;
                int wy = view.OriginY + y;
                char cell = world.Wall(wx, wy) ? '#' : '.';
                if (sim.HasEntity && wx == sim.EntityX && wy == sim.EntityY) cell = 'E';
                if (wx == sim.X && wy == sim.Y) cell = '@';
                text += cell;
            }
            text += "\n";
        }
        return text;
    }
}

}
