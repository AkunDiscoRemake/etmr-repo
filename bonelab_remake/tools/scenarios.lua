-- scenarios.lua — roteiros de teste para run_sim.py (rodam junto com o mock).
-- Cada cenario: setup(), step(t, dt), report().

SCENARIOS = {}

local function V() return require("vec") end
local function G() return BONELAB end

-- cabeca: posicao global + yaw/pitch (graus)
local function setHead(pos, yaw, pitch)
    local Vm = V()
    local B = Vm.basisFromEuler(pitch or 0, yaw or 0, 0)
    local qx, qy, qz, qw = Vm.basisToQuat(B)
    MOCK.head.pos = { pos[1], pos[2], pos[3] }
    MOCK.head.q = { qx, qy, qz, qw }
end

-- base "K" da mao sintetica e centro da palma (no espaco da mao sintetica)
local Kc = {}
local function synthK(side)
    if Kc[side] then return Kc[side] end
    local Vm = V()
    local pts = MOCK.handPoints(side, { 0, 0, 0, 0, 0 })
    local K = Vm.basis(Vm.sub(pts[9], pts[0]), Vm.sub(pts[5], pts[17]))
    local c = Vm.avg({ pts[0], pts[5], pts[9], pts[13], pts[17] })
    Kc[side] = { K = K, c = c }
    return Kc[side]
end

-- Coloca a mao (coordenadas LOCAIS do jogo) com palma em `palm` e base de mao `hb`
-- (hb.f = punho->dedos, hb.u = lado do indicador) e dobra `curl`.
local function placeHand(side, palm, hb, curl, tracked)
    local Vm = V()
    local R = G().rig
    local k = synthK(side)
    local Bset = Vm.mulMM(hb, Vm.transpose(k.K))
    local wrist = Vm.sub(palm, Vm.mulMV(Bset, k.c))
    -- converte para global
    local wW = R.toWorld(wrist)
    local BW = { r = R.dirToWorld(Bset.r), u = R.dirToWorld(Bset.u), f = R.dirToWorld(Bset.f) }
    MOCK.setHand(side, wW, BW, curl, tracked)
end

-- mao para segurar a arma `it` (de tipo pose) na pose de objeto desejada
local function handForObject(side, objPos, objB, gpName, def, curl)
    local Vm = V()
    local P = require("poses")
    local gp = def.grabs[gpName]
    local c = P.get(gp.pose, side)
    local hb = Vm.mulMM(objB, c.basis)
    local palm = Vm.poseApply(objPos, objB, Vm.add(gp.at, c.palm))
    placeHand(side, palm, hb, curl)
end

local OPEN = { 0, 0, 0, 0, 0 }
local GRIP = { 0.6, 0, 1, 1, 1 }
local FIRE = { 0.6, 1, 1, 1, 1 }

local function lerp3(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function nearestBot(from, types)
    local best, bd = nil, 1e9
    for _, b in ipairs(G().bots.list) do
        if not b.dead and b.scale > 0.9 and (not types or types[b.type]) then
            local d = V().dist(b.pos, from)
            if d < bd then bd = d; best = b end
        end
    end
    return best
end

local function headOf(bot)
    if bot.type == "crab" then
        if bot.latched or bot.grabbed or bot.flying then return bot.pos end
        return V().add(bot.pos, { 0, 0.18, 0 })
    end
    return V().add(bot.pos, { 0, 1.62, 0 })
end

---------------------------------------------------------------------------
-- Cenario: smoke — boot, pegar pistola, atirar no boneco, ondas, recarregar
---------------------------------------------------------------------------
local S = {}
SCENARIOS.smoke = S
local st = {}

function S.setup()
    setHead({ 0.3, 0.1, -0.2 }, 0, 0)
    st = { phase = "idle", fired = 0, reloads = 0, grabbed = false, wavesStarted = false, trigOn = false, trigT = 0, maxWave = 0, hpMin = 100, kills = 0 }
end

local function curPalmRest(side)
    local R = G().rig
    local Vm = V()
    local h = R.head
    local f = R.flatForward()
    local r = { f[3], 0, -f[1] }
    return Vm.add(Vm.add(h, Vm.scale(f, 0.35)), Vm.add(Vm.scale(r, side == "right" and 0.2 or -0.2), { 0, -0.35, 0 }))
end

local function restHand(side)
    local Vm = V()
    local R = G().rig
    local f = R.flatForward()
    local hb = Vm.basis(f, side == "right" and { -f[3], 0.3, f[1] } or { f[3], 0.3, -f[1] })
    placeHand(side, curPalmRest(side), hb, OPEN)
end

function S.step(t, dt)
    local g = G()
    setHead({ 0.3, 0.1, -0.2 }, math.sin(t * 0.3) * 5, math.sin(t * 0.5) * 3)
    if not g or not g.items then
        MOCK.hands.left.tracked = false
        MOCK.hands.right.tracked = false
        return
    end
    local Vm = V()
    local I = g.items
    local Wp = g.weapons
    local P = require("poses")
    if t < 1 then
        MOCK.hands.left.tracked = false
        MOCK.hands.right.tracked = false
        return
    end
    local gun = I.gunIn("right")

    if not gun then
        -- vai ate a pistola da mesa e fecha a mao
        local slot = I.slots[1]
        local it = slot.item
        if it and not it.dead and not I.isHeld(it) then
            local target = Vm.poseApply(it.pos, it.B, Vm.add(Wp.defs.pistol.grabs.grip.at, P.get("pistol", "right").palm))
            st.reach = (st.reach or 0) + dt / 1.2
            local k = math.min(1, st.reach)
            local from = curPalmRest("right")
            local palm = lerp3(from, target, k)
            local hb = Vm.mulMM(it.B, P.get("pistol", "right").basis)
            local curl = (k >= 1 and (st.reachHold or 0) > 0.15) and GRIP or OPEN
            if k >= 1 then st.reachHold = (st.reachHold or 0) + dt end
            local c = synthK("right")
            local Bset = Vm.mulMM(hb, Vm.transpose(c.K))
            placeHand("right", palm, hb, curl)
        else
            restHand("right")
        end
        restHand("left")
        return
    end
    st.grabbed = true

    -- comecar ondas depois de 3 s com arma
    st.held = (st.held or 0) + dt
    if st.held > 3 and not st.wavesStarted then
        st.wavesStarted = true
        MOCK.buttons[require("i18n").t("bWaves")]()
    end

    -- mira: alvo = bot mais proximo (cabeca); arma 45 cm a frente
    local R = g.rig
    local bot = nearestBot(R.head)
    local target = bot and headOf(bot) or Vm.add(R.head, Vm.scale(R.flatForward(), 5))
    local gunPos = Vm.add(Vm.add(R.head, Vm.scale(R.flatForward(), 0.42)), { 0.12, -0.12, 0 })
    local muzzleOff = Wp.defs[gun.type].muzzle
    local dir = Vm.norm(Vm.sub(target, gunPos))
    local gunB = Vm.basis(dir, { 0, 1, 0 })
    -- corrige a altura do cano
    gunPos = Vm.sub(gunPos, Vm.mulMV(gunB, { 0, muzzleOff[2], 0 }))

    -- gatilho
    st.trigT = st.trigT + dt
    if st.trigT > 0.14 then
        st.trigT = 0
        st.trigOn = not st.trigOn
        if st.trigOn then st.fired = st.fired + 1 end
    end
    local curl = (st.trigOn and bot) and FIRE or GRIP
    handForObject("right", gunPos, gunB, "grip", Wp.defs[gun.type], curl)

    -- recarga: pente vazio -> mao esquerda na bolsa -> pente na arma
    local L = g.controls.hands.left
    local hold = I.holding.left
    if gun.magCount == nil or (gun.magCount == 0 and not gun.chamber) then
        st.reloading = true
    end
    if st.reloading then
        if gun.magCount ~= nil and gun.magCount == 0 then
            -- solta o pente vazio (gestos: dispara a seco)
        end
        if not hold then
            local pp = I.pouchPoints().left
            st.toPouch = (st.toPouch or 0) + dt / 0.6
            local f = R.flatForward()
            local hb = Vm.basis({ 0, -1, 0 }, { f[3], 0, -f[1] })
            local k = math.min(1, st.toPouch)
            placeHand("left", lerp3(curPalmRest("left"), pp, k), hb, (k >= 1 and st.toPouch > 1.15) and GRIP or OPEN)
        elseif hold.item and hold.item.def.kind == "mag" then
            st.toPouch = 0
            -- leva o pente ate o encaixe
            st.toWell = (st.toWell or 0) + dt / 0.5
            local well = Wp.magWellPos(gun)
            local mag = hold.item
            local magB = gun.B
            local palmPose = P.get("mag", "left")
            local hb = Vm.mulMM(magB, palmPose.basis)
            local desiredMagPos = Vm.sub(well, Vm.mulMV(magB, { 0, 0.03, 0 }))
            local palm = Vm.poseApply(desiredMagPos, magB, palmPose.palm)
            local k = math.min(1, st.toWell)
            placeHand("left", lerp3(curPalmRest("left"), palm, k), hb, GRIP)
        else
            restHand("left")
        end
        if gun.magCount ~= nil and gun.magCount > 0 then
            st.reloading = false
            st.reloads = st.reloads + 1
            st.toWell = 0
        end
    else
        if hold then placeHand("left", curPalmRest("left"), Vm.basis(R.flatForward(), { 0, 1, 0 }), OPEN)
        else restHand("left") end
    end
    st.maxWave = math.max(st.maxWave, g.game.wave)
    st.hpMin = math.min(st.hpMin, g.player.hp)
end

function S.report()
    local g = G()
    return string.format("pegou=%s tiros=%d abates=%d headshots=%d recargas=%d onda=%d pontos=%d hpMin=%.0f bots=%d itens=%d",
        tostring(st.grabbed), g.stats.shots, g.stats.kills, g.stats.headshots, st.reloads, st.maxWave, g.game.score, st.hpMin,
        #g.bots.list, #g.items.list)
end

---------------------------------------------------------------------------
-- Cenario: joycon — calibracao + andar com analogico + virar + atirar com ZR
---------------------------------------------------------------------------
local J = {}
SCENARIOS.joycon = J
local jt = {}

function J.setup()
    setHead({ 0, 0, 0 }, 0, 0)
    MOCK.joysticks = { "Joy-Con (L)", "Joy-Con (R)" }
    jt = { calStarted = false, pressQueue = {}, moved = 0, startPos = nil }
end

local CAL_KEYS = { "joystick 2 button 7", "joystick 2 button 5", "joystick 2 button 0", "joystick 1 button 6",
    "joystick 1 button 4", "joystick 1 button 13", "joystick 2 button 2", "joystick 2 button 3",
    "joystick 1 button 9", "joystick 1 button 8" }

function J.step(t, dt)
    local g = G()
    setHead({ 0, 0, 0 }, 0, 0)
    if not g or not g.controls then return end
    local C = g.controls
    for k in pairs(MOCK.keys) do MOCK.keys[k] = nil end
    restHand("right")
    restHand("left")
    if t > 1 and not jt.calStarted then
        jt.calStarted = true
        C.startCalibration()
        jt.step = 1
        jt.t = 0
    end
    if C.calibrating then
        jt.t = jt.t + dt
        -- aperta a tecla da etapa por 0.2 s, solta por 0.2 s
        local key = CAL_KEYS[jt.step]
        if key and jt.t > 0.2 and jt.t < 0.4 then MOCK.keys[key] = true end
        if jt.t > 0.6 then jt.t = 0; jt.step = jt.step + 1 end
        return
    end
    if not jt.calStarted then return end
    if not jt.startPos then jt.startPos = { g.rig.head[1], g.rig.head[3] }; jt.yaw0 = g.rig.yaw; jt.t0 = t end
    local lt = t - jt.t0
    -- anda de lado 2 s com o analogico (pra frente tem a mesa)
    MOCK.axes.Horizontal = lt < 2 and 1 or 0
    -- vira a direita uma vez (botao calibrado)
    if lt > 2.2 and lt < 2.3 then MOCK.keys["joystick 2 button 2"] = true end
    -- pega a pistola com o botao R (mao na arma) e atira com ZR
    if lt > 2.5 then
        local I = g.items
        local it = I.slots[1].item
        local P = require("poses")
        local Vm = V()
        if not I.gunIn("right") and it and not it.dead then
            local target = Vm.poseApply(it.pos, it.B, P.get("pistol", "right").palm)
            placeHand("right", target, Vm.mulMM(it.B, P.get("pistol", "right").basis), OPEN)
            if lt > 3.0 then MOCK.keys["joystick 2 button 5"] = true end
        elseif I.gunIn("right") then
            jt.gotGun = true
            MOCK.keys["joystick 2 button 5"] = true
            local gun = I.gunIn("right")
            local Rg = g.rig
            local gp = Vm.add(Vm.add(Rg.head, Vm.scale(Rg.flatForward(), 0.4)), { 0.1, -0.15, 0 })
            handForObject("right", gp, Vm.basis(Rg.flatForward(), { 0, 1, 0 }), "grip", g.weapons.defs.pistol, OPEN)
            if math.floor(lt * 4) % 2 == 0 then MOCK.keys["joystick 2 button 7"] = true end
            if lt > 5 and lt < 5.05 then MOCK.keys["joystick 2 button 0"] = true end
            jt.ammo = g.weapons.ammoTotal(gun)
            jt.magOut = gun.magCount == nil
        end
    end
    jt.walked = math.sqrt((g.rig.head[1] - jt.startPos[1]) ^ 2 + (g.rig.head[3] - jt.startPos[2]) ^ 2)
end

function J.report()
    local g = G()
    local C = g.controls
    return string.format("calibrado=%s trigger=%s grip=%s turnR=%s andou=%.2fm yaw=%.0f->%.0f pegouArma=%s tiros=%d municao=%s penteSolto=%s",
        tostring(MOCK.storage.calibrated), C.bind.right_trigger, C.bind.right_grip, C.bind.turnR, jt.walked or 0, jt.yaw0 or 0, g.rig.yaw,
        tostring(jt.gotGun), g.stats.shots, tostring(jt.ammo), tostring(jt.magOut))
end

---------------------------------------------------------------------------
-- Cenario: crab — crab pula no rosto e o jogador arranca com a mao
---------------------------------------------------------------------------
local K = {}
SCENARIOS.crab = K
local kt = {}

function K.setup()
    setHead({ 0, 0, 0 }, 0, 0)
    kt = { spawned = false, latchedSeen = false, grabbed = false, thrown = false }
end

function K.step(t, dt)
    local g = G()
    setHead({ 0, 0, 0 }, 0, 0)
    if not g or not g.bots then return end
    local Vm = V()
    if t > 1 and not kt.spawned then
        kt.spawned = true
        MOCK.buttons[require("i18n").t("bSandbox")]()
        local p = Vm.add(g.rig.head, Vm.scale(g.rig.flatForward(), 4))
        kt.crab = g.bots.spawn("crab", { p[1], 0, p[3] }, { force = true })
    end
    restHand("left")
    local crab = kt.crab
    if crab and crab.latched then kt.latchedSeen = true; kt.latchT = (kt.latchT or 0) + dt end
    if crab and crab.latched and kt.latchT > 1.0 then
        -- mao direita vai ate o crab e fecha
        placeHand("right", crab.pos, Vm.basis(g.rig.headB.f, { 0, 1, 0 }), GRIP)
    elseif crab and crab.grabbed then
        kt.grabbed = true
        kt.hold = (kt.hold or 0) + dt
        local p = Vm.add(Vm.add(g.rig.head, Vm.scale(g.rig.flatForward(), 0.3 + kt.hold * 2)), { 0.2, -0.2 + kt.hold, 0 })
        placeHand("right", p, Vm.basis(g.rig.headB.f, { 0, 1, 0 }), kt.hold > 0.25 and OPEN or GRIP)
        if kt.hold > 0.25 then kt.thrown = true end
    else
        restHand("right")
    end
end

function K.report()
    local g = G()
    return string.format("pulou_no_rosto=%s arrancou=%s arremessou=%s hp=%.0f crabsNoRosto=%d",
        tostring(kt.latchedSeen), tostring(kt.grabbed), tostring(kt.thrown), g.player.hp, g.player.crabs)
end

---------------------------------------------------------------------------
-- Cenario: idle — so fica parado (para medir custo por frame e checar a IA)
---------------------------------------------------------------------------
local Id = {}
SCENARIOS.idle = Id
function Id.setup() setHead({ 0, 0, 0 }, 0, 0) end
function Id.step(t, dt)
    local g = G()
    setHead({ 0, 0, 0 }, 0, 0)
    if g and g.items then restHand("right"); restHand("left") end
    if g and g.game and t > 1 and not Id.started then
        Id.started = true
        MOCK.buttons[require("i18n").t("bWaves")]()
    end
end
function Id.report()
    local g = G()
    return string.format("onda=%d hp=%.0f bots=%d morto=%s", g.game.wave, g.player.hp, #g.bots.list, tostring(g.player.dead))
end

---------------------------------------------------------------------------
-- Cenario: showcase — pose para screenshot (SMG com duas maos + inimigos)
---------------------------------------------------------------------------
local Sh = {}
SCENARIOS.showcase = Sh
local sh = {}
function Sh.setup() setHead({ 0, 0, 0 }, 0, 0); sh = {} end
function Sh.step(t, dt)
    local g = G()
    setHead({ 0, 0, 0 }, 4, 6)
    if not g or not g.items then return end
    local Vm = V()
    local I, R = g.items, g.rig
    if t > 0.5 and not sh.spawned then
        sh.spawned = true
        MOCK.buttons[require("i18n").t("bSandbox")]()
        g.bots.clear(true)
        sh.grunt = g.bots.spawn("grunt", { -1.0, 0, -4.4 }, { yaw = 170, force = true, passive = true })
        sh.gunner = g.bots.spawn("gunner", { 1.5, 0, -3.6 }, { yaw = 200, force = true, passive = true })
        sh.crab = g.bots.spawn("crab", { 0.35, 0, -5.6 }, { yaw = 180, force = true, passive = true })
        sh.grunt2 = g.bots.spawn("grunt", { -2.6, 0, -2.2 }, { yaw = 150, force = true, passive = true })
    end
    for _, k in ipairs({ "grunt", "gunner", "crab", "grunt2" }) do if sh[k] then sh[k].passive = true end end
    if sh.grunt then sh.grunt.attackPose = 0.7; sh.grunt.vel = { 0.3, 0, -1.2 } end
    if sh.grunt2 then sh.grunt2.vel = { 0.5, 0, -1.5 } end
    if sh.gunner then sh.gunner.aimPose = 1 end
    -- SMG com as duas maos
    local smg = I.slots[2].item
    local def = g.weapons.defs.smg
    local f = R.flatForward()
    local target = { -0.4, 1.4, -4.4 }
    local gp = Vm.add(Vm.add(R.head, Vm.scale(f, 0.32)), { 0.09, -0.2, 0 })
    local B = Vm.basis(Vm.sub(target, gp), { 0, 1, 0 })
    if not I.isHeld(smg) then
        local P = require("poses")
        local palm = Vm.poseApply(smg.pos, smg.B, P.get("pistol", "right").palm)
        placeHand("right", palm, Vm.mulMM(smg.B, P.get("pistol", "right").basis), (t > 1.2) and GRIP or OPEN)
        local palmL = Vm.poseApply(smg.pos, smg.B, Vm.add(def.grabs.fore.at, P.get("support", "left").palm))
        placeHand("left", palmL, Vm.mulMM(smg.B, P.get("support", "left").basis), (t > 1.4) and GRIP or OPEN)
    else
        local curl = (math.floor(t * 8) % 2 == 0 and t > 2.5) and FIRE or GRIP
        handForObject("right", gp, B, "grip", def, curl)
        handForObject("left", gp, B, "fore", def, GRIP)
    end
end
function Sh.report() return "held=" .. tostring(G().items.isHeld(G().items.slots[2].item)) end

---------------------------------------------------------------------------
-- Cenario: jitter — segurando a pistola com tracking ruim (tremor + perda)
-- Conta quantas vezes a arma caiu da mao sem o jogador abrir a mao.
---------------------------------------------------------------------------
local Jt = {}
SCENARIOS.jitter = Jt
local jj = {}
function Jt.setup() setHead({ 0, 0, 0 }, 0, 0); jj = { drops = 0, had = false, lostFrames = 0, noisy = 0 } end
function Jt.step(t, dt)
    local g = G()
    setHead({ 0, 0, 0 }, 0, 0)
    if not g or not g.items then return end
    local Vm, I, P = V(), g.items, require("poses")
    local gun = I.gunIn("right")
    restHand("left")
    if not jj.had then
        local it = I.slots[1].item
        local palm = Vm.poseApply(it.pos, it.B, P.get("pistol", "right").palm)
        placeHand("right", palm, Vm.mulMM(it.B, P.get("pistol", "right").basis), t > 1.5 and GRIP or OPEN)
        if gun then jj.had = true; jj.t0 = t end
        return
    end
    if jj.had and not gun and not jj.dropped then jj.drops = jj.drops + 1; jj.dropped = true end
    if gun then jj.dropped = false end
    local R = g.rig
    local gp = Vm.add(Vm.add(R.head, Vm.scale(R.flatForward(), 0.4)), { 0.1, -0.15, 0 })
    -- 15% dos frames a leitura dos dedos "abre" (ruido), e a cada 4 s a mao some por 1.5 s
    local curl = GRIP
    if math.random() < 0.15 then curl = { 0.3, 0, 0.15, 0.2, 0.1 }; jj.noisy = jj.noisy + 1 end
    local lt = t - jj.t0
    local lost = (lt % 4) > 2.5
    if lost then jj.lostFrames = jj.lostFrames + 1 end
    handForObject("right", gp, Vm.basis(R.flatForward(), { 0, 1, 0 }), "grip", g.weapons.defs.pistol, curl)
    if lost then MOCK.hands.right.tracked = false end
    -- no fim, abre a mao de verdade por 0.6 s: tem que soltar
    if lt > 14 then
        handForObject("right", gp, Vm.basis(R.flatForward(), { 0, 1, 0 }), "grip", g.weapons.defs.pistol, OPEN)
    end
end
function Jt.report()
    local g = G()
    return string.format("pegou=%s quedas_durante_ruido=%d framesRuido=%d framesSemTracking=%d soltouNoFim=%s",
        tostring(jj.had), jj.drops - (g.items.gunIn("right") and 0 or 1), jj.noisy, jj.lostFrames, tostring(g.items.gunIn("right") == nil))
end
