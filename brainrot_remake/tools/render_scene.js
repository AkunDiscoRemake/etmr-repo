// render_scene.js — renderiza uma cena exportada pelo mock (JSON) usando three.js no Chromium headless.
// Uso: node render_scene.js <scene.json> <out.png> [--cam head|x,y,z:tx,ty,tz] [--w 1280 --h 720] [--fov 75]
// Converte do sistema mao-esquerda da Unity para o mao-direita do three.js (z -> -z).

const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PW_PATH || 'playwright');

const args = process.argv.slice(2);
const scenePath = args[0];
const outPath = args[1];
function opt(name, def) {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
}
const W = parseInt(opt('w', '1280'));
const Hh = parseInt(opt('h', '720'));
const cam = opt('cam', 'head');
const fov = parseFloat(opt('fov', '75'));
const imagesDir = path.resolve(__dirname, '..', 'images');
const threePath = process.env.THREE_PATH;

(async () => {
  const scene = JSON.parse(fs.readFileSync(scenePath, 'utf8'));
  const textures = {};
  for (const o of scene.objs) {
    if (o.t && !textures[o.t]) {
      const p = path.join(path.resolve(__dirname, '..'), o.t);
      if (fs.existsSync(p)) textures[o.t] = 'data:image/png;base64,' + fs.readFileSync(p).toString('base64');
    }
  }
  const threeSrc = fs.readFileSync(threePath, 'utf8');
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: W, height: Hh } });
  page.on('console', m => console.log('[page]', m.text()));
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  await page.setContent(`<html><body style="margin:0;background:#000"><canvas id=c width=${W} height=${Hh}></canvas></body></html>`);
  await page.addScriptTag({ content: threeSrc });
  await page.evaluate(async ({ scene, textures, W, Hh, cam, fov }) => {
    const T = THREE;
    const renderer = new T.WebGLRenderer({ canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true });
    renderer.setSize(W, Hh, false);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    renderer.outputColorSpace = T.SRGBColorSpace;
    renderer.toneMapping = T.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    const s = new T.Scene();
    s.background = new T.Color(0x0b0d12);
    s.add(new T.HemisphereLight(0xdfe8ff, 0x3a3530, 1.1));
    const sun = new T.DirectionalLight(0xffffff, 1.6);
    sun.position.set(4, 10, 3);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const sc = sun.shadow.camera; sc.left = -14; sc.right = 14; sc.top = 14; sc.bottom = -14; sc.far = 40;
    s.add(sun);
    const geos = {
      cube: new T.BoxGeometry(1, 1, 1),
      sphere: new T.SphereGeometry(0.5, 24, 16),
      capsule: new T.CapsuleGeometry(0.5, 1, 8, 16),
      cylinder: new T.CylinderGeometry(0.5, 0.5, 2, 24),
      plane: new T.PlaneGeometry(10, 10).rotateX(-Math.PI / 2),
      quad: new T.PlaneGeometry(1, 1),
    };
    const loader = new T.TextureLoader();
    const texCache = {};
    async function tex(k) {
      if (!textures[k]) return null;
      if (!texCache[k]) {
        texCache[k] = await new Promise(r => loader.load(textures[k], t => { t.colorSpace = T.SRGBColorSpace; t.anisotropy = 8; r(t); }));
      }
      return texCache[k];
    }
    for (const o of scene.objs) {
      if (o.c[3] <= 0.01) continue;
      let map = o.t ? await tex(o.t) : null;
      if (map && o.ts) {
        map = map.clone(); map.needsUpdate = true;
        map.wrapS = map.wrapT = T.RepeatWrapping; map.repeat.set(o.ts[0], o.ts[1]);
      }
      const mat = o.ul ? new T.MeshBasicMaterial({ color: new T.Color(o.c[0], o.c[1], o.c[2]), map, transparent: true, alphaTest: 0.02, side: T.DoubleSide }) : new T.MeshStandardMaterial({
        color: new T.Color(o.c[0], o.c[1], o.c[2]),
        map,
        metalness: o.m != null ? o.m : 0.1,
        roughness: o.m != null ? 0.35 : 0.7,
        side: o.k === 'quad' ? T.DoubleSide : T.FrontSide,
      });
      if (o.e && !o.ul) { mat.emissive = new T.Color(o.e[0], o.e[1], o.e[2]); }
      const mesh = new T.Mesh(geos[o.k], mat);
      // unity (mao esquerda) -> three (mao direita): M' = S M S, S = diag(1,1,-1)
      const r = o.r, u = o.u, f = o.f;
      const m = new T.Matrix4();
      m.set(
        r[0], u[0], -f[0], o.p[0],
        r[1], u[1], -f[1], o.p[1],
        -r[2], -u[2], f[2], -o.p[2],
        0, 0, 0, 1);
      mesh.matrixAutoUpdate = false;
      mesh.matrix.copy(m);
      mesh.castShadow = o.k !== 'plane' && o.k !== 'quad';
      mesh.receiveShadow = true;
      s.add(mesh);
    }
    const camera = new T.PerspectiveCamera(fov, W / Hh, 0.01, 400);
    if (cam === 'head') {
      const [hx, hy, hz] = scene.head;
      const [qx, qy, qz, qw] = scene.q;
      // forward/up da Unity a partir do quaternion
      const fx = 2 * (qx * qz + qw * qy), fy = 2 * (qy * qz - qw * qx), fz = 1 - 2 * (qx * qx + qy * qy);
      const ux = 2 * (qx * qy - qw * qz), uy = 1 - 2 * (qx * qx + qz * qz), uz = 2 * (qy * qz + qw * qx);
      camera.position.set(hx, hy, -hz);
      camera.up.set(ux, uy, -uz);
      camera.lookAt(hx + fx, hy + fy, -(hz + fz));
    } else if (cam.startsWith('L')) {
      // camera em coordenadas locais do jogo: mundo = rotY(p, yaw) + T
      const rig = scene.rig;
      const tw = (p) => {
        const r = rig.yaw * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
        return [p[0] * c + p[2] * s + rig.T[0], p[1] + rig.T[1], -p[0] * s + p[2] * c + rig.T[2]];
      };
      const [a, b] = cam.slice(1).split(':');
      const P = tw(a.split(',').map(Number)), Tg = tw(b.split(',').map(Number));
      camera.position.set(P[0], P[1], -P[2]);
      camera.lookAt(Tg[0], Tg[1], -Tg[2]);
    } else {
      const [a, b] = cam.split(':');
      const [x, y, z] = a.split(',').map(Number);
      const [tx, ty, tz] = b.split(',').map(Number);
      camera.position.set(x, y, -z);
      camera.lookAt(tx, ty, -tz);
    }
    renderer.render(s, camera);
  }, { scene, textures, W, Hh, cam, fov });
  const data = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
  fs.writeFileSync(outPath, Buffer.from(data.split(',')[1], 'base64'));
  await browser.close();
  console.log('ok', outPath, scene.objs.length, 'objs');
})();
