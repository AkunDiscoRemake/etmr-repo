-- scenarios.lua — "jogador robo" para testar o jogo no simulador (tools/run_sim.py).
-- Controla o Joy-Con falso (analogico + botoes) e a cabeca; nao mexe direto no estado do jogo
-- (a nao ser para forcar eventos/dinheiro em testes especificos).

SCENARIOS = {}

local KEY = {
    rgrip = "joystick button 5", rtrig = "joystick button 7", jump = "joystick button 0",
    ltrig = "joystick button 6", lgrip = "joystick button 4", menu = "joystick button 10",
}

local S = {}   -- helpers

function S.G() return BRAINROT end

function S.press(k, v) MOCK.keys[KEY[k]] = v and true or nil end

function S.setYawWorld(yaw)
    local r = math.rad(yaw) / 2
    MOCK.head.q = { 0, math.sin(r), 0, math.cos(r) }
end

-- olha (no espaco local do jogo) para o ponto p
function S.lookAt(p)
    local G = S.G()
    local R = G.rig
    local d = { p[1] - R.head[1], 0, p[3] - R.head[3] }
    local w = R.dirToWorld(d)
    S.setYawWorld(math.deg(math.atan(w[1], w[3])))
end

-- anda ate p; retorna true quando chegou
function S.walkTo(p, tol)
    local G = S.G()
    local R = G.rig
    local d = math.sqrt((p[1] - R.head[1]) ^ 2 + (p[3] - R.head[3]) ^ 2)
    if d < (tol or 0.5) then
        MOCK.axes.Vertical = 0
        return true
    end
    S.lookAt(p)
    MOCK.axes.Vertical = math.min(1, d / 0.8 + 0.2)
    return false
end

function S.stop() MOCK.axes.Vertical = 0; MOCK.axes.Horizontal = 0 end

function S.feet()
    local R = S.G().rig
    return { R.head[1], 0, R.head[3] }
end

local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2) end

local function pickConvTarget()
    local G = S.G()
    local best, bz = nil, -1e9
    for _, it in pairs(G.conveyor.items) do
        if it.price <= G.player.money and it.z < 10 and it.z > -20 and it.z > bz then best, bz = it, it.z end
    end
    return best
end

---------------------------------------------------------------------------
-- SMOKE: compra, coleta, rouba de um bot, bate, eventos
---------------------------------------------------------------------------
do
    local sc = { state = "start", t0 = 0, rep = {} }
    function sc.setup()
        MOCK.joysticks = { "Joy-Con (R)" }
    end
    function sc.step(t, dt)
        local G = S.G()
        if not G or not G.localEnt then return end
        local Lt = require("layout")
        local st = sc.state
        if st == "start" then
            if t > 1.5 then sc.state = "toCarpet" end
        elseif st == "toCarpet" then
            local it = pickConvTarget()
            if it then
                sc.item = it
                local target = { -1.9, 0, it.z + 1.5 }
                if S.walkTo(target, 0.6) then sc.state = "buy"; sc.t0 = t end
            else
                S.walkTo({ -2.0, 0, -8 }, 0.5)
            end
        elseif st == "buy" then
            local it = sc.item
            if not G.conveyor.items[it.uid] then
                S.press("rgrip", false)
                sc.rep.bought = G.player.stats.bought
                sc.state = (G.player.stats.bought > 0) and "waitArrive" or "toCarpet"
                sc.t0 = t
            else
                S.lookAt({ 0, 0, it.z })
                S.press("rgrip", true)
                if t - sc.t0 > 4 then S.press("rgrip", false); sc.state = "toCarpet" end
            end
        elseif st == "waitArrive" then
            local my = G.myBase
            S.walkTo(Lt.spawnPos(my), 0.6)
            if G.bases.count(my) > 0 and t - sc.t0 > 3 then sc.state = "collect"; sc.t0 = t end
        elseif st == "collect" then
            local my = G.myBase
            local s = nil
            for k = 1, Lt.SLOTS do if G.bases.list[my].slots[k] then s = k; break end end
            if s and S.walkTo(Lt.padPos(my, s), 0.3) and t - sc.t0 > 6 then
                sc.rep.collected = G.player.stats.collected
                sc.state = "toSteal"
                sc.t0 = t
            end
        elseif st == "toSteal" then
            -- base de bot com algo para roubar (a mais perto)
            if not sc.tb then
                local best, bd = nil, 1e9
                for i = 1, 8 do
                    if i ~= G.myBase and G.bases.list[i].owner and not G.bases.isLocked(i) then
                        local _, s = G.bases.best(i, true)
                        local d = dist(Lt.bases[i].center, S.feet())
                        if s and d < bd then best, bd = { b = i, s = s }, d end
                    end
                end
                sc.tb = best
                sc.path = { Lt.doorPos(G.myBase), Lt.frontPos(G.myBase), Lt.frontPos(best.b), Lt.doorPos(best.b) }
            end
            local tb = sc.tb
            local q = Lt.slotUV[tb.s]
            if #sc.path > 0 then
                if S.walkTo(sc.path[1], 0.6) then table.remove(sc.path, 1) end
            elseif S.walkTo(Lt.basePoint(tb.b, q.padU + (q.u < 0 and -0.6 or 0.6), q.v, 0), 0.35) then
                sc.state = "steal"; sc.t0 = t
            end
            if t - sc.t0 > 40 then sc.state = "fight"; sc.t0 = t end
        elseif st == "steal" then
            local tb = sc.tb
            S.lookAt(Lt.slotPos(tb.b, tb.s))
            S.press("rgrip", true)
            if G.localEnt.carry then
                S.press("rgrip", false)
                sc.rep.carried = true
                sc.state = "runHome"; sc.t0 = t
                sc.path = { Lt.doorPos(tb.b), Lt.frontPos(tb.b), Lt.frontPos(G.myBase), Lt.spawnPos(G.myBase) }
            elseif t - sc.t0 > 8 then
                S.press("rgrip", false)
                sc.state = "fight"; sc.t0 = t
            end
        elseif st == "runHome" then
            if #sc.path > 0 then
                if S.walkTo(sc.path[1], 0.6) then table.remove(sc.path, 1) end
            end
            if not G.localEnt.carry then
                sc.rep.delivered = G.player.stats.stolen
                sc.rep.dropAt = string.format("%.0f,%.0f stun=%.1f", S.feet()[1], S.feet()[3], G.player.stunT)
                sc.state = "fight"; sc.t0 = t
            end
            if t - sc.t0 > 30 then sc.state = "fight"; sc.t0 = t end
        elseif st == "fight" then
            -- persegue o bot mais perto e bate
            local best, bd = nil, 1e9
            for _, e in ipairs(G.ents.order) do
                if e.kind == "bot" then
                    local d = dist(e.pos, S.feet())
                    if d < bd then best, bd = e, d end
                end
            end
            if best then
                if bd > 1.6 then S.walkTo(best.pos, 1.4) else S.stop(); S.lookAt(best.pos) end
                S.press("rtrig", math.floor(t * 3) % 2 == 0 and bd < 2.2)
            end
            if t - sc.t0 > 12 then
                S.press("rtrig", false)
                sc.rep.hits = G.player.stats.hits
                sc.state = "events"; sc.t0 = t
                G.events.force("candy")
            end
        elseif st == "events" then
            S.stop()
            local e = t - sc.t0
            if e > 8 and not sc.lava then sc.lava = true; G.events.force("lava") end
            if e > 20 and not sc.night then sc.night = true; G.events.current = nil; G.events.force("night") end
            if e > 28 then
                sc.state = "lock"; sc.t0 = t
            end
            -- tenta pegar doces
            S.walkTo({ math.sin(t * 0.3) * 8, 0, -10 + math.cos(t * 0.3) * 8 }, 0.3)
        elseif st == "lock" then
            local my = G.myBase
            if S.walkTo(G.world.bases[my].lockPos, 0.3) then
                sc.rep.locked = G.bases.isLocked(my)
                sc.state = "done"
            end
            if t - sc.t0 > 20 then sc.state = "done" end
        else
            S.stop()
        end
    end
    function sc.report()
        local G = S.G()
        local r = sc.rep
        local bots = 0
        for _ in pairs(G.ai.bots) do bots = bots + 1 end
        return string.format("estado=%s comprou=%s coletou=%s carregou=%s entregou=%s acertos=%s trancou=%s soltou_em=%s dinheiro=%d base=%d bots=%d roubados_de_mim? noite=%s",
            sc.state, tostring(r.bought), tostring(r.collected), tostring(r.carried), tostring(r.delivered), tostring(r.hits),
            tostring(r.locked), tostring(r.dropAt), math.floor(G.player.money), G.bases.count(G.myBase), bots, tostring(G.events.isNight()))
    end
    SCENARIOS.smoke = sc
end

---------------------------------------------------------------------------
-- IDLE: fica parado na base e ve os bots jogarem (testa a IA e os roubos)
---------------------------------------------------------------------------
do
    local sc = { stats = { steals = 0, buys = 0 } }
    function sc.setup()
        MOCK.storage.base = "1=tralalero:none:0,2=noobini:gold:0,3=cappuccino:none:0"
        MOCK.storage.tutDone = true
        MOCK.storage.difficulty = "hard"
    end
    local lastCount = {}
    function sc.step(t, dt)
        local G = S.G()
        if not G or not G.localEnt then return end
        S.stop()
        for i = 1, 8 do
            local n = G.bases.count(i)
            if lastCount[i] and n > lastCount[i] then sc.stats.buys = sc.stats.buys + 1 end
            lastCount[i] = n
        end
        for _, e in ipairs(G.ents.order) do
            if e.carry and not e.wasCarry then sc.stats.steals = sc.stats.steals + 1 end
            e.wasCarry = e.carry ~= nil
        end
    end
    function sc.report()
        local G = S.G()
        local tot = 0
        for i = 1, 8 do tot = tot + G.bases.count(i) end
        return string.format("roubos_iniciados=%d chegadas=%d total_brainrots=%d minha_base=%d esteira=%d",
            sc.stats.steals, sc.stats.buys, tot, G.bases.count(G.myBase), (function() local n = 0 for _ in pairs(G.conveyor.items) do n = n + 1 end return n end)())
    end
    SCENARIOS.idle = sc
end

---------------------------------------------------------------------------
-- SHOWCASE: para renders (dinheiro alto, base cheia de brainrots raros)
---------------------------------------------------------------------------
do
    local sc = {}
    function sc.setup()
        MOCK.storage.base = "1=tralalero:none:500,2=bombardiro:gold:0,3=cappuccino:none:0,4=ballerina:diamond:0,5=patapim:none:0,6=tralaleritos:none:0,7=chimpbanana:candy:0,8=lirili:lava:0,9=orcalero:rainbow:0,10=girafa:none:0"
        MOCK.storage.money = 1234567
        MOCK.storage.tutDone = true
    end
    function sc.step(t, dt)
        local G = S.G()
        if not G or not G.localEnt then return end
        S.stop()
        local Lt = require("layout")
        if t < 1 then S.walkTo(Lt.basePoint(G.myBase, 0, -2.6, 0), 0.3) else S.lookAt(Lt.doorPos(G.myBase)) end
    end
    function sc.report() return "ok" end
    SCENARIOS.showcase = sc
end

SCENARIO_HELPERS = S

---------------------------------------------------------------------------
-- EVENTOS: para renders (noite de Halloween, Candy, Lava) olhando a esteira
---------------------------------------------------------------------------
for _, ev in ipairs({ "night", "candy", "lava" }) do
    local sc = {}
    function sc.setup()
        MOCK.storage.base = "1=tralalero:halloween:0,2=bombardiro:lava:0,3=cappuccino:candy:0"
        MOCK.storage.tutDone = true
    end
    function sc.step(t, dt)
        local G = S.G()
        if not G or not G.localEnt then return end
        local Lt = require("layout")
        if not sc.forced and t > 0.5 then sc.forced = true; G.events.force(ev) end
        if t < 2.5 then S.walkTo(Lt.frontPos(G.myBase), 0.4) else S.stop(); S.lookAt({ 0, 0, Lt.frontPos(G.myBase)[3] + 6 }) end
    end
    function sc.report() return "ok " .. ev end
    SCENARIOS["ev_" .. ev] = sc
end
