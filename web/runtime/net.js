// net.js — EMRAPI.Multiplayer no navegador, com o SDK JavaScript oficial do Photon Realtime
// (mesmo App ID do app). Usa a porta 443 (passa por qualquer rede/proxy).
// Os eventos chegam numa fila e o Lua busca a cada frame (H_mppoll), como no app.
/* global EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});
  const N = {};
  W.net = N;

  let client = null;
  let nick = 'Player';
  const queue = [];
  let connectCb = 0, joinCb = 0, leaveCb = 0;
  let lastMaster = -1;
  let wasConnected = false;

  function LBC() { return window.Photon.LoadBalancing.LoadBalancingClient; }
  function push(kind, a, b, c) { queue.push([kind, a || 0, b === undefined ? '' : String(b), c === undefined ? '' : String(c)]); }
  function cb(id, ok, err) { if (id) push('cb', id, ok ? '1' : '0', err || ''); }

  function inRoom() { return !!(client && client.isJoinedToRoom()); }

  function makeClient(appId) {
    const P = window.Photon;
    const C = LBC();
    const ver = 'web-' + (W.app.id || 'app') + '-' + (W.app.version || '1');
    const c = new C(P.ConnectionProtocol.Wss, appId, ver);
    try { c.setLogLevel(P.LogLevel.ERROR); } catch (e) { /* ok */ }
    c.setNameServerAddress('wss://ns.photonengine.io:443');
    c.setUserId(nick + '-' + Math.floor(Math.random() * 1e6));
    c.myActor().setName(nick);
    c.onStateChange = function (st) {
      if (st === C.State.ConnectedToMaster || st === C.State.JoinedLobby) {
        wasConnected = true;
        if (connectCb) { const id = connectCb; connectCb = 0; cb(id, true); }
        if (leaveCb) { const id = leaveCb; leaveCb = 0; cb(id, true); }
      } else if (st === C.State.Joined) {
        lastMaster = c.myRoom().masterClientId;
        if (joinCb) { const id = joinCb; joinCb = 0; cb(id, true); }
      } else if (st === C.State.Disconnected || st === C.State.Error) {
        if (connectCb) { const id = connectCb; connectCb = 0; cb(id, false, 'desconectado'); }
        if (joinCb) { const id = joinCb; joinCb = 0; cb(id, false, 'desconectado'); }
        if (wasConnected) { wasConnected = false; push('disconnected', 0, 'disconnected'); }
      }
    };
    c.onError = function (code, msg) {
      if (connectCb) { const id = connectCb; connectCb = 0; cb(id, false, String(msg || code)); }
      if (joinCb) { const id = joinCb; joinCb = 0; cb(id, false, String(msg || code)); }
      W.log(2, 'Photon: ' + code + ' ' + msg);
    };
    c.onEvent = function (code, content, actorNr) {
      if (code === 1 && content && typeof content === 'object') push('event', actorNr, content.k, content.d);
      else if (code === 2 && content) push('roomprop', 0, content.k, content.v);
    };
    c.onActorJoin = function (a) {
      if (a.actorNr === c.myActor().actorNr) return;
      push('join', a.actorNr, a.name || ('p' + a.actorNr));
    };
    c.onActorLeave = function (a) {
      if (a.actorNr === c.myActor().actorNr) return;
      push('left', a.actorNr, a.name || ('p' + a.actorNr));
    };
    c.onActorPropertiesChange = function (a) {
      const props = a.getCustomProperties ? a.getCustomProperties() : {};
      for (const k in props) push('playerprop', a.actorNr, k, props[k]);
    };
    c.onMyRoomPropertiesChange = function () {
      const props = c.myRoom().getCustomProperties();
      for (const k in props) push('roomprop', 0, k, props[k]);
    };
    return c;
  }

  function connect(appId, id) {
    if (!window.Photon) { cb(id, false, 'Photon SDK ausente'); return; }
    if (!appId) { cb(id, false, 'sem photonAppId'); return; }
    if (client) { try { client.disconnect(); } catch (e) { /* ok */ } }
    client = makeClient(appId);
    connectCb = id;
    client.connectToRegionMaster(W.app.photonRegion || 'eu');
  }

  N.update = function () {
    if (!inRoom()) return;
    const m = client.myRoom().masterClientId;
    if (m !== lastMaster) { lastMaster = m; push('master', m); }
  };

  function state() {
    if (!client) return 'offline';
    if (inRoom()) return 'inroom';
    if (connectCb) return 'connecting';
    if (joinCb) return 'joining';
    return client.isConnectedToMaster() ? 'connected' : 'offline';
  }

  N.register = function () {
    const { reg, lua } = W;
    // H_mp(op, texto, n1, n2, payload)
    reg('H_mp', (Ls) => {
      const op = lua.str(Ls, 1), s = lua.str(Ls, 2) || '';
      const n1 = lua.int(Ls, 3), n2 = lua.int(Ls, 4);
      const payload = lua.isnone(Ls, 5) ? '' : (lua.str(Ls, 5) || '');
      if (op === 'nick') { nick = s || nick; if (client) client.myActor().setName(nick); }
      else if (op === 'connect') connect(W.app.photonAppId, n1);
      else if (op === 'connectid') connect(s, n1);
      else if (op === 'disconnect') { if (client) client.disconnect(); }
      else if (op === 'random') {
        if (!client || !client.isConnectedToMaster()) { cb(n1, false, 'nao conectado'); return; }
        joinCb = n1;
        client.joinRandomOrCreateRoom({}, null, { maxPlayers: n2 || 8 });
      } else if (op === 'create') {
        joinCb = n1; client.createRoom(s, { maxPlayers: n2 || 8 });
      } else if (op === 'join') {
        joinCb = n1; client.joinRoom(s);
      } else if (op === 'joinorcreate') {
        joinCb = n1; client.joinRoom(s, { createIfNotExists: true }, { maxPlayers: n2 || 8 });
      } else if (op === 'leave') {
        if (inRoom()) { leaveCb = n1; client.leaveRoom(); } else cb(n1, true);
      } else if (op === 'roomlist') {
        const list = client ? client.availableRooms().map((r) => ({ name: r.name, players: r.playerCount, maxPlayers: r.maxPlayers })) : [];
        cb(n1, true, JSON.stringify(list));
      } else if (op === 'send') {
        if (inRoom()) client.raiseEvent(1, { k: s, d: payload });
      } else if (op === 'sendto') {
        if (inRoom()) client.raiseEvent(1, { k: s, d: payload }, { targetActors: [n1] });
      } else if (op === 'roomprop') {
        if (inRoom()) client.myRoom().setCustomProperty(s, payload);
      } else if (op === 'playerprop') {
        if (client) client.myActor().setCustomProperty(s, payload);
      }
    });
    reg('H_mpq', (Ls) => {
      const q = lua.str(Ls, 1) || '';
      let r = '';
      if (q === 'connected') r = client && (client.isConnectedToMaster() || inRoom()) ? '1' : '0';
      else if (q === 'state') r = state();
      else if (q === 'inroom') r = inRoom() ? '1' : '0';
      else if (q === 'room') r = inRoom() ? client.myRoom().name : '';
      else if (q === 'count') r = String(inRoom() ? client.myRoomActorsArray().length : 0);
      else if (q === 'master') r = inRoom() && client.myRoom().masterClientId === client.myActor().actorNr ? '1' : '0';
      else if (q === 'actor') r = String(inRoom() ? client.myActor().actorNr : -1);
      else if (q === 'players') {
        const me = inRoom() ? client.myActor().actorNr : -1;
        const m = inRoom() ? client.myRoom().masterClientId : -1;
        r = JSON.stringify(inRoom() ? client.myRoomActorsArray().map((a) => ({ actor: a.actorNr, nick: a.name || '', isMaster: a.actorNr === m, isLocal: a.actorNr === me })) : []);
      } else if (q.startsWith('roomprop:')) {
        const v = inRoom() ? client.myRoom().getCustomProperty(q.slice(9)) : undefined;
        r = v === undefined || v === null ? '' : String(v);
      } else if (q.startsWith('playerprop:')) {
        const parts = q.split(':');
        const a = inRoom() ? client.myRoomActors()[parseInt(parts[1], 10)] : null;
        const v = a ? a.getCustomProperty(parts.slice(2).join(':')) : undefined;
        r = v === undefined || v === null ? '' : String(v);
      }
      lua.pushS(Ls, r);
      return 1;
    });
    reg('H_mppoll', (Ls) => {
      const e = queue.shift();
      if (!e) { lua.pushNil(Ls); return 1; }
      lua.pushS(Ls, e[0]); lua.pushN(Ls, e[1]); lua.pushS(Ls, e[2]); lua.pushS(Ls, e[3]);
      return 4;
    });
  };
})();
