function onCreated() {
  setProtocol("EILLLT");
  // TODO(seihai-gserver-v2): shared Worlds placeholder token, not yet usable
  sendRaw("SEIWRLD1");
  // TODO(seihai-gserver-v2): session cipher and key not chosen
  setEncryptionOut("SEI-PENDING", "", "");
}
