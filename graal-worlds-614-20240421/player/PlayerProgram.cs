using System;
using System.IO;

namespace Worlds614 {

/* Portable player for the 6.114 folder. The Unity editor is not invoked.
   A self-check or a PPM raster is not a Unity player build. */
public static class PlayerProgram {
    public static int Main(string[] args) {
        bool self = false;
        bool list = false;
        bool smoke = false;
        bool serve = false;
        string worldPath = null;
        string raster = null;
        string account = "loop1";
        string moves = "e,e,e,s,e";
        int port = 14923;
        bool havePort = false;
        for (int i = 0; i < args.Length; i++) {
            string arg = args[i];
            if (arg == "--self-check") self = true;
            else if (arg == "--list") list = true;
            else if (arg == "--smoke") smoke = true;
            else if (arg == "--serve") serve = true;
            else if (arg == "--world" && i + 1 < args.Length) worldPath = args[++i];
            else if (arg == "--raster" && i + 1 < args.Length) raster = args[++i];
            else if (arg == "--account" && i + 1 < args.Length) account = args[++i];
            else if (arg == "--moves" && i + 1 < args.Length) moves = args[++i];
            else if (arg == "--port" && i + 1 < args.Length) {
                if (!int.TryParse(args[++i], out port) || port <= 0 || port > 65535) {
                    Console.WriteLine("state Error reason=port-out-of-range");
                    return 2;
                }
                havePort = true;
            } else {
                Console.WriteLine("state Error reason=bad-arg");
                return 2;
            }
        }
        if (list) {
            PrintList();
            if (!self && !smoke && !serve) return 0;
        }
        if (self) {
            if (worldPath == null) worldPath = DefaultWorld();
            return PlayerChecks.Run(worldPath);
        }
        if (worldPath == null) worldPath = DefaultWorld();
        LocalWorld world;
        try {
            world = LocalWorld.Load(worldPath);
        } catch (Exception) {
            Console.WriteLine("state Error reason=world-unreadable");
            return 1;
        }
        if (serve && !smoke) {
            if (!havePort) port = 14923;
            YardServer server = new YardServer(world);
            try {
                server.Start(port);
            } catch (Exception) {
                Console.WriteLine("state Error reason=connect-failed");
                return 1;
            }
            Console.WriteLine("unity player built: no");
            Console.WriteLine("local-only fixture");
            Console.WriteLine("serve 127.0.0.1:" + server.Port);
            server.Join();
            return server.Fault == null ? 0 : 1;
        }
        if (smoke || havePort) {
            return RunSmoke(world, worldPath, port, account, moves, raster);
        }
        Console.WriteLine("worlds-player: portable 6.114 stand-in. Unity player was not built.");
        Console.WriteLine("  --self-check --world worlds/local-yard.txt");
        Console.WriteLine("  --smoke --port 14923 --world worlds/local-yard.txt --raster out.ppm");
        return 0;
    }

    static int RunSmoke(LocalWorld world, string worldPath, int port, string account,
        string moves, string raster) {
        Console.WriteLine("unity player built: no");
        Console.WriteLine("world " + worldPath);
        string password = Environment.GetEnvironmentVariable("GRAAL_PW");
        if (password == null) password = "loopbackpw";
        YardServer server = new YardServer(world);
        try {
            server.Start(port);
        } catch (Exception) {
            Console.WriteLine("state Error reason=connect-failed");
            return 1;
        }
        Console.WriteLine("serve 127.0.0.1:" + server.Port);
        PlayResult result = new YardClient().Play(
            "127.0.0.1", server.Port, account, password, moves, world);
        server.Join();
        Console.Write(result.Log);
        if (result.State != LinkState.InWorld) return 1;
        if (raster != null) {
            PlayerSim sim = new PlayerSim(world);
            sim.X = result.PlayerX;
            sim.Y = result.PlayerY;
            sim.EntityX = result.EntityX;
            sim.EntityY = result.EntityY;
            YardRaster.Write(raster, world, sim, result.Camera);
            Console.WriteLine("raster " + raster);
        }
        if (result.Log.IndexOf(password, StringComparison.Ordinal) >= 0) {
            Console.WriteLine("state Error reason=secret-in-log");
            return 1;
        }
        Console.WriteLine("smoke ok");
        return 0;
    }

    static void PrintList() {
        Console.WriteLine("6.114 Worlds portable player");
        Console.WriteLine("unity player built: no");
        Console.WriteLine("connector token " + ConnectorHello.Token);
        Console.WriteLine("local-only fixture for session, movement, and one entity");
        Console.WriteLine("no IL2CPP player and no Torque");
    }

    static string DefaultWorld() {
        string[] candidates = new string[] {
            Path.Combine("graal-worlds-614-20240421", "worlds", "local-yard.txt"),
            Path.Combine("worlds", "local-yard.txt")
        };
        for (int i = 0; i < candidates.Length; i++) {
            if (File.Exists(candidates[i])) return candidates[i];
        }
        return candidates[0];
    }
}

}
