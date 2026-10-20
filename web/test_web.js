// test_web.js — abre um jogo HTML no Chromium headless, inicia no modo PC, simula
// teclas/mouse e verifica: sem erros de JS/Lua, FPS e screenshots.
// Uso: node web/test_web.js web/dist/SuperhotRemake.html out.png [segundos] [roteiro]
const path = require('path');
const { chromium } = require(process.env.PW_PATH || 'playwright');

const file = path.resolve(process.argv[2]);
const outPng = process.argv[3] || 'web_test.png';
const secs = parseFloat(process.argv[4] || '8');
const script = process.argv[5] || 'walk';

(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'].concat(process.env.NOPROXY ? ['--no-proxy-server'] : []) });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  const logs = [];
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error') errors.push(t);
    logs.push(m.type() + ': ' + t);
  });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.goto(process.env.HTTPURL ? process.env.HTTPURL : 'file://' + file);
  await page.waitForFunction(() => window.EMRWEB && window.EMRWEB.go, null, { timeout: 60000 });
  const t0 = Date.now();
  await page.evaluate(() => window.EMRWEB.go('desktop'));
  await page.waitForFunction(() => window.EMRWEB.ready === true, null, { timeout: 120000 });
  const loadMs = Date.now() - t0;
  // roteiro: anda, olha em volta, aperta botoes
  const steps = Math.floor(secs * 2);
  for (let i = 0; i < steps; i++) {
    if (script === 'walk') {
      if (i % 6 === 0) await page.keyboard.down('KeyW');
      if (i % 6 === 3) await page.keyboard.up('KeyW');
      if (i % 5 === 2) await page.evaluate(() => { window.EMRWEB.input.yaw += 0.6; });
      if (i % 7 === 4) { await page.keyboard.down('KeyE'); }
      if (i % 7 === 6) { await page.keyboard.up('KeyE'); }
      if (i === 6) await page.keyboard.press('Tab');
      if (i === 9) await page.keyboard.press('Tab');
    }
    await page.waitForTimeout(500);
  }
  const info = await page.evaluate(() => ({
    nodes: window.EMRWEB.nodes.size,
    frameMs: window.EMRWEB.frameMs,
    luaLogs: (window.EMRWEB.logs || []).slice(-40),
    phys: !!window.EMRWEB.physics,
  }));
  await page.screenshot({ path: outPng });
  console.log('carregou em', loadMs, 'ms | objetos', info.nodes, '| lua+host', info.frameMs.toFixed(2), 'ms/frame | fisica', info.phys);
  const luaErr = info.luaLogs.filter((l) => l.startsWith('ERROR'));
  for (const l of info.luaLogs.filter((l) => l.startsWith('WARN'))) console.log('  ', l.slice(0, 200));
  for (const e of luaErr) console.log('LUA ERRO:', e.slice(0, 400));
  for (const e of errors.slice(0, 15)) console.log('JS ERRO:', e.slice(0, 400));
  await browser.close();
  console.log(errors.length || luaErr.length ? 'FALHOU' : 'OK');
  process.exit(errors.length || luaErr.length ? 1 : 0);
})();
