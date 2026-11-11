using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Worlds614 {

public sealed class PlayResult {
    public LinkState State = LinkState.Idle;
    public string Reason = "";
    public int PlayerX;
    public int PlayerY;
    public bool LastBlocked;
    public bool SawEntity;
    public int EntityX;
    public int EntityY;
    public string Log = "";
    public byte[] Sent = new byte[0];
    public byte[] Got = new byte[0];
    public CameraView Camera;
    public string View = "";
}

/* Lab client. Loopback only. Writes the documented eight-byte hello, then
   local-only fixture lines. The password is counted and never written. */
public sealed class YardClient {
    readonly StringBuilder log = new StringBuilder();
    readonly MemoryStream sent = new MemoryStream();
    readonly MemoryStream got = new MemoryStream();

    public PlayResult Play(string host, int port, string account, string password,
        string moves, LocalWorld world) {
        PlayResult result = new PlayResult();
        if (!Loopback(host)) {
            Fail(result, "refused-host");
            return result;
        }
        if (account == null || account.Length == 0) {
            Fail(result, "missing-account");
            return result;
        }
        if (port <= 0 || port > 65535) {
            Fail(result, "port-out-of-range");
            return result;
        }
        int passwordLength = password == null ? 0 : password.Length;
        Note(result, "state Connecting");
        result.State = LinkState.Connecting;
        TcpClient client = new TcpClient();
        try {
            client.ReceiveTimeout = 2000;
            client.SendTimeout = 2000;
            client.Connect(IPAddress.Loopback, port);
            NetworkStream stream = client.GetStream();
            WriteRaw(stream, ConnectorHello.Bytes());
            result.State = LinkState.HelloSent;
            Note(result, "state HelloSent");
            Note(result, "connector token " + ConnectorHello.Token);
            Note(result, "local-only fixture");
            string login = LocalFixture.Login(account, passwordLength);
            WriteRaw(stream, LocalFixture.Encode(login));
            Note(result, "account " + account + " password-length " + passwordLength.ToString());
            string ok = ReadGot(stream);
            if (ok != "LOCAL ok session") {
                Fail(result, Classify(ok));
                return result;
            }
            result.State = LinkState.Session;
            Note(result, "state Session");
            WriteRaw(stream, LocalFixture.Encode(LocalFixture.Enter()));
            string entered = ReadGot(stream);
            if (entered == null || !entered.StartsWith("LOCAL enter ", StringComparison.Ordinal)) {
                Fail(result, Classify(entered));
                return result;
            }
            int x, y;
            if (!LocalFixture.TryInt(entered, "x", out x) || !LocalFixture.TryInt(entered, "y", out y)) {
                Fail(result, "bad-line");
                return result;
            }
            PlayerSim sim = new PlayerSim(world);
            sim.X = x;
            sim.Y = y;
            if (world.HasEntity) {
                string entity = ReadGot(stream);
                int id, ex, ey;
                if (entity == null || !entity.StartsWith("LOCAL entity ", StringComparison.Ordinal) ||
                    !LocalFixture.TryInt(entity, "id", out id) ||
                    !LocalFixture.TryInt(entity, "x", out ex) ||
                    !LocalFixture.TryInt(entity, "y", out ey)) {
                    Fail(result, Classify(entity));
                    return result;
                }
                sim.HasEntity = true;
                sim.EntityX = ex;
                sim.EntityY = ey;
                result.SawEntity = true;
                result.EntityX = ex;
                result.EntityY = ey;
                Note(result, "entity id=" + id + " x=" + ex + " y=" + ey);
            }
            result.State = LinkState.InWorld;
            result.PlayerX = sim.X;
            result.PlayerY = sim.Y;
            Note(result, "state InWorld");
            Note(result, "you x=" + sim.X + " y=" + sim.Y + " blocked=0");
            if (moves != null && moves.Length > 0) {
                string[] steps = moves.Split(',');
                for (int i = 0; i < steps.Length; i++) {
                    string dir = steps[i].Trim();
                    if (dir.Length == 0) continue;
                    int dx, dy;
                    if (!PlayerSim.DecodeDir(dir, out dx, out dy)) {
                        Fail(result, "bad-dir");
                        return result;
                    }
                    WriteRaw(stream, LocalFixture.Encode(LocalFixture.Move(dir)));
                    string you = ReadGot(stream);
                    int mx, my, blocked;
                    if (you == null || !you.StartsWith("LOCAL you ", StringComparison.Ordinal) ||
                        !LocalFixture.TryInt(you, "x", out mx) ||
                        !LocalFixture.TryInt(you, "y", out my) ||
                        !LocalFixture.TryInt(you, "blocked", out blocked)) {
                        Fail(result, Classify(you));
                        return result;
                    }
                    sim.X = mx;
                    sim.Y = my;
                    result.PlayerX = mx;
                    result.PlayerY = my;
                    result.LastBlocked = blocked != 0;
                    Note(result, "you x=" + mx + " y=" + my + " blocked=" + blocked);
                    if (sim.HasEntity) {
                        string entity = ReadGot(stream);
                        int id, ex, ey;
                        if (entity == null || !LocalFixture.TryInt(entity, "id", out id) ||
                            !LocalFixture.TryInt(entity, "x", out ex) ||
                            !LocalFixture.TryInt(entity, "y", out ey)) {
                            Fail(result, Classify(entity));
                            return result;
                        }
                        sim.EntityX = ex;
                        sim.EntityY = ey;
                        result.EntityX = ex;
                        result.EntityY = ey;
                        Note(result, "entity id=" + id + " x=" + ex + " y=" + ey);
                    }
                }
            }
            result.Camera = PlayerSim.Camera(world, sim.X, sim.Y, 5, 5);
            result.View = PlayerSim.CameraText(world, sim, result.Camera);
            Note(result, "camera " + result.Camera.OriginX + "," + result.Camera.OriginY +
                " " + result.Camera.Width + "x" + result.Camera.Height);
            Note(result, "local-only view");
            Note(result, result.View.TrimEnd('\n'));
            result.Log = log.ToString();
            result.Sent = sent.ToArray();
            result.Got = got.ToArray();
            return result;
        } catch (SocketException) {
            Fail(result, "connect-failed");
            return result;
        } catch (IOException) {
            Fail(result, "short-read");
            return result;
        } catch (FormatException) {
            Fail(result, "bad-token");
            return result;
        } finally {
            client.Close();
        }
    }

    static bool Loopback(string host) {
        return host == "127.0.0.1";
    }

    void WriteRaw(NetworkStream stream, byte[] data) {
        stream.Write(data, 0, data.Length);
        sent.Write(data, 0, data.Length);
    }

    string ReadGot(NetworkStream stream) {
        string line = YardServer.ReadLine(stream);
        if (line != null) {
            byte[] data = LocalFixture.Encode(line);
            got.Write(data, 0, data.Length);
        }
        return line;
    }

    void Note(PlayResult result, string line) {
        log.Append(line);
        log.Append('\n');
        result.Log = log.ToString();
    }

    void Fail(PlayResult result, string reason) {
        result.State = LinkState.Error;
        result.Reason = reason;
        Note(result, "state Error reason=" + reason);
        result.Sent = sent.ToArray();
        result.Got = got.ToArray();
    }

    static string Classify(string line) {
        if (line == null) return "short-read";
        string reason;
        if (LocalFixture.IsLocal(line) && LocalFixture.TryField(line, "reason", out reason))
            return reason;
        return "bad-line";
    }
}

}
