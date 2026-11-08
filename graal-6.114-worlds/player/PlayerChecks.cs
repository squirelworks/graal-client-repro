using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Worlds614 {

public static class PlayerChecks {
    static int passed;
    static int failed;

    public static int Run(string worldPath) {
        passed = 0;
        failed = 0;
        CheckHello();
        CheckMotion();
        CheckFile(worldPath);
        CheckSession(worldPath);
        CheckErrors();
        Console.WriteLine(passed + " passed, " + failed + " failed");
        return failed == 0 ? 0 : 1;
    }

    static void Check(bool cond, string what) {
        if (cond) {
            passed++;
            Console.WriteLine("ok    " + what);
        } else {
            failed++;
            Console.WriteLine("FAIL  " + what);
        }
    }

    static void CheckHello() {
        byte[] hello = ConnectorHello.Bytes();
        Check(hello.Length == 8, "hello is eight bytes");
        Check(Encoding.ASCII.GetString(hello) == "GNP1905C", "hello is GNP1905C");
        Check(Encoding.ASCII.GetString(hello) != "G3D0511C", "hello is not the 6.03 token");
        Check(hello[0] == (byte)'G', "hello starts at the token");
    }

    static void CheckMotion() {
        LocalWorld world = LocalWorld.Parse(
            "name box\ntile 4\ncolor floor 1 2 3\ngrid\n#####\n#@..#\n#.E.#\n#####\n");
        PlayerSim sim = new PlayerSim(world);
        Check(sim.X == 1 && sim.Y == 1, "spawn is the at-sign");
        StepResult east = sim.TryStep(world, 1, 0);
        Check(!east.Blocked && sim.X == 2 && sim.Y == 1, "step onto floor");
        StepResult south = sim.TryStep(world, 0, 1);
        Check(south.Blocked && sim.X == 2 && sim.Y == 1, "entity blocks");
        StepResult west = sim.TryStep(world, -1, 0);
        Check(!west.Blocked && sim.X == 1, "step back");
        StepResult wall = sim.TryStep(world, 0, -1);
        Check(wall.Blocked && sim.Y == 1, "wall blocks");
        int dx, dy;
        Check(PlayerSim.DecodeDir("left", out dx, out dy) && dx == -1 && dy == 0, "left is west");
        Check(!PlayerSim.DecodeDir("jump", out dx, out dy), "unknown input is refused");
        CameraView edge = PlayerSim.Camera(world, 1, 1, 5, 5);
        Check(edge.OriginX == 0 && edge.OriginY == 0 && edge.Width == 5 && edge.Height == 4,
            "camera clamps to the yard");
        sim.X = 3;
        sim.Y = 2;
        CameraView mid = PlayerSim.Camera(world, sim.X, sim.Y, 3, 3);
        Check(mid.OriginX == 2 && mid.OriginY == 1, "camera centres on the player");
    }

    static void CheckFile(string worldPath) {
        if (worldPath == null || worldPath.Length == 0) {
            Check(false, "world path");
            return;
        }
        LocalWorld world = LocalWorld.Load(worldPath);
        Check(world.Name == "local-yard", "file name is local-yard");
        Check(world.SpawnX == 1 && world.SpawnY == 1, "file spawn");
        Check(world.HasEntity && world.EntityX == 7 && world.EntityY == 3, "file entity");
        Check(world.Wall(4, 2) && world.Wall(5, 2), "file walls");
        Check(world.Floor.R == 46 && world.Player.B == 40, "file colours");
    }

    static void CheckSession(string worldPath) {
        LocalWorld world = LocalWorld.Load(worldPath);
        const string secret = "s3cret-token";
        YardServer server = new YardServer(world);
        server.Start(0);
        PlayResult result = new YardClient().Play(
            "127.0.0.1", server.Port, "loop1", secret, "e,e,e,s,e", world);
        server.Join();
        Check(result.State == LinkState.InWorld, "session reaches InWorld");
        Check(result.PlayerX == 5 && result.PlayerY == 1, "moves stop on the wall then step east");
        Check(result.Log.IndexOf("blocked=1", StringComparison.Ordinal) >= 0, "the wall step is blocked");
        Check(result.LastBlocked == false, "last step was open");
        Check(result.SawEntity && result.EntityX == 6 && result.EntityY == 3, "entity stepped west");
        Check(result.Sent.Length >= 8 && ConnectorHello.IsHello(result.Sent, 8), "wire starts with GNP1905C");
        Check(result.Sent.Length == 8 || result.Sent[8] == (byte)'L', "bytes after the hello are the local fixture");
        string sent = Encoding.ASCII.GetString(result.Sent);
        string got = Encoding.ASCII.GetString(result.Got);
        Check(sent.IndexOf(secret, StringComparison.Ordinal) < 0, "password is not on the wire");
        Check(got.IndexOf(secret, StringComparison.Ordinal) < 0, "password is not in the reply");
        Check(result.Log.IndexOf(secret, StringComparison.Ordinal) < 0, "password is not in the log");
        Check(result.Log.IndexOf("password-length 12", StringComparison.Ordinal) >= 0, "password length is logged");
        Check(result.View.IndexOf('@') >= 0 && result.View.IndexOf('E') >= 0, "camera text shows both bodies");
        string raster = Path.Combine(Path.GetTempPath(), "worlds-local-yard-check.ppm");
        PlayerSim drawn = new PlayerSim(world);
        drawn.X = result.PlayerX;
        drawn.Y = result.PlayerY;
        drawn.EntityX = result.EntityX;
        drawn.EntityY = result.EntityY;
        YardRaster.Write(raster, world, drawn, result.Camera);
        byte[] ppm = File.ReadAllBytes(raster);
        Check(ppm.Length > 16 && ppm[0] == (byte)'P' && ppm[1] == (byte)'6', "raster is a PPM");
        File.Delete(raster);
        Check(server.Fault == null, "server thread stayed up");
    }

    static void CheckErrors() {
        PlayResult refused = new YardClient().Play("off-loop", 14923, "loop1", "pw", "", Empty());
        Check(refused.State == LinkState.Error && refused.Reason == "refused-host", "non-loopback is refused");
        Check(refused.Sent.Length == 0, "refused host sends nothing");
        int closed = ClosedPort();
        PlayResult down = new YardClient().Play("127.0.0.1", closed, "loop1", "pw", "", Empty());
        Check(down.State == LinkState.Error && down.Reason == "connect-failed", "closed port is connect-failed");
        CheckBadLine();
    }

    static void CheckBadLine() {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        System.Threading.Thread thread = new System.Threading.Thread(delegate () {
            TcpClient client = listener.AcceptTcpClient();
            NetworkStream stream = client.GetStream();
            YardServer.ReadExact(stream, 8);
            byte[] nope = Encoding.ASCII.GetBytes("NOPE\n");
            stream.Write(nope, 0, nope.Length);
            client.Close();
            listener.Stop();
        });
        thread.IsBackground = true;
        thread.Start();
        PlayResult bad = new YardClient().Play("127.0.0.1", port, "loop1", "pw", "", Empty());
        thread.Join();
        Check(bad.State == LinkState.Error && bad.Reason == "bad-line", "a non-local reply is an error");
    }

    static int ClosedPort() {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    static LocalWorld Empty() {
        return LocalWorld.Parse("name empty\ngrid\n@\n");
    }
}

}
