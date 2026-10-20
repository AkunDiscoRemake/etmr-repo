// ui3d.js — EMRAPI.UI: paineis no mundo 3D (canvas -> textura), com botoes, textos,
// toggles, sliders e imagens. Clique: mouse (PC), toque/olhar (VR Box), controle ou dedo (WebXR).
/* global THREE, EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});
  const U = {};
  W.ui3d = U;

  const PX = 500;           // pixels de UI por metro (layout dos jogos)
  const RES = 2;            // resolucao do canvas (nitidez)
  const els = new Map();    // id -> elemento
  const panels = [];
  let hover = null;         // { panel, el }
  let reticle = null;

  const DEF = {
    text: [160, 30], button: [160, 30], toggle: [160, 24], slider: [160, 20], image: [100, 100], input: [160, 30], scroll: [200, 200],
  };

  function lum(c) { return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]; }

  function create(kind, parentId, text, a, b) {
    const id = W.allocId();
    const parent = els.get(parentId) || null;
    const e = {
      id, kind, parent, text: text || '', x: 0, y: 0, w: (DEF[kind] || [100, 30])[0], h: (DEF[kind] || [100, 30])[1],
      color: null, active: true, children: [], value: 0, state: false, min: a, max: b, img: null,
    };
    if (kind === 'slider') e.value = a;
    if (kind === 'image' && text) loadImg(e, text);
    els.set(id, e);
    if (kind === 'panel') {
      e.wm = a; e.hm = b;
      e.color = [0.12, 0.13, 0.2, 0.92];
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(a * PX * RES); canvas.height = Math.round(b * PX * RES);
      e.canvas = canvas;
      e.ctx = canvas.getContext('2d');
      e.tex = new THREE.CanvasTexture(canvas);
      e.tex.colorSpace = THREE.SRGBColorSpace;
      const mat = new THREE.MeshBasicMaterial({ map: e.tex, transparent: true, side: THREE.DoubleSide, depthTest: true });
      mat.toneMapped = false;
      e.mesh = new THREE.Mesh(new THREE.PlaneGeometry(a, b), mat);
      e.mesh.renderOrder = 10;
      e.mesh.userData.panel = e;
      W.scene.add(e.mesh);
      e.dirty = true;
      e.placed = false;
      panels.push(e);
    } else if (parent) {
      parent.children.push(e);
      markDirty(e);
    }
    return id;
  }

  function loadImg(e, path) {
    const url = W.assets.url(path);
    if (!url) return;
    const img = new Image();
    img.onload = () => { e.img = img; markDirty(e); };
    img.src = url;
  }

  function panelOf(e) {
    let p = e;
    while (p && p.kind !== 'panel') p = p.parent;
    return p;
  }
  function markDirty(e) { const p = panelOf(e); if (p) p.dirty = true; }
  function visible(e) {
    let p = e;
    while (p) { if (!p.active) return false; p = p.parent; }
    return true;
  }
  U.anyVisible = () => panels.some((p) => p.active && p.mesh.visible);

  // coloca o painel na frente da cabeca
  function place(p) {
    const h = W.input.head;
    const f = new THREE.Vector3(0, 0, -1).applyQuaternion(h.quat);
    f.y = 0;
    if (f.lengthSq() < 1e-4) f.set(0, 0, -1);
    f.normalize();
    p.mesh.position.copy(h.pos).addScaledVector(f, 1.15);
    p.mesh.position.y = h.pos.y - 0.05;
    p.mesh.lookAt(h.pos.x, p.mesh.position.y, h.pos.z);
    p.placed = true;
  }

  // posicao absoluta (px, origem no centro do painel, y para cima)
  function absPos(e) {
    let x = 0, y = 0, q = e;
    while (q && q.kind !== 'panel') { x += q.x; y += q.y; q = q.parent; }
    return [x, y];
  }

  // ------------------------------------------------------------------------
  // Desenho
  // ------------------------------------------------------------------------
  function roundRect(c, x, y, w, h, r) {
    c.beginPath();
    c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
  }
  function rgba(c, a) { return 'rgba(' + Math.round(c[0] * 255) + ',' + Math.round(c[1] * 255) + ',' + Math.round(c[2] * 255) + ',' + (a !== undefined ? a : (c[3] !== undefined ? c[3] : 1)) + ')'; }
  function wrap(c, text, maxW) {
    const out = [];
    for (const para of String(text).split('\n')) {
      const words = para.split(' ');
      let line = '';
      for (const w of words) {
        const t = line ? line + ' ' + w : w;
        if (c.measureText(t).width > maxW && line) { out.push(line); line = w; } else line = t;
      }
      out.push(line);
    }
    return out;
  }
  function drawText(c, text, cx, cy, w, h, size, color, align) {
    c.fillStyle = color;
    let fs = size;
    let lines;
    do {
      c.font = 'bold ' + fs + 'px system-ui, "Segoe UI", Roboto, sans-serif';
      lines = wrap(c, text, w - 8 * RES);
      if (lines.length * fs * 1.2 <= h || fs <= 10 * RES) break;
      fs -= RES;
    } while (true);
    c.textAlign = align || 'center';
    c.textBaseline = 'middle';
    const lh = fs * 1.2;
    const y0 = cy - (lines.length - 1) * lh / 2;
    const x = align === 'left' ? cx - w / 2 + 4 * RES : cx;
    lines.forEach((l, i) => c.fillText(l, x, y0 + i * lh));
  }

  function drawPanel(p) {
    const c = p.ctx, Wd = p.canvas.width, Hd = p.canvas.height;
    c.clearRect(0, 0, Wd, Hd);
    roundRect(c, 0, 0, Wd, Hd, 18 * RES);
    c.fillStyle = rgba(p.color);
    c.fill();
    const darkBg = lum(p.color) < 0.5;
    const txtCol = darkBg ? '#f2f4ff' : '#1e2230';
    const walk = (e) => {
      if (!e.active) return;
      if (e !== p) drawEl(c, e, p, txtCol, darkBg);
      for (const ch of e.children) walk(ch);
    };
    walk(p);
    p.tex.needsUpdate = true;
    p.dirty = false;
  }

  function drawEl(c, e, p, txtCol, darkBg) {
    const [ax, ay] = absPos(e);
    const cx = (p.wm * PX / 2 + ax) * RES, cy = (p.hm * PX / 2 - ay) * RES;
    const w = e.w * RES, h = e.h * RES;
    const x = cx - w / 2, y = cy - h / 2;
    const hot = hover && hover.el === e;
    if (e.kind === 'text') {
      drawText(c, e.text, cx, cy, w, h, 20 * RES, e.color ? rgba(e.color) : txtCol);
    } else if (e.kind === 'button' || e.kind === 'input') {
      roundRect(c, x, y, w, h, 10 * RES);
      c.fillStyle = e.color ? rgba(e.color) : (hot ? '#ffe27a' : (darkBg ? '#e9ecf6' : '#ffffff'));
      c.fill();
      c.lineWidth = 2 * RES; c.strokeStyle = hot ? '#ffb300' : 'rgba(0,0,0,0.25)'; c.stroke();
      drawText(c, e.text || '', cx, cy, w, h, 19 * RES, '#1b1e2a');
    } else if (e.kind === 'toggle') {
      const s = Math.min(h, 22 * RES);
      roundRect(c, x, cy - s / 2, s, s, 5 * RES);
      c.fillStyle = e.state ? '#3ccf6a' : '#ffffff'; c.fill();
      c.lineWidth = 2 * RES; c.strokeStyle = hot ? '#ffb300' : 'rgba(0,0,0,0.4)'; c.stroke();
      if (e.state) {
        c.strokeStyle = '#fff'; c.lineWidth = 3 * RES; c.beginPath();
        c.moveTo(x + s * 0.22, cy); c.lineTo(x + s * 0.42, cy + s * 0.22); c.lineTo(x + s * 0.78, cy - s * 0.24); c.stroke();
      }
      drawText(c, e.text, cx + s / 2 + 4 * RES, cy, w - s - 8 * RES, h, 17 * RES, txtCol, 'left');
    } else if (e.kind === 'slider') {
      const t = (e.max - e.min) !== 0 ? (e.value - e.min) / (e.max - e.min) : 0;
      roundRect(c, x, cy - 4 * RES, w, 8 * RES, 4 * RES); c.fillStyle = 'rgba(255,255,255,0.35)'; c.fill();
      roundRect(c, x, cy - 4 * RES, w * t, 8 * RES, 4 * RES); c.fillStyle = '#5aa0ff'; c.fill();
      c.beginPath(); c.arc(x + w * t, cy, 10 * RES, 0, Math.PI * 2);
      c.fillStyle = hot ? '#ffe27a' : '#ffffff'; c.fill(); c.strokeStyle = 'rgba(0,0,0,0.4)'; c.lineWidth = 2 * RES; c.stroke();
    } else if (e.kind === 'image' && e.img) {
      c.drawImage(e.img, x, y, w, h);
    } else if (e.kind === 'scroll') {
      roundRect(c, x, y, w, h, 8 * RES); c.fillStyle = 'rgba(0,0,0,0.15)'; c.fill();
    }
  }

  // ------------------------------------------------------------------------
  // Interacao
  // ------------------------------------------------------------------------
  const ray = new THREE.Raycaster();
  function hitPanels(origin, dir) {
    ray.set(origin, dir);
    const meshes = panels.filter((p) => p.active && p.mesh.visible).map((p) => p.mesh);
    const hits = ray.intersectObjects(meshes, false);
    return hits[0] || null;
  }
  function elementAt(p, uv) {
    const px = (uv.x - 0.5) * p.wm * PX, py = (uv.y - 0.5) * p.hm * PX;
    let found = null;
    const walk = (e) => {
      if (!e.active) return;
      if (e !== p && (e.kind === 'button' || e.kind === 'toggle' || e.kind === 'slider' || e.kind === 'input')) {
        const [ax, ay] = absPos(e);
        if (Math.abs(px - ax) <= e.w / 2 + 6 && Math.abs(py - ay) <= e.h / 2 + 6) found = { el: e, lx: px - ax };
      }
      for (const ch of e.children) walk(ch);
    };
    walk(p);
    return found;
  }

  function activate(found) {
    const e = found.el;
    W.audio && W.audio.resume();
    if (e.kind === 'button') {
      W.callLua('EMR_UI_EVENT', e.id, 'button', 0);
    } else if (e.kind === 'toggle') {
      e.state = !e.state; markDirty(e);
      W.callLua('EMR_UI_EVENT', e.id, 'toggle', e.state ? 1 : 0);
    } else if (e.kind === 'slider') {
      const t = Math.max(0, Math.min(1, (found.lx + e.w / 2) / e.w));
      e.value = e.min + (e.max - e.min) * t; markDirty(e);
      W.callLua('EMR_UI_EVENT', e.id, 'slider', e.value);
    } else if (e.kind === 'input') {
      const v = window.prompt(e.text || '', '');
      if (v !== null) { e.text = v; markDirty(e); W.callLua('EMR_UI_EVENT', e.id, 'input', v); }
    }
  }

  function pick(origin, dir) {
    const h = hitPanels(origin, dir);
    if (!h) return null;
    const p = h.object.userData.panel;
    const f = elementAt(p, h.uv);
    return f ? { panel: p, el: f.el, lx: f.lx, point: h.point } : { panel: p, el: null, point: h.point };
  }

  function mouseRay(ev) {
    const r = W.renderer.domElement.getBoundingClientRect();
    const nx = ((ev.clientX - r.left) / r.width) * 2 - 1, ny = -((ev.clientY - r.top) / r.height) * 2 + 1;
    ray.setFromCamera(new THREE.Vector2(nx, ny), W.camera);
    return [ray.ray.origin.clone(), ray.ray.direction.clone()];
  }
  function gazeRay() {
    const h = W.input.head;
    return [h.pos.clone(), new THREE.Vector3(0, 0, -1).applyQuaternion(h.quat)];
  }

  U.pointerMove = function (ev) {
    if (!U.anyVisible()) return;
    const [o, d] = mouseRay(ev);
    const f = pick(o, d);
    setHover(f && f.el ? f : null);
  };
  U.pointerDown = function (ev) {
    if (!U.anyVisible() || W.input.mode !== 'desktop' || document.pointerLockElement) return false;
    const [o, d] = mouseRay(ev);
    const f = pick(o, d);
    if (f && f.el) { activate(f); return true; }
    return !!f;
  };
  U.gazeClick = function () {
    if (!U.anyVisible()) return false;
    const [o, d] = gazeRay();
    const f = pick(o, d);
    if (f && f.el) { activate(f); return true; }
    return false;
  };
  function setHover(f) {
    const prev = hover && hover.el;
    hover = f;
    if (prev !== (f && f.el)) {
      if (prev) markDirty(prev);
      if (f && f.el) markDirty(f.el);
    }
  }

  // ------------------------------------------------------------------------
  // Atualizacao
  // ------------------------------------------------------------------------
  let pokeLatch = false, gazeLatch = false;
  U.update = function () {
    const mode = W.input.mode;
    // desktop: painel aberto solta o mouse; fechado prende de novo no proximo clique
    if (mode === 'desktop' && U.anyVisible() && document.pointerLockElement) document.exitPointerLock();
    for (const p of panels) {
      p.mesh.visible = p.active;
      if (p.active && !p.placed) place(p);
      if (p.dirty && p.active) drawPanel(p);
    }
    if (!U.anyVisible()) { if (reticle) reticle.visible = false; return; }
    // VR Box / XR: olhar mira; botao A/gatilho ou dedo clica
    if (mode === 'vrbox' || mode === 'xr') {
      const [o, d] = gazeRay();
      const f = pick(o, d);
      setHover(f && f.el ? f : null);
      if (!reticle) {
        reticle = new THREE.Mesh(new THREE.RingGeometry(0.006, 0.011, 20), new THREE.MeshBasicMaterial({ color: 0xffcc33, depthTest: false }));
        reticle.renderOrder = 20;
        W.scene.add(reticle);
      }
      reticle.visible = !!f;
      if (f) { reticle.position.copy(f.point); reticle.lookAt(W.input.head.pos); }
      const btn = W.input.anyButton ? W.input.anyButton() : false;
      if (btn && !gazeLatch && f && f.el) activate(f);
      gazeLatch = btn;
      // dedo indicador (maos rastreadas) toca no painel
      for (const side of ['right', 'left']) {
        const hh = W.input.hands[side];
        if (!hh.ok) continue;
        const tip = new THREE.Vector3(hh.pts[8][0], hh.pts[8][1], -hh.pts[8][2]);
        for (const p of panels) {
          if (!p.active) continue;
          const local = p.mesh.worldToLocal(tip.clone());
          const inside = Math.abs(local.x) < p.wm / 2 && Math.abs(local.y) < p.hm / 2;
          if (inside && Math.abs(local.z) < 0.015 && !pokeLatch) {
            const uv = new THREE.Vector2(local.x / p.wm + 0.5, local.y / p.hm + 0.5);
            const fe = elementAt(p, uv);
            if (fe) { activate({ panel: p, el: fe.el, lx: fe.lx }); pokeLatch = true; }
          } else if (!inside || Math.abs(local.z) > 0.04) {
            pokeLatch = false;
          }
        }
      }
    }
  };

  // ------------------------------------------------------------------------
  // Funcoes para o Lua
  // ------------------------------------------------------------------------
  U.register = function () {
    const { reg, lua } = W;
    reg('H_ui', (Ls) => {
      const kind = lua.str(Ls, 1), parent = lua.int(Ls, 2), text = lua.str(Ls, 3) || '';
      const id = create(kind, parent, text, lua.num(Ls, 4), lua.num(Ls, 5));
      lua.pushN(Ls, id);
      return 1;
    });
    reg('H_uiset', (Ls) => {
      const e = els.get(lua.int(Ls, 1));
      if (!e) return;
      const k = lua.str(Ls, 2), s = lua.str(Ls, 3);
      const a = lua.num(Ls, 4), b = lua.num(Ls, 5), c = lua.num(Ls, 6), d = lua.num(Ls, 7);
      if (k === 'text') { e.text = s; }
      else if (k === 'pos') { e.x = a; e.y = b; }
      else if (k === 'size') { e.w = a; e.h = b; }
      else if (k === 'color') { e.color = [a, b, c, d]; }
      else if (k === 'image') { loadImg(e, s); }
      else if (k === 'active') {
        const was = e.active;
        e.active = a !== 0;
        if (e.kind === 'panel') {
          e.mesh.visible = e.active;
          if (e.active && !was) e.placed = false;   // reabriu: aparece na frente
        }
      } else if (k === 'destroy') {
        e.active = false;
        if (e.kind === 'panel') {
          W.scene.remove(e.mesh);
          const i = panels.indexOf(e); if (i >= 0) panels.splice(i, 1);
        } else if (e.parent) {
          const i = e.parent.children.indexOf(e); if (i >= 0) e.parent.children.splice(i, 1);
        }
        els.delete(e.id);
      }
      markDirty(e);
    });
    reg('H_uitext', (Ls) => { const e = els.get(lua.int(Ls, 1)); lua.pushS(Ls, e ? e.text : ''); return 1; });
  };
})();
