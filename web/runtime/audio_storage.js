// audio_storage.js — EMRAPI.Audio (WebAudio, som 3D com HRTF) e EMRAPI.Storage (localStorage).
/* global THREE, EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});

  // ------------------------------------------------------------------------
  // Audio
  // ------------------------------------------------------------------------
  const A = {};
  W.audio = A;
  let ctx = null, master = null;
  const buffers = new Map();     // path -> AudioBuffer | Promise
  const playing = new Map();     // id -> { src, gain, panner, path, loop }
  let seq = 1;

  A.init = function () {
    if (ctx) return ctx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = 1;
    master.connect(ctx.destination);
    return ctx;
  };
  A.resume = function () { if (ctx && ctx.state !== 'running') ctx.resume(); };

  // decodifica todos os sons do pacote (em paralelo)
  A.preload = async function (onProgress) {
    if (!A.init()) return;
    const paths = W.assets.list().filter((p) => /\.(wav|ogg|mp3)$/i.test(p));
    let done = 0;
    await Promise.all(paths.map(async (p) => {
      try {
        const data = await W.assets.arrayBuffer(p);
        const buf = await ctx.decodeAudioData(data);
        buffers.set(p, buf);
      } catch (e) { console.warn('som falhou', p, e); }
      done++;
      if (onProgress) onProgress(done / paths.length);
    }));
  };

  function play(path, spatial, x, y, z, loop) {
    if (!ctx) return 0;
    const buf = buffers.get(path);
    if (!buf) return 0;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = !!loop;
    const gain = ctx.createGain();
    gain.gain.value = 1;
    let panner = null;
    if (spatial) {
      panner = ctx.createPanner();
      panner.panningModel = 'HRTF';
      panner.distanceModel = 'inverse';
      panner.refDistance = 1.5;
      panner.maxDistance = 60;
      panner.rolloffFactor = 1;
      // Unity (x,y,z) -> three/WebAudio (x,y,-z)
      if (panner.positionX) { panner.positionX.value = x; panner.positionY.value = y; panner.positionZ.value = -z; }
      else panner.setPosition(x, y, -z);
      src.connect(gain); gain.connect(panner); panner.connect(master);
    } else {
      src.connect(gain); gain.connect(master);
    }
    const id = seq++;
    const e = { src, gain, panner, path, loop: !!loop, ended: false };
    src.onended = () => { e.ended = true; if (!e.loop) playing.delete(id); };
    src.start();
    playing.set(id, e);
    return id;
  }

  A.update = function () {
    if (!ctx) return;
    const h = W.input.head;
    const L = ctx.listener;
    const f = new THREE.Vector3(0, 0, -1).applyQuaternion(h.quat);
    const u = new THREE.Vector3(0, 1, 0).applyQuaternion(h.quat);
    if (L.positionX) {
      L.positionX.value = h.pos.x; L.positionY.value = h.pos.y; L.positionZ.value = h.pos.z;
      L.forwardX.value = f.x; L.forwardY.value = f.y; L.forwardZ.value = f.z;
      L.upX.value = u.x; L.upY.value = u.y; L.upZ.value = u.z;
    } else {
      L.setPosition(h.pos.x, h.pos.y, h.pos.z);
      L.setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
    }
  };

  A.register = function () {
    const { reg, lua } = W;
    // H_aplay(path, spatial, x, y, z, loop) -> id
    reg('H_aplay', (Ls) => {
      const id = play(lua.str(Ls, 1), lua.int(Ls, 2) === 1, lua.num(Ls, 3), lua.num(Ls, 4), lua.num(Ls, 5), lua.int(Ls, 6) === 1);
      lua.pushN(Ls, id);
      return 1;
    });
    reg('H_astop', (Ls) => {
      const id = lua.int(Ls, 1);
      const stop = (k, e) => { try { e.loop = false; e.src.stop(); } catch (_) { /* ja parou */ } playing.delete(k); };
      if (id === 0) { for (const [k, e] of playing) stop(k, e); }
      else { const e = playing.get(id); if (e) stop(id, e); }
    });
    reg('H_aset', (Ls) => {
      const e = playing.get(lua.int(Ls, 1));
      if (!e) return;
      const k = lua.str(Ls, 2), v = lua.num(Ls, 3);
      if (k === 'vol') e.gain.gain.value = Math.max(0, v);
      else if (k === 'pitch') e.src.playbackRate.value = Math.max(0.1, Math.min(3, v));
      else if (k === 'loop') { e.loop = v !== 0; e.src.loop = e.loop; }
    });
    reg('H_amaster', (Ls) => { if (master) master.gain.value = Math.max(0, lua.num(Ls, 1)); });
    reg('H_aplaying', (Ls) => {
      const e = playing.get(lua.int(Ls, 1));
      lua.pushB(Ls, !!(e && !e.ended));
      return 1;
    });
  };

  // ------------------------------------------------------------------------
  // Storage (isolado por id do app, como no EnJoyTheMR)
  // ------------------------------------------------------------------------
  const S = {};
  W.storage = S;
  let cache = null;
  function key() { return 'emr:' + (W.app.id || 'web'); }
  function load() {
    if (cache) return cache;
    try { cache = JSON.parse(localStorage.getItem(key()) || '{}') || {}; } catch (e) { cache = {}; }
    return cache;
  }
  function save() {
    try { localStorage.setItem(key(), JSON.stringify(load())); } catch (e) { /* modo privado */ }
  }
  S.register = function () {
    const { reg, lua } = W;
    reg('H_sget', (Ls) => {
      const v = load()[lua.str(Ls, 1)];
      if (v === undefined) { lua.pushNil(Ls); return 1; }
      lua.pushS(Ls, v);
      return 1;
    });
    reg('H_sset', (Ls) => { load()[lua.str(Ls, 1)] = lua.str(Ls, 2); });
    reg('H_sdel', (Ls) => { delete load()[lua.str(Ls, 1)]; });
    reg('H_ssave', () => { save(); });
  };
  // salva tambem ao sair
  window.addEventListener('pagehide', () => { if (cache) save(); });
})();
