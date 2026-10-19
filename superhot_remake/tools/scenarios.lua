-- scenarios.lua — roteiros de teste do SUPERHOT Remake (rodam com o mock).

SCENARIOS = {}

local function V() return require("vec") end
local function G() return SUPERHOT end

local function setHead(pos, yaw, pitch)
    local Vm = V()
    local B = Vm.basisFromEuler(pitch or 0, yaw or 0, 0)
    local qx, qy, qz, qw = Vm.basisToQuat(B)
    MOCK.head.pos = { pos[1], pos[2], pos[3] }
    MOCK.head.q = { qx, qy, qz, qw }
end

local Kc = {}
local function synthK(side)
    if Kc[side] then return Kc[side] end
    local Vm = V()
    local pts = MOCK.handPoints(side, { 0, 0, 0, 0, 0 })
    Kc[side] = { K = Vm.basis(Vm.sub(pts[9], pts[0]), Vm.sub(pts[5], pts[17])), c = Vm.avg({ pts[0], pts[5], pts[9], pts[13], pts[17] }) }
    return Kc[side]
end

local function placeHand(side, palm, hb, curl, tracked)
    local Vm = V()
    local R = G().rig
    local k = synthK(side)
    local Bset = Vm.mulMM(hb, Vm.transpose(k.K))
    local wrist = Vm.sub(palm, Vm.mulMV(Bset, k.c))
    MOCK.setHand(side, R.toWorld(wrist), { r = R.dirToWorld(Bset.r), u = R.dirToWorld(Bset.u), f = R.dirToWorld(Bset.f) }, curl, tracked)
end

local function handForObject(side, objPos, objB, gpName, def, curl)
    local Vm, P = V(), require("poses")
    local gp = def.grabs[gpName]
    local c = P.get(gp.pose, side)
    placeHand(side, Vm.poseApply(objPos, objB, Vm.add(gp.at, c.palm)), Vm.mulMM(objB, c.basis), curl)
end

local OPEN = { 0, 0, 0, 0, 0 }
local GRIP = { 0.6, 0, 1, 1, 1 }
local FIRE = { 0.6, 1, 1, 1, 1 }

local function restPalm(side)
    local Vm, R = V(), G().rig
    local f = R.flatForward()
    local r = { f[3], 0, -f[1] }
    return Vm.add(Vm.add(R.head, Vm.scale(f, 0.3)), Vm.add(Vm.scale(r, side == "right" and 0.22 or -0.22), { 0, -0.4, 0 }))
end

local function restHand(side)
    local Vm, R = V(), G().rig
    local f = R.flatForward()
    placeHand(side, restPalm(side), Vm.basis(f, side == "right" and { -f[3], 0.3, f[1] } or { f[3], 0.3, -f[1] }), OPEN)
end

local function lerp3(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function nearestEnemy()
    local g, best, bd = G(), nil, 1e9
    for _, en in ipairs(g.enemies.list) do
        if not en.dead and en.scale > 0.9 then
            local d = V().dist(en.pos, g.rig.head)
            if d < bd then bd = d; best = en end
        end
    end
    return best
end

-- mao ate um alvo (palma) e fecha
local function reachAndGrab(side, st, key, palm, hb, dur)
    st[key] = (st[key] or 0) + 1 / 60 / (dur or 0.8)
    local k = math.min(1, st[key])
    local curl = (k >= 1 and st[key] > 1.25) and GRIP or OPEN
    placeHand(side, lerp3(restPalm(side), palm, k), hb, curl)
end

---------------------------------------------------------------------------
-- smoke: saguao -> fase 1 -> pega pistola -> atira (se mexendo) -> SUPER HOT -> proxima
---------------------------------------------------------------------------
local S = {}
SCENARIOS.smoke = S
local st = {}

function S.setup()
    setHead({ 0.2, 0.0, -0.1 }, 0, 0)
    st = { levelsWon = 0, maxLevel = 0, deaths = 0, throws = 0, picked = false, tsStill = 1, tsMove = 0 }
end

function S.step(t, dt)
    local g = G()
    -- cabeca balanca (o tempo anda) — exceto num trecho parado para medir
    local still = t > 1.5 and t < 2.5
    local sway = still and 0 or math.sin(t * 2.2) * 0.12
    setHead({ 0.2 + sway, 0.0 + (still and 0 or math.sin(t * 3) * 0.03), -0.1 }, still and 0 or math.sin(t * 1.3) * 6, 0)
    if not g or not g.items then return end
    if still and t > 2.2 then st.tsStill = math.min(st.tsStill, g.time.ts) end
    if not still and t > 3 then st.tsMove = math.max(st.tsMove, g.time.ts) end
    local Vm, I, P = V(), g.items, require("poses")
    if t < 1 then MOCK.hands.left.tracked = false; MOCK.hands.right.tracked = false; return end
    restHand("left")
    if g.player.dead then st.wasDead = true; restHand("right"); return end
    if st.wasDead then st.wasDead = false; st.deaths = st.deaths + 1 end

    if g.mode == "lobby" then
        st.reach = st.reach or 0
        if t > 3 and not st.picked then
            -- cubo da proxima fase liberada
            -- cubo da fase mais alta liberada (mesma formula do arco do saguao)
            local want = math.min(g.game.unlocked, 3)
            local R = g.rig
            local center = { 0, 0, -2.6 }
            local ang = (-72 + (want - 1) * 16) * Vm.RAD
            local target = { center[1] + math.sin(ang) * 1.75, 1.15, center[3] + math.cos(ang) * 1.75 }
            reachAndGrab("right", st, "reachCube", target, Vm.basis(R.flatForward(), { 0, 1, 0 }), 0.8)
        else
            restHand("right")
        end
        return
    end
    st.reachCube = nil
    st.maxLevel = math.max(st.maxLevel, g.game.current)

    if g.mode == "win" then restHand("right"); st.winSeen = true; return end
    if st.winSeen and g.mode == "level" then st.winSeen = false; st.levelsWon = st.levelsWon + 1 end

    local held = I.holding.right and I.holding.right.item
    local en = nearestEnemy()
    local R = g.rig
    local gp = Vm.add(Vm.add(R.head, Vm.scale(R.flatForward(), 0.4)), { 0.12, -0.12, 0 })
    local target = en and Vm.add(en.pos, { 0, 1.5, 0 }) or Vm.add(R.head, Vm.scale(R.flatForward(), 4))
    local B = Vm.basis(Vm.sub(target, gp), { 0, 1, 0 })
    if held and held.def.kind == "gun" and held.ammo > 0 then
        st.trig = ((st.trig or 0) + 1) % 16
        handForObject("right", gp, B, "grip", held.def, (en and st.trig < 8) and FIRE or GRIP)
        return
    end
    if held and en then
        -- sem municao ou objeto de arremesso: joga no inimigo
        st.throwT = (st.throwT or 0) + dt
        local dir = Vm.norm(Vm.sub(target, gp))
        local p = lerp3(Vm.sub(gp, Vm.scale(dir, 0.3)), Vm.add(gp, Vm.scale(dir, 0.35)), math.min(1, st.throwT / 0.16))
        local hb = Vm.basis(dir, { 0, 1, 0 })
        local curl = st.throwT > 0.12 and OPEN or GRIP
        if held.def.grabs.grip.pose == "pistol" then handForObject("right", p, B, "grip", held.def, curl)
        else placeHand("right", p, hb, curl) end
        st.throwing = true
        if st.throwT > 0.7 then st.throwT = 0 end
        return
    end
    if held then restHand("right"); return end
    if st.throwing then st.throwing = false; st.throwT = 0; st.pullT = -0.5; st.throws = st.throws + 1 end
    -- mao vazia: puxa a distancia o objeto livre mais proximo (palma apontada, mao fechada)
    local best, bd = nil, 1e9
    for _, it in ipairs(I.list) do
        if not it.dead and (it.state == "rest" or (it.state == "falling" and Vm.len(it.vel) < 1)) then
            local d = Vm.dist(it.pos, R.head)
            local useful = (it.def.kind == "gun" and (it.ammo or 0) > 0) and -3 or ((it.def.kind == "throw" or it.def.kind == "melee") and 0 or 5)
            local score = d + useful
            if score < bd then bd = score; best = it end
        end
    end
    if best then
        st.pullT = (st.pullT or 0) + dt
        local palm = restPalm("right")
        local toIt = Vm.norm(Vm.sub(best.pos, palm))
        -- palma (lado palmar = -r para a mao direita) apontando pro objeto
        local up = math.abs(toIt[2]) > 0.9 and { 0, 0, 1 } or { 0, 1, 0 }
        local hb0 = Vm.basis(up, toIt)
        local hb = { r = Vm.scale(toIt, -1), u = Vm.norm(Vm.cross(toIt, Vm.cross(up, toIt))), f = nil }
        hb.f = Vm.cross(hb.r, hb.u)
        placeHand("right", palm, hb, st.pullT > 0.3 and { 0.8, 1, 1, 1, 1 } or OPEN)
        if st.pullT > 0.8 then st.pullT = 0 end
        local _ = hb0
    else
        restHand("right")
    end
end

function S.report()
    local g = G()
    return string.format("fase_max=%d vitorias=%d mortes=%d abates=%d tiros=%d arremessos=%d desbloqueadas=%d ts_parado=%.3f ts_movendo=%.2f modo=%s",
        st.maxLevel, st.levelsWon, st.deaths, g.stats.kills, g.stats.shots, st.throws, g.game.unlocked, st.tsStill, st.tsMove, g.mode)
end

---------------------------------------------------------------------------
-- still: entra na fase 2 e fica PARADO — o tempo quase nao anda; depois se mexe e morre
---------------------------------------------------------------------------
local St = {}
SCENARIOS.still = St
local sst = {}
function St.setup() setHead({ 0, 0, 0 }, 0, 0); sst = { deaths = 0 } end
function St.step(t, dt)
    local g = G()
    local moveNow = t > 12
    setHead({ moveNow and math.sin(t * 3) * 0.15 or 0, 0, 0 }, 0, 0)
    if not g or not g.items then return end
    restHand("left"); restHand("right")
    if t > 1 and not sst.started then sst.started = true; g.game.startLevel(2) end
    if t > 2 and t < 12 then sst.gt12 = g.levelTime end
    if g.player.dead and not sst.dead then sst.dead = true; sst.deaths = sst.deaths + 1; sst.deathAt = t end
    if not g.player.dead then sst.dead = false end
end
function St.report()
    local g = G()
    return string.format("tempo_de_jogo_em_10s_parado=%.2fs mortes=%d morreu_em=%.1fs inimigos=%d", sst.gt12 or -1, sst.deaths, sst.deathAt or -1, g.enemies.alive())
end

---------------------------------------------------------------------------
-- katana: fase 5, segura a katana na frente e balanca
---------------------------------------------------------------------------
local Kt = {}
SCENARIOS.katana = Kt
local kst = {}
function Kt.setup() setHead({ 0, 0, 0 }, 0, 0); kst = {} end
function Kt.step(t, dt)
    local g = G()
    setHead({ math.sin(t * 2) * 0.1, 0, 0 }, math.sin(t) * 10, 0)
    if not g or not g.items then return end
    local Vm, I, P = V(), g.items, require("poses")
    restHand("left")
    if t > 1 and not kst.started then kst.started = true; g.game.startLevel(5) end
    if not kst.started or g.mode ~= "level" then restHand("right"); return end
    local held = I.holding.right and I.holding.right.item
    if held and held.type == "katana" then
        -- golpes horizontais na frente
        local R = g.rig
        local f = R.flatForward()
        local r = { f[3], 0, -f[1] }
        local a = math.sin(t * 5)
        local p = Vm.add(Vm.add(R.head, Vm.scale(f, 0.4)), Vm.add(Vm.scale(r, a * 0.35), { 0, -0.3, 0 }))
        local bladeDir = Vm.norm(Vm.add(f, Vm.scale(r, a * 0.8)))
        local B = Vm.basis(Vm.scale(r, -1), bladeDir)
        handForObject("right", p, { r = B.r, u = bladeDir, f = Vm.cross(B.r, bladeDir) }, "grip", held.def, GRIP)
        kst.held = true
    else
        for _, it in ipairs(I.list) do
            if it.type == "katana" and it.state == "rest" then
                local palm = Vm.poseApply(it.pos, it.B, P.get("fist", "right").palm)
                reachAndGrab("right", kst, "reach", palm, Vm.mulMM(it.B, P.get("fist", "right").basis), 0.7)
                return
            end
        end
        restHand("right")
    end
end
function Kt.report()
    local g = G()
    return string.format("segurou=%s abates=%d balas_cortadas=%d mortes_jogador=%s", tostring(kst.held), g.stats.kills, g.stats.sliced or 0, tostring(g.player.dead))
end

---------------------------------------------------------------------------
-- endless: modo infinito, mira automatica
---------------------------------------------------------------------------
local En = {}
SCENARIOS.endless = En
function En.setup() setHead({ 0, 0, 0 }, 0, 0); En.st = {}; S.setup() end
function En.step(t, dt)
    local g = G()
    setHead({ math.sin(t * 2.5) * 0.12, 0, 0 }, 0, 0)
    if not g or not g.items then return end
    if t > 1 and not En.st.started then En.st.started = true; MOCK.buttons[require("i18n").t("bEndless")]() end
    S.step(t, dt)
end
function En.report()
    local g = G()
    return string.format("abates=%d recorde_infinito=%d modo=%s", g.stats.kills, g.game.endlessBest, g.mode)
end

---------------------------------------------------------------------------
-- campaign: igual ao smoke, mas invencivel e escolhendo PROXIMA no fim da fase
---------------------------------------------------------------------------
local Cp = {}
SCENARIOS.campaign = Cp
function Cp.setup() S.setup() end
function Cp.step(t, dt)
    local g = G()
    if g and g.player then g.player.god = true end
    -- so no teste: municao infinita para o robo conseguir terminar as fases
    if g and g.items then
        local h = g.items.holding.right
        if h and h.item and h.item.def.kind == "gun" then h.item.ammo = math.max(h.item.ammo, 3) end
    end
    if g and g.mode == "win" then
        st.winSeen = true
        setHead({ 0.2, 0, -0.1 }, 0, 0)
        restHand("left"); restHand("right")
        return
    end
    -- depois do SUPER HOT aparecem os cubos: toca no vermelho (PROXIMA)
    if g and g.mode == "cleared" then
        local Vm = V()
        local R = g.rig
        local f = R.flatForward()
        local r = { f[3], 0, -f[1] }
        local base = Vm.add(R.head, Vm.scale(f, 0.75))
        base[2] = 1.15
        local nextCube = Vm.add(base, Vm.scale(r, 0.3))
        reachAndGrab("right", st, "reachNext", nextCube, Vm.basis(f, { 0, 1, 0 }), 0.6)
        restHand("left")
        setHead({ 0.2, 0, -0.1 }, 0, 0)
        return
    end
    st.reachNext = nil
    S.step(t, dt)
end
Cp.report = S.report

-- campaign6: comeca direto na fase 6 (para cobrir 6..10)
local C6 = {}
SCENARIOS.campaign6 = C6
function C6.setup() S.setup() end
function C6.step(t, dt)
    local g = G()
    if g and g.game and t > 1 and not C6.started then C6.started = true; g.game.startLevel(6) end
    Cp.step(t, dt)
end
C6.report = S.report
