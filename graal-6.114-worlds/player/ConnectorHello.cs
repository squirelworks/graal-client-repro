using System.Text;

namespace Worlds614 {

/* Documented connector hello. A running 6.113 client sends these eight
   bytes before it reads the server (Graal_analysis
   protocol/v6113-list-capture.md). This host uses that token. It is not
   marked provisional. The 6.114 image was not shown to store the literal,
   and the bytes after the token in that 6.113 capture are unidentified
   ciphertext. This type sends only the eight bytes. It does not add the
   6.113 header, a zlib member, a cipher, or a 6.0x type-5 login. */
public static class ConnectorHello {
    public const string Token = "GNP1905C";

    public static byte[] Bytes() {
        return Encoding.ASCII.GetBytes(Token);
    }

    public static bool IsHello(byte[] data, int count) {
        byte[] hello = Bytes();
        if (data == null || count < hello.Length) return false;
        for (int i = 0; i < hello.Length; i++) {
            if (data[i] != hello[i]) return false;
        }
        return true;
    }
}

}
