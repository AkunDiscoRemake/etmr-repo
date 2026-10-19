-- mp_scenarios.lua — roteiro do teste online (tools/run_mp.py).
-- Cliente 1 (mestre): entra online, compra na esteira e fica na base.
-- Cliente 2: entra depois, vai ate a base do 1, ROUBA (segura 5 s) e leva para casa.

local S = SCENARIO_HELPERS

MPSCEN = { rep = {} }
local sc = MPSCEN

function sc.setup(actor)
    sc.actor = actor
    MOCK.joysticks = { "Joy-Con (R)" }
    if actor == 1 then
        MOCK.storage.base = "1=tralalero:none:0,2=noobini:none:0,3=lirili:gold:0"
        MOCK.storage.money = 5000
    else
        MOCK.storage.base = "1=pipikiwi:none:0"
    end
    sc.state = "start"
end

local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2) end

function sc.step(t, dt)
    local G = S.G()
    if not G then return end
    local Lt = require("layout")
    if sc.state == "start" then
        sc.state = "wait"   -- o jogo conecta sozinho
        return
    end
    if not G.localEnt or not G.myBase then return end
    sc.rep.base = G.myBase
    if sc.actor == 1 then
        -- mestre: compra uma vez e volta para a base
        if sc.state == "wait" then sc.state = "toCarpet"; sc.t0 = t end
        if sc.state == "toCarpet" then
            local best, bz = nil, -1e9
            for _, it in pairs(G.conveyor.items) do
                if it.price <= G.player.money and it.z < 0 and it.z > -25 and it.z > bz then best, bz = it, it.z end
            end
            if best then
                sc.item = best
                if S.walkTo({ -1.9, 0, best.z + 1.5 }, 0.6) then sc.state = "buy"; sc.t1 = t end
            end
            if t - sc.t0 > 30 then sc.state = "home" end
        elseif sc.state == "buy" then
            local it = sc.item
            if not G.conveyor.items[it.uid] then
                S.press("rgrip", false)
                sc.rep.bought = G.player.stats.bought
                sc.state = "home"
            else
                S.lookAt({ 0, 0, it.z })
                S.press("rgrip", true)
                if t - sc.t1 > 4 then S.press("rgrip", false); sc.state = "toCarpet" end
            end
        elseif sc.state == "home" then
            S.walkTo(Lt.spawnPos(G.myBase), 0.5)
        end
        sc.rep.mine = G.bases.count(G.myBase)
        sc.rep.remotes = 0
        for _, e in ipairs(G.ents.order) do if e.kind == "remote" then sc.rep.remotes = sc.rep.remotes + 1 end end
    else
        -- cliente 2: rouba da base do mestre
        local target = nil
        for i = 1, 8 do if G.bases.list[i].owner == "a1" then target = i end end
        sc.rep.sawMaster = target
        if sc.state == "wait" and target and t > 4 then
            local _, s = G.bases.best(target, true)
            if s then
                sc.tb = { b = target, s = s }
                sc.path = { Lt.doorPos(G.myBase), Lt.frontPos(G.myBase), Lt.frontPos(target), Lt.doorPos(target) }
                sc.state = "go"
                sc.t0 = t
            end
        elseif sc.state == "go" then
            local tb = sc.tb
            local q = Lt.slotUV[tb.s]
            if #sc.path > 0 then
                if S.walkTo(sc.path[1], 0.6) then table.remove(sc.path, 1) end
            elseif S.walkTo(Lt.basePoint(tb.b, q.padU + (q.u < 0 and -0.6 or 0.6), q.v, 0), 0.35) then
                sc.state = "steal"; sc.t0 = t
            end
        elseif sc.state == "steal" then
            S.lookAt(Lt.slotPos(sc.tb.b, sc.tb.s))
            S.press("rgrip", true)
            if G.localEnt.carry then
                S.press("rgrip", false)
                sc.rep.carried = G.localEnt.carry.id
                sc.state = "run"
                sc.path = { Lt.doorPos(sc.tb.b), Lt.frontPos(sc.tb.b), Lt.frontPos(G.myBase), Lt.spawnPos(G.myBase) }
            elseif t - sc.t0 > 9 then
                S.press("rgrip", false)
                sc.state = "failed"
            end
        elseif sc.state == "run" then
            if #sc.path > 0 then
                if S.walkTo(sc.path[1], 0.6) then table.remove(sc.path, 1) end
            end
            if not G.localEnt.carry then
                sc.rep.delivered = G.player.stats.stolen
                sc.state = "done"
            end
        else
            S.stop()
        end
        sc.rep.mine = G.bases.count(G.myBase)
    end
end

function sc.report()
    local r = sc.rep
    local G = S.G()
    return string.format("ator=%d estado=%s base=%s minha_base=%s comprou=%s remotos=%s viu_mestre=%s carregou=%s entregou=%s online=%s id=%s",
        sc.actor, tostring(sc.state), tostring(r.base), tostring(r.mine), tostring(r.bought), tostring(r.remotes),
        tostring(r.sawMaster), tostring(r.carried), tostring(r.delivered), tostring(G.net.online()), tostring(G.localId))
end
