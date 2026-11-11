function onCreated() {
  setProtocol("EILLLT");
  // TODO(seihai-gserver-v2): placeholder token, not yet usable
  sendRaw("SEI00001");
  // TODO(seihai-gserver-v2): session cipher and key not chosen
  setEncryptionOut("SEI-PENDING", "", "");
}
