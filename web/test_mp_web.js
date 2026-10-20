// test_mp_web.js — teste ONLINE da versao HTML do Brainrot: duas abas do Chromium,
// cada uma com o jogo inteiro, ligadas por um "Photon falso" (relay neste script).
// Valida net.js + EMRAPI.Multiplayer + o jogo: sala, mestre, bases, esteira e poses.
// (O SDK real do Photon foi testado a parte com a nuvem de verdade.)
const path = require('path');
const { chromium } = require(process.env.PW_PATH || 'playwright');
const file = path.resolve(process.argv[2] || 'web/dist/StealABrainrotVR.html');
const secs = parseFloat(process.argv[3] || '25');

// Photon falso injetado antes da pagina (substitui window.Photon)
function fakePhoton() {
  const State = { Uninitialized: 0, ConnectingToNameServer: 1, ConnectedToNameServer: 2, ConnectingToMasterserver: 3, ConnectedToMaster: 4, JoinedLobby: 5, ConnectingToGameserver: 6, ConnectedToGameserver: 7, Joined: 8, Disconnecting: 9, Disconnected: 10, Error: -1 };
  const actors = {};
  const room = { name: 'fakeroom', masterClientId: 1, props: {}, setCustomProperty(k, v) { this.props[k] = v; }, getCustomProperty(k) { return this.props[k]; }, getCustomProperties() { return this.props; } };
  let me = null;
  class LBC {
    constructor() { this.joined = false; this.connected = false; me = this; this.actor = { actorNr: 0, name: '', props: {}, setName(n) { this.name = n; }, setCustomProperty(k, v) { this.props[k] = v; }, getCustomProperty(k) { return this.props[k]; }, getCustomProperties() { return this.props; } }; }
    setLogLevel() {} setNameServerAddress() {} setUserId() {}
    myActor() { return this.actor; }
    myRoom() { return room; }
    myRoomActorsArray() { return Object.values(actors); }
    myRoomActors() { return actors; }
    availableRooms() { return []; }
    isJoinedToRoom() { return this.joined; }
    isConnectedToMaster() { return this.connected; }
    connectToRegionMaster() { setTimeout(() => { this.connected = true; this.onStateChange(State.ConnectedToMaster); }, 50); }
    joinRandomOrCreateRoom() {
      window.__relay('join', JSON.stringify({ name: this.actor.name }));
    }
    raiseEvent(code, content, opts) { window.__relay('event', JSON.stringify({ code, content, to: opts && opts.targetActors })); }
    leaveRoom() { this.joined = false; }
    disconnect() { this.connected = false; }
  }
  LBC.State = State;
  LBC.StateToName = (s) => String(s);
  window.__fromRelay = function (kind, json) {
    const d = JSON.parse(json);
    if (kind === 'welcome') {
      me.actor.actorNr = d.actor;
      room.masterClientId = d.master;
      for (const a of d.actors) actors[a.actorNr] = { actorNr: a.actorNr, name: a.name };
      actors[d.actor] = me.actor;
      me.joined = true;
      me.onStateChange(State.Joined);
    } else if (kind === 'joined') {
      actors[d.actorNr] = { actorNr: d.actorNr, name: d.name };
      me.onActorJoin(actors[d.actorNr]);
    } else if (kind === 'event') {
      me.onEvent(d.code, d.content, d.from);
    }
  };
  const fake = { LoadBalancing: Object.freeze({ LoadBalancingClient: LBC }), ConnectionProtocol: Object.freeze({ Wss: 1 }), LogLevel: Object.freeze({ ERROR: 1 }) };
  Object.freeze(fake);   // o SDK real tenta escrever aqui; fica so o falso
  Object.defineProperty(window, 'Photon', { get: () => fake, set: () => {}, configurable: false });
}

(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
  const pages = [];
  const info = []; // { page, actor, name }
  let nextActor = 1;
  const errors = [];
  async function openClient(tag) {
    const ctx = await browser.newContext({ viewport: { width: 960, height: 540 } });
    const page = await ctx.newPage();
    // o SDK real do Photon reclama do objeto falso congelado: e efeito do teste, nao do jogo
    page.on('pageerror', (e) => { if (!/Class extends value undefined/.test(e.message)) errors.push(tag + ' pageerror: ' + e.message); });
    page.on('console', (m) => { if (m.type() === 'error') errors.push(tag + ': ' + m.text()); });
    await page.addInitScript(fakePhoton);
    const me = { page, actor: 0, name: tag };
    await page.exposeFunction('__relay', async (kind, json) => {
      const d = JSON.parse(json);
      if (kind === 'join') {
        me.actor = nextActor++;
        me.name = d.name || tag;
        const actors = info.filter((x) => x.actor).map((x) => ({ actorNr: x.actor, name: x.name }));
        info.push(me);
        await page.evaluate(([k, j]) => window.__fromRelay(k, j), ['welcome', JSON.stringify({ actor: me.actor, master: 1, actors })]);
        for (const o of info) if (o !== me) await o.page.evaluate(([k, j]) => window.__fromRelay(k, j), ['joined', JSON.stringify({ actorNr: me.actor, name: me.name })]);
      } else if (kind === 'event') {
        for (const o of info) {
          if (o === me) continue;
          if (d.to && !d.to.includes(o.actor)) continue;
          o.page.evaluate(([k, j]) => window.__fromRelay(k, j), ['event', JSON.stringify({ code: d.code, content: d.content, from: me.actor })]).catch(() => {});
        }
      }
    });
    await page.goto('file://' + file);
    await page.waitForFunction(() => window.EMRWEB && window.EMRWEB.go, null, { timeout: 60000 });
    await page.evaluate(() => window.EMRWEB.go('desktop'));
    await page.waitForFunction(() => window.EMRWEB.ready === true, null, { timeout: 120000 });
    pages.push(page);
    return page;
  }
  const A = await openClient('A');
  await A.waitForTimeout(3000);
  const B = await openClient('B');
  await B.waitForTimeout(secs * 1000);
  const q = async (p) => p.evaluate(async () => window.EMRWEB.luaEngine.doString(`
      local G = BRAINROT
      local n, rem = 0, 0
      for _ in pairs(G.conveyor.items) do n = n + 1 end
      for _, e in ipairs(G.ents.order) do if e.kind == "remote" then rem = rem + 1 end end
      local owners = {}
      for i = 1, 8 do owners[#owners + 1] = tostring(G.bases.list[i].owner) end
      return G.localId .. " base=" .. tostring(G.myBase) .. " online=" .. tostring(G.net.online()) .. " mestre=" .. tostring(G.net.isMaster()) ..
        " esteira=" .. n .. " remotos=" .. rem .. " donos=" .. table.concat(owners, ",")`));
  const ra = await q(A), rb = await q(B);
  console.log('A:', ra);
  console.log('B:', rb);
  const ok = /online=true/.test(ra) && /online=true/.test(rb) && /remotos=1/.test(ra) && /remotos=1/.test(rb) && !/base=nil/.test(rb)
    && ra.split('donos=')[1] === rb.split('donos=')[1];
  for (const e of errors.slice(0, 10)) console.log('ERRO:', e.slice(0, 300));
  await browser.close();
  console.log(ok && !errors.length ? 'OK' : 'FALHOU');
  process.exit(ok && !errors.length ? 0 : 1);
})();
