#!/usr/bin/env python3
"""Teste ONLINE: dois clientes do jogo (lupa) conversando por um Photon falso.

Cliente A cria a sala (mestre), cliente B entra depois. O roteiro (tools/mp_scenarios.lua)
faz B andar ate a base de A, roubar um brainrot e levar para casa, enquanto A compra
na esteira. Verifica se os dois mundos concordam (esteira, bases, roubo, entrega).
"""
import os
import sys
import time

from lupa import lua53

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def make_client(actor, seed):
    L = lua53.LuaRuntime(unpack_returned_tuples=True)
    L.execute('package.path = "%s/scripts/?.lua;%s/tools/?.lua;" .. package.path' % (ROOT, ROOT))
    L.execute("math.randomseed(%d)" % seed)
    L.execute("os.time = function() return %d end" % (1700000000 + seed))
    L.execute(open(os.path.join(ROOT, "tools", "mock_emrapi.lua"), encoding="utf8").read())
    L.execute("MOCK.installCS()")
    L.execute('MOCK.installMP(%d)' % actor)
    L.execute('MOCK.storage.tutDone = true')
    L.execute(open(os.path.join(ROOT, "tools", "scenarios.lua"), encoding="utf8").read())
    L.execute(open(os.path.join(ROOT, "tools", "mp_scenarios.lua"), encoding="utf8").read())
    L.execute(open(os.path.join(ROOT, "scripts", "main.lua"), encoding="utf8").read())
    L.execute('SCEN = MPSCEN; SCEN.setup(%d)' % actor)
    L.execute("OnStart()")
    return L


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 90
    leave_at = float(sys.argv[2]) if len(sys.argv) > 2 else None   # cliente 2 sai da sala nesse tempo
    A = make_client(1, 11)
    B = None
    clients = {1: A}
    dt = 1 / 60
    t0 = time.time()
    joinedB = False
    for f in range(int(secs / dt)):
        t = (f + 1) * dt
        # B entra na sala aos 3 s
        if leave_at and t >= leave_at and 2 in clients:
            del clients[2]
            A.execute("MOCK.mp.players[2] = nil; if MOCK.mp.onLeft then MOCK.mp.onLeft(2, 'p2') end")
            print("cliente 2 saiu em %.1fs" % t)
        if t >= 3.0 and B is None:
            B = make_client(2, 22)
            clients[2] = B
        for actor, L in clients.items():
            L.execute("""
                MOCK.time = MOCK.time + %f
                SCEN.step(MOCK.time, %f)
                MOCK.tickTimers()
                MOCK.tickTweens()
                OnUpdate(%f)
            """ % (dt, dt, dt))
            # pedido de entrar na sala
            if L.eval("MOCK.mp.wantJoin ~= nil"):
                isMaster = actor == 1
                L.execute("MOCK.mp.inRoom = true; MOCK.mp.master = %s; MOCK.mp.players[%d] = 'p%d'" % ("true" if isMaster else "false", actor, actor))
                for other, L2 in clients.items():
                    if other != actor:
                        L.execute("MOCK.mp.players[%d] = 'p%d'" % (other, other))
                        if L2.eval("MOCK.mp.inRoom"):
                            L2.execute("MOCK.mp.players[%d] = 'p%d'; if MOCK.mp.onJoin then MOCK.mp.onJoin(%d, 'p%d') end" % (actor, actor, actor, actor))
                L.execute("local cb = MOCK.mp.wantJoin; MOCK.mp.wantJoin = nil; cb(true)")
        # entrega mensagens (todos para todos, menos o remetente)
        for actor, L in clients.items():
            if not L.eval("MOCK.mp.inRoom"):
                continue
            box = L.eval("MOCK.mpTakeOutbox()")
            msgs = [(box[i][1], box[i][2]) for i in range(1, len(box) + 1)]
            for other, L2 in clients.items():
                if other == actor or not L2.eval("MOCK.mp.inRoom"):
                    continue
                for kind, js in msgs:
                    L2.globals().MOCK.mpDeliver(actor, kind, js)
    ok = True
    for actor, L in clients.items():
        logs = [L.eval("MOCK.log")[i] for i in range(1, L.eval("#MOCK.log") + 1)]
        errs = [l for l in logs if l.startswith("ERROR")]
        warns = [l for l in logs if l.startswith("WARN")]
        print("cliente %d: %s" % (actor, L.eval("SCEN.report()")))
        for w in warns[:6]:
            print("   ", w)
        for e in errs[:6]:
            print("  ERRO:", e)
            ok = False
    # sem entidades duplicadas, sem bots e sem vagas presas no mestre
    chk = A.eval("""(function()
        local G = BRAINROT
        local seen, dup, nb, nents = {}, 0, 0, 0
        for _, e in ipairs(G.ents.order) do
            if seen[e.id] then dup = dup + 1 end
            seen[e.id] = true
            if e.kind == "bot" then nents = nents + 1 end
        end
        local stuck = 0
        for i = 1, 8 do for s = 1, 10 do local x = G.bases.list[i].slots[s]; if x and x.c and not G.ents.get(x.c) then stuck = stuck + 1 end end end
        return string.format("%d %d %d %d", dup, nb, nents, stuck)
    end)()""").split()
    print("mestre: duplicados=%s bots=%s ents_bot=%s vagas_presas=%s" % tuple(chk))
    if chk[0] != "0" or chk[1] != "0" or chk[2] != "0" or chk[3] != "0":
        ok = False
    # consistencia: esteira e bases iguais nos dois
    if B is not None and 2 in clients:
        ca = set(A.eval("(function() local t = {} for u in pairs(BRAINROT.conveyor.items) do t[#t+1] = u end return table.concat(t, ',') end)()").split(","))
        cb = set(B.eval("(function() local t = {} for u in pairs(BRAINROT.conveyor.items) do t[#t+1] = u end return table.concat(t, ',') end)()").split(","))
        diff = ca.symmetric_difference(cb)
        print("esteira: A=%d B=%d diferentes=%d" % (len(ca), len(cb), len(diff)))
        if len(diff) > 2:
            ok = False
        for i in range(1, 9):
            sa = A.eval("(function() local s = {} for k = 1, 10 do local x = BRAINROT.bases.list[%d].slots[k] s[#s+1] = x and (x.id .. (x.c and '*' or '')) or '-' end return (BRAINROT.bases.list[%d].owner or 'nil') .. ' ' .. table.concat(s, ' ') end)()" % (i, i))
            sb = B.eval("(function() local s = {} for k = 1, 10 do local x = BRAINROT.bases.list[%d].slots[k] s[#s+1] = x and (x.id .. (x.c and '*' or '')) or '-' end return (BRAINROT.bases.list[%d].owner or 'nil') .. ' ' .. table.concat(s, ' ') end)()" % (i, i))
            mark = "" if sa == sb else "   <-- DIFERENTE"
            if sa != sb:
                ok = False
            print("base %d A: %s%s" % (i, sa, mark))
            if sa != sb:
                print("       B: %s" % sb)
    print("tempo %.1fs" % (time.time() - t0))
    print("OK" if ok else "FALHOU")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
