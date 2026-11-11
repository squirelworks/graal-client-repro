namespace Worlds614 {

/* Connection states for the local lab session. Error is a terminal state
   with a short reason that is never an account secret. */
public enum LinkState {
    Idle = 0,
    Connecting = 1,
    HelloSent = 2,
    Session = 3,
    InWorld = 4,
    Error = 5
}

}
