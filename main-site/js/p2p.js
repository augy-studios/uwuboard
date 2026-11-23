// Host and guest pairing over PeerJS, STUN only. The reference module from
// docs/STUN-p2p-spec.md, which says why each rule below is there.
// Plain script: this project does not use ES modules, so exports go on window.P2P.
(function () {
  const PEERJS_URL = "https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js";
  const PEER_PREFIX = "uwuboard-sync-";
  const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";
  const CODE_LENGTH = 6;
  const PROTOCOL_VERSION = 1;
  const CONNECT_TIMEOUT_MS = 15000;

  // STUN only. Supplying `config` replaces PeerJS's default, which includes a
  // public TURN relay.
  const ICE_SERVERS = [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun.cloudflare.com:3478" },
  ];
  const PEER_OPTIONS = { debug: 0, config: { iceServers: ICE_SERVERS } };

  const BROKER_ERRORS = new Set([
    "network", "server-error", "socket-error", "socket-closed", "disconnected",
  ]);

  /* ---- codes ---- */

  // A random pairing code of CODE_LENGTH characters from CODE_ALPHABET, every character
  // equally likely.
  function generateCode() {
    // Bytes at or above this would make some characters likelier than others.
    const limit = 256 - (256 % CODE_ALPHABET.length);
    let code = "";
    while (code.length < CODE_LENGTH) {
      const [byte] = crypto.getRandomValues(new Uint8Array(1));
      if (byte < limit) {
        code = code + CODE_ALPHABET[byte % CODE_ALPHABET.length];
      }
    }
    return code;
  }

  // What somebody typed, as a code: capital letters and digits only, at most CODE_LENGTH of them.
  function normaliseCode(input) {
    let text = input;
    if (!text) {
      text = "";
    }
    return String(text).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LENGTH);
  }

  function isValidCode(input) {
    const code = normaliseCode(input);
    return code.length === CODE_LENGTH && [...code].every((character) => {
      return CODE_ALPHABET.includes(character);
    });
  }

  /* ---- library ---- */

  // Loaded only when somebody starts a sync, so the rest of the app never waits on it.
  let peerLibrary = null;

  // Resolves with PeerJS's Peer class, adding its script to the page the first time.
  function loadPeerJs() {
    if (peerLibrary) {
      return Promise.resolve(peerLibrary);
    }
    if (window.Peer) {
      peerLibrary = window.Peer;
      return Promise.resolve(peerLibrary);
    }

    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = PEERJS_URL;
      script.async = true;
      script.onload = () => {
        if (window.Peer) {
          peerLibrary = window.Peer;
          resolve(peerLibrary);
        } else {
          reject(new Error("PeerJS did not define Peer"));
        }
      };
      script.onerror = () => {
        reject(new Error('Could not load PeerJS'));
      };
      document.head.appendChild(script);
    });
  }

  // A PeerJS error, as a sentence to show the person.
  function describePeerError(error) {
    switch (errorTypeOf(error)) {
      case "peer-unavailable":
        return 'Nobody is showing that code. Check it and try again.';
      case "unavailable-id":
        return 'That code is already in use. Generate a new one.';
      case "network":
      case "server-error":
      case "socket-error":
      case "socket-closed":
        return 'Cannot reach the pairing service. Everything else still works.';
      case "browser-incompatible":
        return 'This browser cannot make peer-to-peer connections.';
      default:
        return 'The connection failed.';
    }
  }

  // The `type` of a PeerJS error, or undefined when there is no error object.
  function errorTypeOf(error) {
    if (error === null || error === undefined) {
      return undefined;
    }
    return error.type;
  }

  /* ---- shared ---- */

  // What the host and the guest have in common: a PeerJS peer, a status, and the events
  // ("status", "message") the rest of the app listens for.
  class Connection extends EventTarget {
    constructor() {
      super();
      this.peer = null;
      this.status = "idle";
    }

    setStatus(status, detail = {}) {
      this.status = status;
      this.dispatchEvent(new CustomEvent("status", { detail: { status, ...detail } }));
    }

    // Wires up one data channel to the other device: its opening, its messages and its closing.
    bindLink(link) {
      // A link that closes without ever opening never reached the other device.
      let everOpened = false;
      let finished = false;
      const finish = () => {
        if (finished) {
          return;
        }
        finished = true;
        this.onLinkClosed(link, everOpened);
      };

      link.on("open", () => {
        everOpened = true;
        this.onLinkOpen(link);
      });
      link.on("data", (message) => {
        if (!message || typeof message !== "object" || typeof message.type !== "string") {
          return;
        }
        this.dispatchEvent(new CustomEvent("message", { detail: { message, from: link.peer } }));
      });
      link.on("close", finish);
      link.on("error", finish);
    }

    // The broker socket can drop while channels stay up. Re-register under the
    // same id, backing off while it keeps failing.
    watchBroker() {
      const peer = this.peer;
      let delay = 1000;
      peer.on("open", () => {
        delay = 1000;
      });
      peer.on("disconnected", () => {
        setTimeout(() => {
          if (this.peer === peer && !peer.destroyed && peer.disconnected) {
            peer.reconnect();
          }
        }, delay);
        delay = Math.min(delay * 2, 30000);
      });
    }

    destroyPeer() {
      // Cleared first, so the disconnect that destroy() causes is not retried.
      const peer = this.peer;
      this.peer = null;
      if (peer !== null && peer !== undefined) {
        peer.destroy();
      }
    }
  }

  /* ---- host ---- */

  // The device showing the code: it registers under the code and waits for guests to connect.
  class Host extends Connection {
    constructor({ maxGuests = 1 } = {}) {
      super();
      this.maxGuests = maxGuests;
      this.links = new Map(); // guest peer id -> open link
    }

    // Registers with the broker under `code` and starts accepting guests.
    async start(code) {
      const Peer = await loadPeerJs();
      this.code = code;
      this.setStatus("connecting");

      this.peer = new Peer(PEER_PREFIX + code, PEER_OPTIONS);
      this.watchBroker();

      this.peer.on("open", () => {
        this.refreshStatus();
      });
      this.peer.on("connection", (link) => {
        if (this.maxGuests === 1) {
          // The newcomer replaces the incumbent.
          for (const oldLink of [...this.links.values()]) {
            this.drop(oldLink);
          }
        } else if (this.links.size >= this.maxGuests) {
          link.on("open", () => {
            link.send({ type: "full" });
            link.close({ flush: true });
          });
          return;
        }
        this.bindLink(link);
      });
      this.peer.on("error", (error) => {
        if (errorTypeOf(error) === "unavailable-id") {
          this.setStatus("error", { message: describePeerError(error), taken: true });
          return;
        }
        // Guests already attached do not need the broker.
        if (this.links.size > 0 && BROKER_ERRORS.has(errorTypeOf(error))) {
          return;
        }
        this.setStatus("error", { message: describePeerError(error) });
      });
    }

    onLinkOpen(link) {
      this.links.set(link.peer, link);
      this.dispatchEvent(new CustomEvent("join", { detail: { id: link.peer, metadata: link.metadata } }));
      this.refreshStatus();
    }

    onLinkClosed(link) {
      // Links this end dropped, and links that never opened, are not in the map.
      if (this.links.get(link.peer) !== link) {
        return;
      }
      this.links.delete(link.peer);
      this.dispatchEvent(new CustomEvent("leave", { detail: { id: link.peer } }));
      this.refreshStatus();
    }

    // A guest that dropped and one that never came look the same from here.
    refreshStatus() {
      if (this.links.size > 0) {
        this.setStatus("connected");
      } else {
        this.setStatus("waiting");
      }
    }

    // Removed before closing: close() emits "close" synchronously.
    drop(link) {
      this.links.delete(link.peer);
      link.close();
    }

    // To one guest when `to` is given, otherwise to all of them.
    send(message, to) {
      for (const [id, link] of this.links) {
        if (to && id !== to) {
          continue;
        }
        try {
          link.send(message);
        } catch {
          // Closed between the check and the send; its close handler reports it.
        }
      }
    }

    close() {
      for (const link of [...this.links.values()]) {
        this.drop(link);
      }
      this.destroyPeer();
      this.setStatus("idle");
    }
  }

  /* ---- guest ---- */

  // The device entering the code: it connects to the host registered under it.
  class Guest extends Connection {
    constructor() {
      super();
      this.link = null;
      this.timer = null;
    }

    // Asks the broker for a channel to the host showing `code`, giving up after
    // CONNECT_TIMEOUT_MS if no path between the two devices turns up.
    async connect(code, metadata) {
      const Peer = await loadPeerJs();
      this.setStatus("connecting");

      this.peer = new Peer(PEER_OPTIONS);
      this.watchBroker();

      // Nothing errors when ICE cannot find a path; it just keeps trying.
      this.timer = setTimeout(() => {
        if (this.status !== "connecting") {
          return;
        }
        this.hangUp();
        this.setStatus("unreachable");
      }, CONNECT_TIMEOUT_MS);

      // once, not on: a broker reconnect fires "open" again.
      this.peer.once("open", () => {
        this.link = this.peer.connect(PEER_PREFIX + code, { reliable: true, metadata });
        this.bindLink(this.link);
      });
      this.peer.on("error", (error) => {
        if (this.status === "connected" && BROKER_ERRORS.has(errorTypeOf(error))) {
          return;
        }
        this.hangUp();
        this.setStatus("error", { message: describePeerError(error) });
      });
    }

    onLinkOpen(link) {
      if (link !== this.link) {
        return;
      }
      clearTimeout(this.timer);
      this.setStatus("connected");
      this.send({ type: "hello", v: PROTOCOL_VERSION });
    }

    onLinkClosed(link, everOpened) {
      if (link !== this.link) {
        return;
      }
      this.link = null;
      if (everOpened) {
        this.setStatus("dropped");
      } else {
        this.setStatus("unreachable");
      }
    }

    send(message) {
      if (this.link === null || this.link === undefined || !this.link.open) {
        return;
      }
      try {
        this.link.send(message);
      } catch {
        // As on the host.
      }
    }

    // Leaving on purpose: `bye` first, and a flushed close so it arrives.
    leave() {
      this.send({ type: "bye" });
      clearTimeout(this.timer);
      const link = this.link;
      const peer = this.peer;
      this.link = null;
      this.peer = null;
      if (link !== null && link !== undefined) {
        link.close({ flush: true });
      }
      setTimeout(() => {
        if (peer !== null && peer !== undefined) {
          peer.destroy();
        }
      }, 1000);
      this.setStatus("idle");
    }

    hangUp() {
      clearTimeout(this.timer);
      const link = this.link;
      this.link = null;
      if (link !== null && link !== undefined) {
        link.close();
      }
      this.destroyPeer();
    }

    close() {
      this.hangUp();
      this.setStatus("idle");
    }
  }

  window.P2P = { Host, Guest, generateCode, normaliseCode, isValidCode, CODE_LENGTH, PROTOCOL_VERSION };
})();
