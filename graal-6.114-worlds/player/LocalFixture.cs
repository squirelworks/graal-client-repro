using System;
using System.Globalization;
using System.Text;

namespace Worlds614 {

/* LOCAL-ONLY fixture lines. Not a v7 frame, not a 6.114 packet, and not
   compatible with the classic PLO/PLI table. Every line is ASCII, ends
   with '\n', and starts with "LOCAL ". Account secrets are not a field.
   The password is represented by its length only. */
public static class LocalFixture {
    public const string Prefix = "LOCAL ";

    public static string Login(string account, int passwordLength) {
        return "LOCAL login account=" + Token(account) +
            " password-length=" + passwordLength.ToString(CultureInfo.InvariantCulture);
    }

    public static string Enter() {
        return "LOCAL enter";
    }

    public static string Move(string dir) {
        return "LOCAL move dir=" + Token(dir);
    }

    public static string SessionOk() {
        return "LOCAL ok session";
    }

    public static string Entered(string world, int x, int y) {
        return "LOCAL enter world=" + Token(world) + " x=" + x.ToString(CultureInfo.InvariantCulture) +
            " y=" + y.ToString(CultureInfo.InvariantCulture);
    }

    public static string Entity(int id, int x, int y) {
        return "LOCAL entity id=" + id.ToString(CultureInfo.InvariantCulture) +
            " x=" + x.ToString(CultureInfo.InvariantCulture) +
            " y=" + y.ToString(CultureInfo.InvariantCulture);
    }

    public static string You(int x, int y, bool blocked) {
        return "LOCAL you x=" + x.ToString(CultureInfo.InvariantCulture) +
            " y=" + y.ToString(CultureInfo.InvariantCulture) +
            " blocked=" + (blocked ? "1" : "0");
    }

    public static string Error(string reason) {
        return "LOCAL error reason=" + Token(reason);
    }

    public static bool IsLocal(string line) {
        return line != null && line.StartsWith(Prefix, StringComparison.Ordinal);
    }

    public static string Token(string text) {
        if (text == null || text.Length == 0) throw new FormatException("empty token");
        for (int i = 0; i < text.Length; i++) {
            char c = text[i];
            bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
            if (!ok) throw new FormatException("token");
        }
        return text;
    }

    public static bool TryField(string line, string key, out string value) {
        value = null;
        string needle = key + "=";
        int at = line.IndexOf(needle, StringComparison.Ordinal);
        if (at < 0) return false;
        int start = at + needle.Length;
        int end = start;
        while (end < line.Length && line[end] != ' ') end++;
        value = line.Substring(start, end - start);
        return value.Length > 0;
    }

    public static bool TryInt(string line, string key, out int value) {
        value = 0;
        string text;
        if (!TryField(line, key, out text)) return false;
        return int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value);
    }

    public static byte[] Encode(string line) {
        return Encoding.ASCII.GetBytes(line + "\n");
    }
}

}
