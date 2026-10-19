#!/usr/bin/env python3
"""Roda o jogo no EMRAPI falso (Lua 5.3 via lupa) com um cenario roteirizado.

Uso:
  python3 tools/run_sim.py --scenario smoke --seconds 20 [--nocs] [--snap 3,10] [--out DIR]

Falha (exit 1) se houver erro Lua ou LogError do jogo.
"""
import argparse
import json
import os
import sys
import time

from lupa import lua53

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", default="smoke")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--nocs", action="store_true", help="simula plataforma SEM acesso a CS.*")
    ap.add_argument("--snap", default="", help="tempos (s) para exportar a cena, separados por virgula")
    ap.add_argument("--out", default=os.path.join(ROOT, "tools", "out"))
    ap.add_argument("--tracking", default="6dof")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--lang", default="", help="forca o idioma salvo (en/ru/pt)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    L = lua53.LuaRuntime(unpack_returned_tuples=True)
    L.execute('package.path = "%s/scripts/?.lua;%s/tools/?.lua;" .. package.path' % (ROOT, ROOT))
    L.execute("math.randomseed(%d)" % a.seed)
    L.execute(open(os.path.join(ROOT, "tools", "mock_emrapi.lua"), encoding="utf8").read())
    L.execute('MOCK.trackingMode = "%s"' % a.tracking)
    if a.lang:
        L.execute('MOCK.storage.lang = "%s"' % a.lang)
    if not a.nocs:
        L.execute("MOCK.installCS()")
    L.execute("MOCK.installMP(1)")   # o jogo e so online: sala com um jogador (mestre)
    L.execute(open(os.path.join(ROOT, "tools", "scenarios.lua"), encoding="utf8").read())
    main_src = open(os.path.join(ROOT, "scripts", "main.lua"), encoding="utf8").read()
    L.execute(main_src)
    # modo estrito: qualquer global nova criada pelo jogo vira erro
    L.execute("""
        local allowed = { OnStart=1, OnUpdate=1, OnPause=1, OnResume=1, OnDestroy=1, BRAINROT=1, SCEN=1 }
        setmetatable(_G, {
          __newindex = function(t, k, v)
            if not allowed[k] then error("global nova: " .. tostring(k), 2) end
            rawset(t, k, v)
          end,
          __index = function(t, k) error("global indefinida: " .. tostring(k), 2) end,
        })
    """)

    snaps = sorted(float(x) for x in a.snap.split(",") if x.strip())
    dt = 1 / 60
    frames = int(a.seconds / dt)
    L.execute('SCEN = SCENARIOS["%s"]' % a.scenario)
    L.execute("SCEN.setup()")
    L.execute("OnStart()")
    t0 = time.time()
    lua_err = None
    for f in range(frames):
        try:
            L.execute("""
                MOCK.time = MOCK.time + %f
                SCEN.step(MOCK.time, %f)
                MOCK.tickTimers()
                MOCK.tickTweens()
                OnUpdate(%f)
                MOCK.tickPhysics(%f)
                if MOCK.mp.wantJoin then
                    MOCK.mp.inRoom = true; MOCK.mp.master = true; MOCK.mp.players[1] = "p1"
                    local cb = MOCK.mp.wantJoin; MOCK.mp.wantJoin = nil; cb(true)
                end
                MOCK.mp.outbox = {}
            """ % (dt, dt, dt, dt))
        except Exception as e:  # erro fora do pcall do jogo (cenario/mock)
            lua_err = "frame %d: %s" % (f, e)
            break
        tnow = (f + 1) * dt
        while snaps and tnow >= snaps[0]:
            s = snaps.pop(0)
            js = L.eval("MOCK.exportScene()")
            try:  # transformacao do mundo do jogo (para camera em coordenadas locais)
                rig = L.eval('BRAINROT and string.format(\'{"T":[%f,%f,%f],"yaw":%f}\', BRAINROT.rig.T[1], BRAINROT.rig.T[2], BRAINROT.rig.T[3], BRAINROT.rig.yaw) or "null"')
                js = js[:-1] + ',"rig":' + rig + '}'
            except Exception:
                pass
            p = os.path.join(a.out, "%s_%05.1f.json" % (a.scenario, s))
            open(p, "w").write(js)
            print("snapshot", p, "objs=%d" % L.eval("MOCK.countObjects()"))
    L.execute("OnDestroy()")
    elapsed = time.time() - t0

    logs = [L.eval("MOCK.log")[i] for i in range(1, L.eval("#MOCK.log") + 1)]
    errors = [l for l in logs if l.startswith("ERROR")]
    warns = [l for l in logs if l.startswith("WARN")]
    try:
        report = L.eval("SCEN.report and SCEN.report() or ''")
    except Exception as e:  # relatorio quebrado nao esconde os erros do jogo
        report = "(relatorio falhou: %s)" % str(e).splitlines()[0]
    print("frames=%d tempo=%.1fs (%.2f ms/frame)  objetos=%d  sons=%d" % (
        frames, elapsed, elapsed / max(1, frames) * 1000, L.eval("MOCK.countObjects()"), L.eval("#MOCK.sounds")))
    for w in warns[:10]:
        print("  ", w)
    if os.environ.get("SIMLOG"):
        for l in logs:
            print("  ", l)
    if report:
        print("relatorio:", report)
    if lua_err:
        print("ERRO LUA (fora do jogo):", lua_err)
    for e in errors[:10]:
        print("ERRO:", e)
    tex = L.eval("MOCK.textures") or {}
    missing = [k for k in tex if not os.path.isfile(os.path.join(ROOT, k))]
    for m in missing:
        print("TEXTURA FALTANDO:", m)
    snd = [L.eval("MOCK.sounds")[i] for i in range(1, L.eval("#MOCK.sounds") + 1)]
    missing_snd = sorted(set(x for x in snd if not os.path.isfile(os.path.join(ROOT, x))))
    for m in missing_snd:
        print("SOM FALTANDO:", m)
    if lua_err or errors or missing or missing_snd:
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
