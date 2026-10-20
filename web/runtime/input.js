// input.js — entrada e modos de exibicao do EnJoyTheMR no navegador.
//  * PC: mouse olha, WASD anda, botoes viram um "Joy-Con virtual" (mesmos numeros de botao)
//  * Gamepad / Joy-Con de verdade (Gamepad API)
//  * VR Box: tela dividida (estereo) + giroscopio do celular
//  * WebXR: oculos VR (cabeca, maos com 21 articulacoes, controles)
//  * Camera: hand tracking com MediaPipe (as mesmas 21 articulacoes do app)
/* global THREE, EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});
  const I = {};
  W.input = I;

  I.mode = 'desktop';         // desktop | vrbox | xr
  I.virtualHands = true;      // maos simuladas quando nao ha tracking (PC/VR Box)
  I.yaw = 0; I.pitch = 0;     // cabeca no modo PC
  I.reach = 0.32;             // distancia das maos simuladas
  const keys = new Set();
  const mouseBtn = [false, false, false];
  let gyroQ = null, gyroYawOffset = 0, dragYaw = 0;
  let camHands = null;        // { left: pts, right: pts } vindos da camera
  const head = { pos: new THREE.Vector3(0, 0, 0), quat: new THREE.Quaternion() };
  const hands = {
    left: { ok: false, pts: [], gesture: 'None', pinch: 0, punch: 0 },
    right: { ok: false, pts: [], gesture: 'None', pinch: 0, punch: 0 },
  };
  for (const s of ['left', 'right']) for (let i = 0; i < 21; i++) hands[s].pts.push([0, 0, 0]);
  const virtPad = new Array(20).fill(false);   // botoes do Joy-Con virtual (teclado/mouse)
  const xrPad = new Array(20).fill(false);     // botoes dos controles WebXR
  let axes = { h: 0, v: 0 };
  let realPads = [];

  // ------------------------------------------------------------------------
  // Mao sintetica (mesmo modelo do simulador): mao aberta + dobra dos dedos
  // ------------------------------------------------------------------------
  const OPEN = [
    [0, 0, 0],
    [-0.025, -0.006, 0.025], [-0.045, -0.009, 0.05], [-0.06, -0.009, 0.075], [-0.07, -0.009, 0.095],
    [-0.022, 0, 0.09], [-0.026, 0, 0.13], [-0.028, 0, 0.155], [-0.03, 0, 0.175],
    [0, 0, 0.095], [0, 0, 0.14], [0, 0, 0.168], [0, 0, 0.19],
    [0.02, 0, 0.09], [0.022, 0, 0.13], [0.024, 0, 0.155], [0.025, 0, 0.175],
    [0.038, 0, 0.08], [0.042, 0, 0.11], [0.045, 0, 0.13], [0.047, 0, 0.147],
  ];
  const FING = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16], [17, 18, 19, 20]];
  const ANG = [85, 105, 70];
  function handPoints(side, curl) {
    const pts = OPEN.map((p) => [p[0], p[1], p[2]]);
    for (let fi = 1; fi < 5; fi++) {
      const f = FING[fi], c = curl[fi];
      let acc = 0;
      let prev = pts[f[0]].slice();
      for (let j = 1; j < 4; j++) {
        acc += ANG[j - 1] * c;
        const a = OPEN[f[j]], b = OPEN[f[j - 1]];
        const seg = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
        const Lg = Math.hypot(seg[1], seg[2]);
        const r = acc * Math.PI / 180;
        const p = [prev[0] + seg[0], prev[1] - Math.sin(r) * Lg, prev[2] + Math.cos(r) * Lg];
        pts[f[j]] = p;
        prev = p;
      }
    }
    const c = curl[0];
    for (let j = 1; j <= 3; j++) {
      const p = pts[j + 1];
      pts[j + 1] = [p[0] + 0.025 * c * j / 3, p[1] - 0.015 * c, p[2] - 0.01 * c * j / 3];
    }
    if (side === 'left') for (const p of pts) p[0] = -p[0];
    return pts;
  }
  I.handPoints = handPoints;

  // coloca a mao: wrist (three), base r/u/f (three) -> pontos Unity
  function placeHand(h, side, wrist, r, u, f, curl) {
    const pts = handPoints(side, curl);
    for (let i = 0; i < 21; i++) {
      const p = pts[i];
      const x = wrist.x + r.x * p[0] + u.x * p[1] + f.x * p[2];
      const y = wrist.y + r.y * p[0] + u.y * p[1] + f.y * p[2];
      const z = wrist.z + r.z * p[0] + u.z * p[1] + f.z * p[2];
      h.pts[i][0] = x; h.pts[i][1] = y; h.pts[i][2] = -z;
    }
    h.ok = true;
  }

  function gestureFromCurl(curl) {
    const grip = (curl[2] + curl[3] + curl[4]) / 3;
    if (grip > 0.7 && curl[1] > 0.6) return 'Fist';
    if (grip > 0.6 && curl[1] < 0.3) return 'Point';
    if (grip < 0.3 && curl[1] < 0.3) return 'Open';
    return 'None';
  }

  // curl a partir dos pontos (para maos reais: XR/camera)
  function curlFromPts(pts) {
    const out = [];
    for (let fi = 0; fi < 5; fi++) {
      const f = FING[fi];
      const a = pts[f[0]], b = pts[f[1]], c = pts[f[2]], d = pts[f[3]];
      const dist = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]);
      const chain = dist(a, b) + dist(b, c) + dist(c, d);
      const straight = chain > 1e-4 ? dist(a, d) / chain : 1;
      out.push(Math.max(0, Math.min(1, (0.93 - straight) / 0.43)));
    }
    return out;
  }

  // ------------------------------------------------------------------------
  // Teclado / mouse (Joy-Con virtual)
  // ------------------------------------------------------------------------
  // mesmos numeros de botao dos padroes do jogo (Joy-Con no Android):
  // 7 = ZR (gatilho dir.), 5 = R (pegar dir.), 0 = A, 6 = ZL, 4 = L, 2 = baixo/X, 10 = menu
  const KEYMAP = {
    KeyE: 5, KeyQ: 4, KeyF: 6, Space: 0, KeyR: 2, KeyX: 1, KeyY: 3, Tab: 10, KeyM: 10,
    KeyT: 11, Digit1: 12, Digit2: 13,
  };
  function updateVirtualPad() {
    virtPad.fill(false);
    for (const k of keys) if (KEYMAP[k] !== undefined) virtPad[KEYMAP[k]] = true;
    if (mouseBtn[0]) virtPad[7] = true;
    if (mouseBtn[2]) virtPad[5] = true;
    if (mouseBtn[1]) virtPad[6] = true;
  }

  function onKey(e, down) {
    if (e.code === 'Tab') e.preventDefault();
    if (down) keys.add(e.code); else keys.delete(e.code);
    if (down && e.code === 'KeyV') hands.right.punch = 0.0001;
    if (down && e.code === 'KeyC') hands.left.punch = 0.0001;
  }

  I.attach = function (canvas) {
    I.canvas = canvas;
    window.addEventListener('keydown', (e) => onKey(e, true));
    window.addEventListener('keyup', (e) => onKey(e, false));
    window.addEventListener('blur', () => { keys.clear(); mouseBtn.fill(false); });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    canvas.addEventListener('mousedown', (e) => {
      if (W.ui3d && W.ui3d.pointerDown(e)) return;
      if (I.mode === 'desktop' && document.pointerLockElement !== canvas && !(W.ui3d && W.ui3d.anyVisible())) {
        canvas.requestPointerLock && canvas.requestPointerLock();
        return;
      }
      mouseBtn[e.button] = true;
    });
    window.addEventListener('mouseup', (e) => { mouseBtn[e.button] = false; });
    window.addEventListener('mousemove', (e) => {
      if (document.pointerLockElement === canvas) {
        I.yaw -= e.movementX * 0.0025;
        I.pitch -= e.movementY * 0.0025;
        I.pitch = Math.max(-1.45, Math.min(1.45, I.pitch));
      } else if (W.ui3d) {
        W.ui3d.pointerMove(e);
      }
    });
    canvas.addEventListener('wheel', (e) => {
      I.reach = Math.max(0.2, Math.min(0.62, I.reach - e.deltaY * 0.0006));
    }, { passive: true });
    // toque (celular): arrastar gira (VR Box sem giroscopio) e toque = clique no painel
    let lastTouch = null;
    canvas.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      lastTouch = { x: t.clientX, y: t.clientY, t: performance.now() };
    }, { passive: true });
    canvas.addEventListener('touchmove', (e) => {
      const t = e.touches[0];
      if (lastTouch) {
        dragYaw -= (t.clientX - lastTouch.x) * 0.004;
        if (!gyroQ) I.pitch = Math.max(-1.4, Math.min(1.4, I.pitch - (t.clientY - lastTouch.y) * 0.004));
        lastTouch.x = t.clientX; lastTouch.y = t.clientY;
      }
    }, { passive: true });
    canvas.addEventListener('touchend', () => {
      if (lastTouch && performance.now() - lastTouch.t < 250 && W.ui3d) W.ui3d.gazeClick();
      lastTouch = null;
    }, { passive: true });
  };

  // ------------------------------------------------------------------------
  // Giroscopio (VR Box)
  // ------------------------------------------------------------------------
  const zee = new THREE.Vector3(0, 0, 1);
  const euler = new THREE.Euler();
  const q0 = new THREE.Quaternion();
  const q1 = new THREE.Quaternion(-Math.sqrt(0.5), 0, 0, Math.sqrt(0.5));
  function onOrient(e) {
    if (e.alpha == null) return;
    const a = THREE.MathUtils.degToRad(e.alpha), b = THREE.MathUtils.degToRad(e.beta), g = THREE.MathUtils.degToRad(e.gamma);
    const orient = THREE.MathUtils.degToRad((screen.orientation && screen.orientation.angle) || window.orientation || 0);
    euler.set(b, a, -g, 'YXZ');
    const q = new THREE.Quaternion().setFromEuler(euler);
    q.multiply(q1);
    q.multiply(q0.setFromAxisAngle(zee, -orient));
    gyroQ = q;
  }
  I.enableGyro = async function () {
    try {
      if (window.DeviceOrientationEvent && typeof DeviceOrientationEvent.requestPermission === 'function') {
        await DeviceOrientationEvent.requestPermission();
      }
    } catch (e) { /* sem permissao: fica no arrastar */ }
    window.addEventListener('deviceorientation', onOrient);
  };

  // ------------------------------------------------------------------------
  // Gamepads (Joy-Con)
  // ------------------------------------------------------------------------
  function pollPads() {
    realPads = [];
    const list = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const g of list) if (g && g.connected) realPads.push(g);
  }
  function padBtn(g, b) {
    const x = g.buttons[b];
    if (!x) return false;
    return typeof x === 'object' ? (x.pressed || x.value > 0.5) : x > 0.5;
  }
  // GetKey("joystick button 5") / ("joystick 2 button 5")
  function getKey(name) {
    let m = /^joystick (\d+) button (\d+)$/.exec(name);
    if (m) {
      const j = parseInt(m[1], 10) - 1, b = parseInt(m[2], 10);
      if (j === 0 && (virtPad[b] || xrPad[b])) return true;
      const g = realPads[j];
      return g ? padBtn(g, b) || (b === 10 && (padBtn(g, 8) || padBtn(g, 9))) : false;
    }
    m = /^joystick button (\d+)$/.exec(name);
    if (m) {
      const b = parseInt(m[1], 10);
      if (virtPad[b] || xrPad[b]) return true;
      for (const g of realPads) {
        if (padBtn(g, b)) return true;
        if (b === 10 && (padBtn(g, 8) || padBtn(g, 9))) return true;
      }
      return false;
    }
    const k = name.length === 1 ? 'Key' + name.toUpperCase() : null;
    return k ? keys.has(k) : false;
  }
  function getAxis(n) {
    if (n === 'Horizontal') return axes.h;
    if (n === 'Vertical') return axes.v;
    return 0;
  }

  // ------------------------------------------------------------------------
  // Maos pela camera (MediaPipe) — opcional, precisa de internet
  // ------------------------------------------------------------------------
  const MP_VER = '0.10.14';
  I.enableCameraHands = async function (onStatus) {
    const say = (s) => onStatus && onStatus(s);
    try {
      say('carregando MediaPipe...');
      const vision = await import('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@' + MP_VER + '/vision_bundle.mjs');
      const fileset = await vision.FilesetResolver.forVisionTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@' + MP_VER + '/wasm');
      const hl = await vision.HandLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task', delegate: 'GPU' },
        runningMode: 'VIDEO', numHands: 2,
      });
      say('abrindo a camera...');
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: 640, height: 480 }, audio: false });
      const video = document.createElement('video');
      video.srcObject = stream; video.playsInline = true; video.muted = true;
      await video.play();
      I.camVideo = video;
      camHands = { left: null, right: null, hl, video, last: -1, front: false };
      say('maos pela camera: ligado');
      return true;
    } catch (e) {
      say('camera indisponivel: ' + e.message);
      return false;
    }
  };

  const HFOV = 66 * Math.PI / 180;
  function updateCameraHands() {
    const c = camHands;
    if (!c || c.video.readyState < 2) return;
    const now = performance.now();
    if (c.video.currentTime === c.last) return;
    c.last = c.video.currentTime;
    const res = c.hl.detectForVideo(c.video, now);
    c.left = null; c.right = null;
    const aspect = c.video.videoWidth / Math.max(1, c.video.videoHeight);
    const th = Math.tan(HFOV / 2), tv = th / aspect;
    for (let k = 0; k < (res.landmarks || []).length; k++) {
      const lm = res.landmarks[k], wl = res.worldLandmarks[k];
      let label = (res.handednesses[k] && res.handednesses[k][0] && res.handednesses[k][0].categoryName) || 'Right';
      // camera traseira nao e espelhada: o rotulo do MediaPipe vem trocado
      label = label === 'Left' ? 'right' : 'left';
      const dir = (p) => [(p.x - 0.5) * 2 * th, -(p.y - 0.5) * 2 * tv];
      const d0 = dir(lm[0]), d9 = dir(lm[9]);
      const imgLen = Math.hypot(d0[0] - d9[0], d0[1] - d9[1]);
      const realLen = Math.hypot(wl[0].x - wl[9].x, wl[0].y - wl[9].y, wl[0].z - wl[9].z) || 0.09;
      const depth = Math.max(0.15, Math.min(1.2, realLen / Math.max(imgLen, 1e-3)));
      const wrist = [d0[0] * depth, d0[1] * depth, depth];
      const pts = [];
      for (let i = 0; i < 21; i++) {
        pts.push([wrist[0] + (wl[i].x - wl[0].x), wrist[1] - (wl[i].y - wl[0].y), wrist[2] + (wl[i].z - wl[0].z)]);
      }
      c[label] = pts;   // espaco da cabeca: x direita, y cima, z frente
    }
  }

  // ------------------------------------------------------------------------
  // Atualizacao por frame
  // ------------------------------------------------------------------------
  const v3 = new THREE.Vector3(), r3 = new THREE.Vector3(), u3 = new THREE.Vector3(), f3 = new THREE.Vector3();
  const XR_JOINTS = [
    'wrist',
    'thumb-metacarpal', 'thumb-phalanx-proximal', 'thumb-phalanx-distal', 'thumb-tip',
    'index-finger-phalanx-proximal', 'index-finger-phalanx-intermediate', 'index-finger-phalanx-distal', 'index-finger-tip',
    'middle-finger-phalanx-proximal', 'middle-finger-phalanx-intermediate', 'middle-finger-phalanx-distal', 'middle-finger-tip',
    'ring-finger-phalanx-proximal', 'ring-finger-phalanx-intermediate', 'ring-finger-phalanx-distal', 'ring-finger-tip',
    'pinky-finger-phalanx-proximal', 'pinky-finger-phalanx-intermediate', 'pinky-finger-phalanx-distal', 'pinky-finger-tip',
  ];

  function headBasis() {
    r3.set(1, 0, 0).applyQuaternion(head.quat);
    u3.set(0, 1, 0).applyQuaternion(head.quat);
    f3.set(0, 0, -1).applyQuaternion(head.quat);   // frente no three = -z
  }

  function virtualHand(side, dt, curl) {
    const h = hands[side];
    const sx = side === 'right' ? 1 : -1;
    // mao segue o olhar (yaw + parte do pitch), a frente e um pouco abaixo do rosto
    const yawQ = new THREE.Quaternion().setFromEuler(new THREE.Euler(I.pitchForHands(), I.headYaw(), 0, 'YXZ'));
    const R = new THREE.Vector3(1, 0, 0).applyQuaternion(yawQ);
    const U = new THREE.Vector3(0, 1, 0).applyQuaternion(yawQ);
    const F = new THREE.Vector3(0, 0, -1).applyQuaternion(yawQ);
    if (h.punch > 0) { h.punch += dt / 0.28; if (h.punch >= 1) h.punch = 0; }
    const pk = h.punch > 0 ? Math.sin(h.punch * Math.PI) * 0.34 : 0;
    const wrist = head.pos.clone()
      .addScaledVector(R, 0.17 * sx)
      .addScaledVector(U, -0.24)
      .addScaledVector(F, I.reach - 0.12 + pk);
    // palma virada para dentro, polegar para cima, dedos para a frente
    const hr = U.clone().multiplyScalar(-sx);
    const hu = R.clone().multiplyScalar(sx);
    placeHand(h, side, wrist, hr, hu, F, curl);
    h.gesture = gestureFromCurl(curl);
  }
  I.pitchForHands = () => {
    const e = new THREE.Euler().setFromQuaternion(head.quat, 'YXZ');
    return e.x * 0.85;
  };
  I.headYaw = () => {
    const e = new THREE.Euler().setFromQuaternion(head.quat, 'YXZ');
    return e.y;
  };

  I.update = function (dt, xrFrame) {
    pollPads();
    updateVirtualPad();
    // eixos: teclado + gamepads
    let h = 0, v = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) v += 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) v -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) h += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) h -= 1;
    for (const g of realPads) {
      const ax = g.axes[0] || 0, ay = g.axes[1] || 0;
      if (Math.abs(ax) > 0.15) h += ax;
      if (Math.abs(ay) > 0.15) v -= ay;
    }
    axes.h = Math.max(-1, Math.min(1, h + (I.xrAxes ? I.xrAxes.h : 0)));
    axes.v = Math.max(-1, Math.min(1, v + (I.xrAxes ? I.xrAxes.v : 0)));

    // cabeca
    if (I.mode === 'xr' && xrFrame) {
      updateXR(xrFrame);
    } else {
      head.pos.set(0, 0, 0);
      if (I.mode === 'vrbox' && gyroQ) {
        const yawFix = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), dragYaw);
        head.quat.copy(yawFix).multiply(gyroQ);
      } else {
        head.quat.setFromEuler(new THREE.Euler(I.pitch, I.yaw + dragYaw, 0, 'YXZ'));
      }
      // maos
      if (camHands) updateCameraHands();
      headBasis();
      for (const side of ['left', 'right']) {
        const hh = hands[side];
        const cp = camHands && camHands[side];
        if (cp) {
          for (let i = 0; i < 21; i++) {
            const p = cp[i];
            v3.copy(head.pos).addScaledVector(r3, p[0]).addScaledVector(u3, p[1]).addScaledVector(f3, p[2]);
            hh.pts[i][0] = v3.x; hh.pts[i][1] = v3.y; hh.pts[i][2] = -v3.z;
          }
          hh.ok = true;
          const curl = curlFromPts(cp);
          hh.gesture = gestureFromCurl(curl);
        } else if (I.virtualHands) {
          const b = side === 'right';
          const grip = getKey('joystick button ' + (b ? 5 : 4));
          const trig = getKey('joystick button ' + (b ? 7 : 6));
          const g = grip ? 1 : 0, t = trig ? 1 : 0;
          virtualHand(side, dt, [g * 0.6, t, g, g, g]);
        } else {
          hh.ok = false;
        }
      }
    }
    if (W.headNode) {
      W.headNode.position.copy(head.pos);
      W.headNode.quaternion.copy(head.quat);
      W.headNode.updateMatrix();
      W.headNode.matrixAutoUpdate = true;
    }
  };

  // ------------------------------------------------------------------------
  // WebXR
  // ------------------------------------------------------------------------
  let xrRef = null;
  function updateXR(frame) {
    const session = frame.session;
    if (!xrRef) xrRef = W.renderer.xr.getReferenceSpace();
    const pose = frame.getViewerPose(xrRef);
    if (pose) {
      const t = pose.transform;
      head.pos.set(t.position.x, t.position.y, t.position.z);
      head.quat.set(t.orientation.x, t.orientation.y, t.orientation.z, t.orientation.w);
    }
    xrPad.fill(false);
    I.xrAxes = { h: 0, v: 0 };
    hands.left.ok = false; hands.right.ok = false;
    headBasis();
    for (const src of session.inputSources) {
      const side = src.handedness === 'left' ? 'left' : 'right';
      const h = hands[side];
      if (src.hand) {
        let okAll = true;
        for (let i = 0; i < 21; i++) {
          const j = src.hand.get(XR_JOINTS[i]);
          const jp = j && frame.getJointPose(j, xrRef);
          if (!jp) { okAll = false; break; }
          const p = jp.transform.position;
          h.pts[i][0] = p.x; h.pts[i][1] = p.y; h.pts[i][2] = -p.z;
        }
        h.ok = okAll;
        if (okAll) {
          const pts3 = h.pts.map((p) => [p[0], p[1], -p[2]]);
          h.gesture = gestureFromCurl(curlFromPts(pts3));
        }
      } else if (src.gamepad && src.gripSpace) {
        const gp = src.gamepad;
        const b = (i) => gp.buttons[i] && (gp.buttons[i].pressed || gp.buttons[i].value > 0.5);
        const trig = b(0), squeeze = b(1);
        if (side === 'right') {
          xrPad[7] = trig; xrPad[5] = squeeze; xrPad[0] = b(4); xrPad[1] = b(5); xrPad[11] = b(3);
        } else {
          xrPad[6] = trig; xrPad[4] = squeeze; xrPad[2] = b(4); xrPad[3] = b(5); xrPad[10] = b(3) || b(5);
          I.xrAxes.h += gp.axes[2] || 0;
          I.xrAxes.v -= gp.axes[3] || 0;
        }
        const gpose = frame.getPose(src.gripSpace, xrRef);
        if (gpose) {
          const o = gpose.transform.orientation, p = gpose.transform.position;
          const q = new THREE.Quaternion(o.x, o.y, o.z, o.w);
          const sx = side === 'right' ? 1 : -1;
          const F = new THREE.Vector3(0, 0, -1).applyQuaternion(q);
          const U = new THREE.Vector3(0, 1, 0).applyQuaternion(q);
          const R = new THREE.Vector3(1, 0, 0).applyQuaternion(q);
          const wrist = new THREE.Vector3(p.x, p.y, p.z).addScaledVector(F, -0.06);
          const g = squeeze ? 1 : 0;
          placeHand(h, side, wrist, U.clone().multiplyScalar(-sx), R.clone().multiplyScalar(sx), F, [g * 0.6, trig ? 1 : 0, g, g, g]);
          h.gesture = gestureFromCurl([g * 0.6, trig ? 1 : 0, g, g, g]);
        }
      }
    }
  }

  I.enterXR = async function () {
    const session = await navigator.xr.requestSession('immersive-vr', { optionalFeatures: ['local-floor', 'hand-tracking'] });
    W.renderer.xr.enabled = true;
    W.renderer.xr.setReferenceSpaceType('local-floor');
    await W.renderer.xr.setSession(session);
    I.mode = 'xr';
    xrRef = null;
    session.addEventListener('end', () => { I.mode = 'desktop'; W.renderer.xr.enabled = false; });
  };

  // ------------------------------------------------------------------------
  // Render (PC / VR Box / XR)
  // ------------------------------------------------------------------------
  let camera, stereo;
  I.setupCamera = function () {
    camera = new THREE.PerspectiveCamera(75, 1, 0.03, 600);
    W.camera = camera;
    stereo = new THREE.StereoCamera();
    stereo.eyeSep = 0.064;
    const resize = () => {
      const w = window.innerWidth, h = window.innerHeight;
      W.renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.fov = I.mode === 'vrbox' ? 90 : 75;
      camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', resize);
    I.resize = resize;
    resize();
  };

  W.render = function () {
    const R = W.renderer;
    if (I.mode === 'xr') {
      camera.position.set(0, 0, 0);
      camera.quaternion.identity();
      R.render(W.scene, camera);
      return;
    }
    camera.position.copy(head.pos);
    camera.quaternion.copy(head.quat);
    camera.updateMatrixWorld();
    const size = R.getSize(new THREE.Vector2());
    if (I.mode === 'vrbox') {
      camera.aspect = (size.x / 2) / size.y;
      camera.updateProjectionMatrix();
      stereo.update(camera);
      R.setScissorTest(true);
      R.setScissor(0, 0, size.x / 2, size.y); R.setViewport(0, 0, size.x / 2, size.y);
      R.render(W.scene, stereo.cameraL);
      R.setScissor(size.x / 2, 0, size.x / 2, size.y); R.setViewport(size.x / 2, 0, size.x / 2, size.y);
      R.render(W.scene, stereo.cameraR);
      R.setScissorTest(false);
      R.setViewport(0, 0, size.x, size.y);
    } else {
      camera.aspect = size.x / size.y;
      camera.updateProjectionMatrix();
      R.render(W.scene, camera);
    }
  };

  // algum botao de "confirmar" (A ou gatilho) apertado — para clicar nos paineis no VR Box/XR
  I.anyButton = function () {
    if (virtPad[0] || virtPad[7] || xrPad[0] || xrPad[7]) return true;
    for (const g of realPads) if (padBtn(g, 0) || padBtn(g, 7) || padBtn(g, 1)) return true;
    return false;
  };

  I.trackingMode = () => (I.mode === 'xr' ? '6dof' : '3dof');
  I.head = head;
  I.hands = hands;

  // ------------------------------------------------------------------------
  // Funcoes para o Lua
  // ------------------------------------------------------------------------
  I.register = function () {
    const { reg, lua } = W;
    reg('H_head', (Ls) => {
      // posicao/rotacao da cabeca no sistema da Unity
      lua.pushN(Ls, head.pos.x); lua.pushN(Ls, head.pos.y); lua.pushN(Ls, -head.pos.z);
      lua.pushN(Ls, -head.quat.x); lua.pushN(Ls, -head.quat.y); lua.pushN(Ls, head.quat.z); lua.pushN(Ls, head.quat.w);
      return 7;
    });
    reg('H_handok', (Ls) => { lua.pushB(Ls, hands[lua.int(Ls, 1) === 0 ? 'left' : 'right'].ok); return 1; });
    reg('H_joint', (Ls) => {
      const h = hands[lua.int(Ls, 1) === 0 ? 'left' : 'right'];
      const i = Math.max(0, Math.min(20, lua.int(Ls, 2)));
      const p = h.pts[i];
      lua.pushN(Ls, p[0]); lua.pushN(Ls, p[1]); lua.pushN(Ls, p[2]);
      return 3;
    });
    reg('H_gesture', (Ls) => { lua.pushS(Ls, hands[lua.int(Ls, 1) === 0 ? 'left' : 'right'].gesture); return 1; });
    reg('H_pinch', (Ls) => { lua.pushN(Ls, hands[lua.int(Ls, 1) === 0 ? 'left' : 'right'].pinch); return 1; });
    reg('H_key', (Ls) => { lua.pushB(Ls, getKey(lua.str(Ls, 1) || '')); return 1; });
    reg('H_axis', (Ls) => { lua.pushN(Ls, getAxis(lua.str(Ls, 1) || '')); return 1; });
    reg('H_joynames', (Ls) => {
      const names = realPads.map((g) => g.id);
      if (I.mode === 'xr') names.push('WebXR controllers');
      lua.pushS(Ls, names.join('\n'));
      return 1;
    });
  };
})();
