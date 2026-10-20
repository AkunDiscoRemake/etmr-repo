// engine.js — "EnJoyTheMR no navegador": roda os scripts Lua do jogo (wasmoon = Lua 5.4 em
// WebAssembly) e implementa a parte nativa da EMRAPI com three.js.
//
// Ponte Lua <-> JS: funcoes C cruas registradas direto no estado Lua (H_*), ~0.2 us por chamada.
// Coordenadas: a Unity e mao-esquerda; o three.js e mao-direita. Toda transformacao local
// e convertida com M' = S*M*S, S = diag(1,1,-1) (posicao z -> -z).
/* global THREE, EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});

  // ------------------------------------------------------------------------
  // Matematica da Unity (mesma do vec.lua dos jogos)
  // ------------------------------------------------------------------------
  const RAD = Math.PI / 180, DEG = 180 / Math.PI;
  // linhas da matriz de rotacao Ry*Rx*Rz (Unity)
  function unityRot(xd, yd, zd, out) {
    const cx = Math.cos(xd * RAD), sx = Math.sin(xd * RAD);
    const cy = Math.cos(yd * RAD), sy = Math.sin(yd * RAD);
    const cz = Math.cos(zd * RAD), sz = Math.sin(zd * RAD);
    out[0] = cy * cz + sy * sx * sz; out[1] = -cy * sz + sy * sx * cz; out[2] = sy * cx;
    out[3] = cx * sz; out[4] = cx * cz; out[5] = -sx;
    out[6] = -sy * cz + cy * sx * sz; out[7] = sy * sz + cy * sx * cz; out[8] = cy * cx;
    return out;
  }
  function matToQuat(m) { // m: linhas 3x3 -> quaternion (x,y,z,w) da Unity
    const m00 = m[0], m11 = m[4], m22 = m[8];
    const tr = m00 + m11 + m22;
    let x, y, z, w;
    if (tr > 0) {
      const s = Math.sqrt(tr + 1) * 2; w = 0.25 * s;
      x = (m[7] - m[5]) / s; y = (m[2] - m[6]) / s; z = (m[3] - m[1]) / s;
    } else if (m00 > m11 && m00 > m22) {
      const s = Math.sqrt(1 + m00 - m11 - m22) * 2; w = (m[7] - m[5]) / s;
      x = 0.25 * s; y = (m[1] + m[3]) / s; z = (m[2] + m[6]) / s;
    } else if (m11 > m22) {
      const s = Math.sqrt(1 + m11 - m00 - m22) * 2; w = (m[2] - m[6]) / s;
      x = (m[1] + m[3]) / s; y = 0.25 * s; z = (m[5] + m[7]) / s;
    } else {
      const s = Math.sqrt(1 + m22 - m00 - m11) * 2; w = (m[3] - m[1]) / s;
      x = (m[2] + m[6]) / s; y = (m[5] + m[7]) / s; z = 0.25 * s;
    }
    return [x, y, z, w];
  }
  function quatToEuler(x, y, z, w) { // quaternion Unity -> euler Unity (graus)
    const m = [
      1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
      2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
      2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)];
    const m12 = m[5];
    let ex, ey, ez;
    if (m12 < -0.99999) { ex = 90; ey = Math.atan2(-m[6], m[0]) * DEG; ez = 0; }
    else if (m12 > 0.99999) { ex = -90; ey = Math.atan2(-m[6], m[0]) * DEG; ez = 0; }
    else { ex = Math.asin(-m12) * DEG; ey = Math.atan2(m[2], m[8]) * DEG; ez = Math.atan2(m[3], m[4]) * DEG; }
    return [ex, ey, ez];
  }
  W.unityRot = unityRot; W.matToQuat = matToQuat; W.quatToEuler = quatToEuler;
  // three (mao direita) <-> Unity (mao esquerda)
  W.toUnityPos = (v) => [v.x, v.y, -v.z];
  W.toUnityQuat = (q) => [-q.x, -q.y, q.z, q.w];

  // ------------------------------------------------------------------------
  // Grafo de cena
  // ------------------------------------------------------------------------
  const nodes = new Map();      // id -> node
  let nextId = 1;
  W.nodes = nodes;
  W.allocId = () => nextId++;

  let scene, root, headNode;
  const geos = {};
  const texCache = new Map();
  const tmpR = new Array(9);

  function makeGeos() {
    geos.cube = new THREE.BoxGeometry(1, 1, 1);
    geos.sphere = new THREE.SphereGeometry(0.5, 20, 14);
    geos.capsule = new THREE.CapsuleGeometry(0.5, 1, 6, 14);
    geos.cylinder = new THREE.CylinderGeometry(0.5, 0.5, 2, 20);
    geos.plane = new THREE.PlaneGeometry(10, 10).rotateX(-Math.PI / 2);
    geos.quad = new THREE.PlaneGeometry(1, 1);
  }

  function newNode(kind) {
    const id = nextId++;
    let obj;
    if (kind === 'empty') {
      obj = new THREE.Group();
    } else {
      const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.5, metalness: 0 });
      obj = new THREE.Mesh(geos[kind], mat);
      obj.castShadow = W.shadows && kind !== 'quad' && kind !== 'plane';
      obj.receiveShadow = W.shadows;
    }
    obj.matrixAutoUpdate = false;
    const n = {
      id, kind, obj, parent: null, pos: [0, 0, 0], rot: [0, 0, 0], scl: [1, 1, 1],
      color: [1, 1, 1, 1], metal: 0, smooth: 0.5, emit: null, unlit: false, tex: null, tiling: null,
      active: true, dirty: true, children: new Set(), collider: 0, colliderR: 0.5, body: null, headAttach: null,
    };
    obj.userData.node = n;
    nodes.set(id, n);
    return n;
  }

  function setParent(n, p) {
    if (n.parent) n.parent.children.delete(n);
    n.parent = p || null;
    const pobj = p ? p.obj : root;
    pobj.add(n.obj);
    if (p) p.children.add(n);
    n.dirty = true;
    if (W.physics) W.physics.onReparent(n);
  }

  // matriz local (Unity TRS) -> three
  function applyMatrix(n) {
    const r = unityRot(n.rot[0], n.rot[1], n.rot[2], tmpR);
    const sx = n.scl[0], sy = n.scl[1], sz = n.scl[2];
    n.obj.matrix.set(
      r[0] * sx, r[1] * sy, -r[2] * sz, n.pos[0],
      r[3] * sx, r[4] * sy, -r[5] * sz, n.pos[1],
      -r[6] * sx, -r[7] * sy, r[8] * sz, -n.pos[2],
      0, 0, 0, 1);
    n.obj.matrixWorldNeedsUpdate = true;
    n.dirty = false;
  }
  W.applyMatrix = applyMatrix;

  function destroyNode(n) {
    for (const c of Array.from(n.children)) destroyNode(c);
    if (W.physics && (n.body || n.colBody)) W.physics.remove(n);
    if (n.parent) n.parent.children.delete(n);
    if (n.obj.parent) n.obj.parent.remove(n.obj);
    if (n.obj.material) {
      if (n.obj.material.map && n.ownMap) n.obj.material.map.dispose();
      n.obj.material.dispose();
    }
    nodes.delete(n.id);
    n.destroyed = true;
  }

  // ---------------- materiais ----------------
  function texFor(path, tiling) {
    const key = tiling ? path + '|' + tiling[0] + 'x' + tiling[1] : path;
    let t = texCache.get(key);
    if (t) return t;
    const url = W.assets.url(path);
    if (!url) return null;
    let base = texCache.get(path);
    if (!base) {
      base = new THREE.TextureLoader().load(url);
      base.colorSpace = THREE.SRGBColorSpace;
      base.anisotropy = 4;
      texCache.set(path, base);
    }
    if (!tiling) return base;
    t = base.clone();
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(tiling[0], tiling[1]);
    t.needsUpdate = true;
    // o clone so fica pronto quando a imagem base carregar
    if (!base.image || !base.image.complete) {
      const img = base.image;
      if (img && img.addEventListener) img.addEventListener('load', () => { t.needsUpdate = true; });
    }
    texCache.set(key, t);
    return t;
  }

  function rebuildMaterial(n) {
    const o = n.obj;
    if (!o.isMesh) return;
    const old = o.material;
    const map = n.tex ? texFor(n.tex, n.tiling) : null;
    const c = n.color;
    let mat;
    if (n.unlit) {
      mat = new THREE.MeshBasicMaterial({
        color: new THREE.Color(c[0], c[1], c[2]), map, transparent: true, opacity: c[3],
        alphaTest: 0.02, side: THREE.FrontSide,
      });
      mat.toneMapped = false;
      o.castShadow = false;
      o.receiveShadow = false;
    } else {
      mat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(c[0], c[1], c[2]), map,
        metalness: n.metal, roughness: Math.max(0.04, 1 - n.smooth * 0.92),
      });
      if (n.emit) mat.emissive = new THREE.Color(n.emit[0], n.emit[1], n.emit[2]);
    }
    o.material = mat;
    if (old) old.dispose();
  }

  function setColor(n, r, g, b, a) {
    n.color = [r, g, b, a];
    const m = n.obj.material;
    if (!m) return;
    m.color.setRGB(r, g, b);
    if (n.unlit) m.opacity = a;
  }

  // ------------------------------------------------------------------------
  // Ponte Lua (wasmoon)
  // ------------------------------------------------------------------------
  let LW, M, L, lenPtr;
  const td = new TextDecoder();

  function num(Ls, i) { return M._lua_tonumberx(Ls, i, 0); }
  function int(Ls, i) { return Math.round(M._lua_tonumberx(Ls, i, 0)); }
  function bool(Ls, i) { return M._lua_toboolean(Ls, i) !== 0; }
  function str(Ls, i) {
    const p = M._lua_tolstring(Ls, i, lenPtr);
    if (!p) return null;
    const len = M.HEAPU32[lenPtr >> 2];
    return td.decode(M.HEAPU8.subarray(p, p + len));
  }
  function isnone(Ls, i) { return M._lua_type(Ls, i) <= 0; }
  function pushN(Ls, v) { M._lua_pushnumber(Ls, v); }
  function pushB(Ls, v) { M._lua_pushboolean(Ls, v ? 1 : 0); }
  function pushS(Ls, s) { LW.lua_pushstring(Ls, s); }
  function pushNil(Ls) { M._lua_pushnil(Ls); }

  function reg(name, fn) {
    const ptr = M.addFunction((Ls) => {
      try {
        const r = fn(Ls);
        return r || 0;
      } catch (e) {
        console.error('[host] ' + name, e);
        return 0;
      }
    }, 'ii');
    LW.lua_pushcclosure(L, ptr, 0);
    LW.lua_setglobal(L, name);
  }
  W.reg = reg;
  W.lua = { num, int, bool, str, isnone, pushN, pushB, pushS, pushNil };

  function nodeOf(Ls, i) { return nodes.get(int(Ls, i)); }

  function registerScene() {
    reg('H_log', (Ls) => {
      const lvl = int(Ls, 1), msg = str(Ls, 2);
      W.log(lvl, msg);
    });
    reg('H_appid', (Ls) => { pushS(Ls, W.app.id || 'web'); return 1; });
    reg('H_appname', (Ls) => { pushS(Ls, W.app.name || ''); return 1; });
    reg('H_exit', () => { W.exitApp && W.exitApp(); });
    reg('H_hasperm', (Ls) => { pushB(Ls, (W.app.permissions || []).includes(str(Ls, 1))); return 1; });
    reg('H_tracking', (Ls) => { pushS(Ls, W.input.trackingMode()); return 1; });
    reg('H_root', (Ls) => { pushN(Ls, W.rootNode.id); return 1; });
    reg('H_create', (Ls) => {
      const kind = str(Ls, 1);
      const n = newNode(geos[kind] ? kind : 'empty');
      setParent(n, W.rootNode);
      if (W.physics) W.physics.onCreate(n);
      pushN(Ls, n.id);
      return 1;
    });
    reg('H_destroy', (Ls) => { const n = nodeOf(Ls, 1); if (n && n !== W.rootNode) destroyNode(n); });
    reg('H_parent', (Ls) => {
      const n = nodeOf(Ls, 1), p = nodeOf(Ls, 2);
      if (n && p && n !== p) setParent(n, p);
    });
    reg('H_pos', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      n.pos[0] = num(Ls, 2); n.pos[1] = num(Ls, 3); n.pos[2] = num(Ls, 4); n.dirty = true;
      if (n.body) W.physics.teleport(n);
    });
    reg('H_rot', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      n.rot[0] = num(Ls, 2); n.rot[1] = num(Ls, 3); n.rot[2] = num(Ls, 4); n.dirty = true;
      if (n.body) W.physics.teleport(n);
    });
    reg('H_scale', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      n.scl[0] = num(Ls, 2); n.scl[1] = num(Ls, 3); n.scl[2] = num(Ls, 4); n.dirty = true;
    });
    reg('H_color', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      setColor(n, num(Ls, 2), num(Ls, 3), num(Ls, 4), isnone(Ls, 5) ? 1 : num(Ls, 5));
    });
    reg('H_tex', (Ls) => {
      const n = nodeOf(Ls, 1), path = str(Ls, 2);
      if (!n || !W.assets.has(path)) { pushB(Ls, false); return 1; }
      n.tex = path;
      if (n.obj.isMesh) {
        const map = texFor(path, n.tiling);
        n.obj.material.map = map;
        n.obj.material.needsUpdate = true;
      }
      pushB(Ls, true);
      return 1;
    });
    reg('H_mat', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n || !n.obj.isMesh) return;
      const key = str(Ls, 2), a = num(Ls, 3), b = num(Ls, 4), c = num(Ls, 5);
      const m = n.obj.material;
      if (key === 'metal') { n.metal = a; if (m.metalness !== undefined) m.metalness = a; }
      else if (key === 'smooth') { n.smooth = a; if (m.roughness !== undefined) m.roughness = Math.max(0.04, 1 - a * 0.92); }
      else if (key === 'emit') { n.emit = [a, b, c]; if (m.emissive) m.emissive.setRGB(a, b, c); }
      else if (key === 'noshadow') { n.obj.castShadow = !a && W.shadows && !n.unlit; }
      else if (key === 'recvshadow') { n.obj.receiveShadow = !!a && W.shadows && !n.unlit; }
      else if (key === 'unlit') { if (!n.unlit) { n.unlit = true; rebuildMaterial(n); } }
      else if (key === 'tiling') {
        n.tiling = [a, b];
        if (n.tex) { m.map = texFor(n.tex, n.tiling); m.needsUpdate = true; }
      }
    });
    reg('H_active', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      n.active = bool(Ls, 2); n.obj.visible = n.active;
      if (W.physics) W.physics.onActive(n);
    });
    reg('H_isactive', (Ls) => { const n = nodeOf(Ls, 1); pushB(Ls, n ? n.active : false); return 1; });
    reg('H_getpos', (Ls) => {
      const n = nodeOf(Ls, 1);
      if (!n) { pushN(Ls, 0); pushN(Ls, 0); pushN(Ls, 0); return 3; }
      pushN(Ls, n.pos[0]); pushN(Ls, n.pos[1]); pushN(Ls, n.pos[2]); return 3;
    });
    reg('H_getwpos', (Ls) => {
      const n = nodeOf(Ls, 1);
      const v = new THREE.Vector3();
      if (n) { applyAllDirty(); n.obj.updateWorldMatrix(true, false); v.setFromMatrixPosition(n.obj.matrixWorld); }
      pushN(Ls, v.x); pushN(Ls, v.y); pushN(Ls, -v.z); return 3;
    });
    reg('H_getrot', (Ls) => {
      const n = nodeOf(Ls, 1);
      const q = n ? matToQuat(unityRot(n.rot[0], n.rot[1], n.rot[2], tmpR)) : [0, 0, 0, 1];
      pushN(Ls, q[0]); pushN(Ls, q[1]); pushN(Ls, q[2]); pushN(Ls, q[3]); return 4;
    });
    reg('H_gettrs', (Ls) => {
      const n = nodeOf(Ls, 1);
      const a = n ? [...n.pos, ...n.rot, ...n.scl] : [0, 0, 0, 0, 0, 0, 1, 1, 1];
      for (const v of a) pushN(Ls, v);
      return 9;
    });
    reg('H_headattach', (Ls) => {
      const n = nodeOf(Ls, 1); if (!n) return;
      if (bool(Ls, 2)) {
        n.headAttach = { prevParent: n.parent };
        n.pos = [num(Ls, 3), num(Ls, 4), num(Ls, 5)];
        n.rot = [0, 0, 0];
        if (n.parent) n.parent.children.delete(n);
        n.parent = null;
        headNode.add(n.obj);
        n.dirty = true;
      } else if (n.headAttach) {
        const prev = n.headAttach.prevParent;
        n.headAttach = null;
        setParent(n, prev || W.rootNode);
      }
    });
    reg('H_bg', (Ls) => { W.setBackground && W.setBackground(str(Ls, 1)); });
    reg('H_ambient', (Ls) => { W.setAmbient(num(Ls, 1), num(Ls, 2), num(Ls, 3)); });
  }

  function applyAllDirty() {
    for (const n of nodes.values()) if (n.dirty) applyMatrix(n);
  }
  W.applyAllDirty = applyAllDirty;

  // chama uma funcao global do Lua com numeros/strings como argumentos
  function callLua(name, ...args) {
    LW.lua_getglobal(L, name);
    if (M._lua_type(L, -1) !== 6) { LW.lua_settop(L, -2); return; }
    for (const a of args) {
      if (typeof a === 'string') pushS(L, a);
      else if (typeof a === 'boolean') pushB(L, a);
      else pushN(L, a);
    }
    const r = LW.lua_pcallk(L, args.length, 0, 0, 0, null);
    if (r !== 0) {
      const msg = LW.lua_tolstring(L, -1, null);
      W.log(3, '[' + name + '] ' + msg);
      LW.lua_settop(L, -2);
    }
  }
  W.callLua = callLua;

  // ------------------------------------------------------------------------
  // Luz / ceu (parecido com a cena padrao da Unity)
  // ------------------------------------------------------------------------
  let hemi, sun, baseAmbient = [0.75, 0.78, 0.85];
  function setupLights() {
    hemi = new THREE.HemisphereLight(0xe6edff, 0x4a4540, 1.15);
    scene.add(hemi);
    sun = new THREE.DirectionalLight(0xfff6ea, 1.9);
    sun.position.set(6, 12, 4);
    if (W.shadows) {
      sun.castShadow = true;
      sun.shadow.mapSize.set(2048, 2048);
      const c = sun.shadow.camera;
      c.left = -18; c.right = 18; c.top = 18; c.bottom = -18; c.near = 0.5; c.far = 60;
      sun.shadow.bias = -0.0005;
    }
    scene.add(sun);
    scene.add(sun.target);
  }
  W.setAmbient = function (r, g, b) {
    const lum = (0.3 * r + 0.59 * g + 0.11 * b) / (0.3 * baseAmbient[0] + 0.59 * baseAmbient[1] + 0.11 * baseAmbient[2]);
    const k = Math.max(0.12, Math.min(1.4, lum));
    hemi.color.setRGB(Math.min(1, r / 0.78), Math.min(1, g / 0.78), Math.min(1, b / 0.78));
    hemi.intensity = 1.15 * k;
    sun.intensity = 1.9 * k;
  };

  // ------------------------------------------------------------------------
  // Boot
  // ------------------------------------------------------------------------
  W.log = function (lvl, msg) {
    const f = lvl >= 3 ? console.error : (lvl === 2 ? console.warn : console.log);
    f('[lua] ' + msg);
    W.logs = W.logs || [];
    W.logs.push((lvl >= 3 ? 'ERROR: ' : lvl === 2 ? 'WARN: ' : 'LOG: ') + msg);
    if (W.logs.length > 400) W.logs.shift();
    if (lvl >= 3 && W.onError) W.onError(msg);
  };

  W.start = async function (opts) {
    const app = W.app;
    W.shadows = !!opts.shadows;
    // three
    const canvas = opts.canvas;
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: !opts.mobile, powerPreference: 'high-performance' });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, opts.mobile ? 1.5 : 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    renderer.shadowMap.enabled = W.shadows;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    W.renderer = renderer;
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x101418);
    W.scene = scene;
    makeGeos();
    setupLights();
    root = new THREE.Group();
    root.matrixAutoUpdate = false;
    scene.add(root);
    headNode = new THREE.Group();
    scene.add(headNode);
    W.headNode = headNode;
    const rn = { id: nextId++, kind: 'empty', obj: root, parent: null, pos: [0, 0, 0], rot: [0, 0, 0], scl: [1, 1, 1], children: new Set(), active: true, dirty: false };
    nodes.set(rn.id, rn);
    W.rootNode = rn;
    W.root3 = root;
    W.input.setupCamera();

    // Lua
    const factory = new window.wasmoon.LuaFactory(opts.wasmUrl);
    for (const [path, src] of Object.entries(app.scripts)) await factory.mountFile('/app/' + path, src);
    await factory.mountFile('/app/emr_core.lua', W.coreLua);
    const engine = await factory.createEngine({ injectObjects: false, enableProxy: false, openStandardLibs: true });
    W.luaEngine = engine;
    LW = engine.global.lua;
    M = LW.module;
    L = engine.global.address;
    lenPtr = M._malloc(8);

    registerScene();
    W.input.register();
    W.audio.register();
    W.ui3d.register();
    W.physicsBridge.register();
    W.storage.register();
    W.net.register();

    await engine.doString('package.path = "/app/scripts/?.lua;/app/?.lua;" .. package.path');
    await engine.doString('dofile("/app/emr_core.lua")');
    await engine.doString('dofile("/app/' + app.entry + '")');
    callLua('EMR_START');

    // laco
    let last = performance.now();
    const t0 = last;
    W.frameMs = 0;
    function frame(now, xrFrame) {
      let dt = (now - last) / 1000;
      last = now;
      if (!(dt > 0)) dt = 1 / 60;
      if (dt > 0.05) dt = 0.05;
      const tStart = performance.now();
      W.input.update(dt, xrFrame);
      callLua('EMR_FRAME', dt, (now - t0) / 1000);
      applyAllDirty();
      if (W.physics) W.physics.step(dt);
      W.audio.update();
      W.ui3d.update(dt);
      W.net.update && W.net.update();
      W.frameMs = W.frameMs * 0.95 + (performance.now() - tStart) * 0.05;
      W.render(dt);
      if (W.onFrame) W.onFrame(dt);
    }
    renderer.setAnimationLoop(frame);
    document.addEventListener('visibilitychange', () => callLua('EMR_PAUSE', document.hidden));
    window.addEventListener('beforeunload', () => callLua('EMR_DESTROY'));
  };
})();
