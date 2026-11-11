using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;

namespace Worlds614 {

/* Local-only yard server. Speaks the connector hello and then LocalFixture
   lines. One accepted client. The entity steps west on the first unblocked
   player move. That step is a fixture, not a 6.114 property update. */
public sealed class YardServer {
    readonly LocalWorld world;
    readonly ManualResetEvent ready = new ManualResetEvent(false);
    TcpListener listener;
    Thread thread;
    public int Port;
    public Exception Fault;

    public YardServer(LocalWorld world) {
        this.world = world;
    }

    public void Start(int port) {
        listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        thread = new Thread(Serve);
        thread.IsBackground = true;
        thread.Start();
        if (!ready.WaitOne(2000)) throw new IOException("server did not bind");
    }

    public void Join() {
        if (thread != null) thread.Join();
    }

    void Serve() {
        ready.Set();
        TcpClient client = null;
        try {
            client = listener.AcceptTcpClient();
            client.ReceiveTimeout = 2000;
            client.SendTimeout = 2000;
            NetworkStream stream = client.GetStream();
            byte[] hello = ReadExact(stream, ConnectorHello.Bytes().Length);
            if (!ConnectorHello.IsHello(hello, hello.Length)) {
                WriteLine(stream, LocalFixture.Error("bad-hello"));
                return;
            }
            string login = ReadLine(stream);
            if (!LocalFixture.IsLocal(login) || login.IndexOf("LOCAL login ", StringComparison.Ordinal) != 0) {
                WriteLine(stream, LocalFixture.Error("bad-line"));
                return;
            }
            WriteLine(stream, LocalFixture.SessionOk());
            string enter = ReadLine(stream);
            if (enter != "LOCAL enter") {
                WriteLine(stream, LocalFixture.Error("bad-line"));
                return;
            }
            PlayerSim sim = new PlayerSim(world);
            WriteLine(stream, LocalFixture.Entered(world.Name, sim.X, sim.Y));
            if (sim.HasEntity)
                WriteLine(stream, LocalFixture.Entity(1, sim.EntityX, sim.EntityY));
            bool nudged = false;
            while (true) {
                string line;
                try {
                    line = ReadLine(stream);
                } catch (IOException) {
                    return;
                }
                if (line == null) return;
                if (!line.StartsWith("LOCAL move dir=", StringComparison.Ordinal)) {
                    WriteLine(stream, LocalFixture.Error("bad-line"));
                    return;
                }
                string dir;
                if (!LocalFixture.TryField(line, "dir", out dir)) {
                    WriteLine(stream, LocalFixture.Error("bad-line"));
                    return;
                }
                int dx, dy;
                if (!PlayerSim.DecodeDir(dir, out dx, out dy)) {
                    WriteLine(stream, LocalFixture.Error("bad-dir"));
                    return;
                }
                StepResult step = sim.TryStep(world, dx, dy);
                if (!step.Blocked && !nudged && sim.HasEntity) {
                    NudgeEntity(sim);
                    nudged = true;
                }
                WriteLine(stream, LocalFixture.You(sim.X, sim.Y, step.Blocked));
                if (sim.HasEntity)
                    WriteLine(stream, LocalFixture.Entity(1, sim.EntityX, sim.EntityY));
            }
        } catch (Exception ex) {
            Fault = ex;
        } finally {
            if (client != null) client.Close();
            listener.Stop();
        }
    }

    void NudgeEntity(PlayerSim sim) {
        int nx = sim.EntityX - 1;
        int ny = sim.EntityY;
        if (world.Wall(nx, ny) || (nx == sim.X && ny == sim.Y)) return;
        sim.EntityX = nx;
        sim.EntityY = ny;
    }

    static void WriteLine(NetworkStream stream, string line) {
        byte[] data = LocalFixture.Encode(line);
        stream.Write(data, 0, data.Length);
    }

    public static byte[] ReadExact(NetworkStream stream, int count) {
        byte[] data = new byte[count];
        int got = 0;
        while (got < count) {
            int n = stream.Read(data, got, count - got);
            if (n <= 0) throw new IOException("short-read");
            got += n;
        }
        return data;
    }

    public static string ReadLine(NetworkStream stream) {
        string text = "";
        while (text.Length < 240) {
            int b = stream.ReadByte();
            if (b < 0) {
                if (text.Length == 0) return null;
                throw new IOException("short-read");
            }
            if (b == '\n') return text;
            if (b != '\r') text += (char)b;
        }
        throw new IOException("long-line");
    }
}

}
