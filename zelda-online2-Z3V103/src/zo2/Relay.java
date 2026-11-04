package zo2;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Vector;

/**
 * A text-line connection to the GServ lobby. A reader thread collects
 * complete lines; the game takes them on its own tick with poll().
 */
public class Relay {
  Socket socket;
  OutputStream out;
  Vector lines = new Vector();
  volatile boolean closed;

  public Relay(String host, int port, int timeoutMs) throws IOException {
    socket = new Socket();
    socket.connect(new InetSocketAddress(host, port), timeoutMs);
    socket.setTcpNoDelay(true);
    out = socket.getOutputStream();
    Thread t = new Thread() {
      public void run() { readLoop(); }
    };
    t.setDaemon(true);
    t.start();
  }

  void readLoop() {
    try {
      InputStream in = socket.getInputStream();
      StringBuffer line = new StringBuffer();
      int c;
      while ((c = in.read()) >= 0) {
        if (c == '\n') {
          synchronized (lines) { lines.addElement(line.toString()); }
          line.setLength(0);
        } else if (line.length() < 4096) {
          line.append((char) c);
        }
      }
    } catch (IOException e) {
      // closed
    }
    closed = true;
  }

  public void send(String line) {
    if (closed) return;
    try {
      out.write((line + "\n").getBytes("ISO-8859-1"));
      out.flush();
    } catch (IOException e) {
      closed = true;
    }
  }

  /** The next received line, or null. */
  public String poll() {
    synchronized (lines) {
      if (lines.isEmpty()) return null;
      String l = (String) lines.elementAt(0);
      lines.removeElementAt(0);
      return l;
    }
  }

  public boolean isClosed() {
    return closed;
  }

  public void close() {
    closed = true;
    try { socket.close(); } catch (IOException e) { }
  }
}
