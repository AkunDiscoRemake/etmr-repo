-- ============================================================================
--  BONELAB REMAKE (fan remake) — EnJoyTheMR / VR Box
--  Modo Lua puro, display "scene". Ponto de entrada.
--
--  * Mao fake articulada (21 juntas) que se encaixa nas armas
--  * Joy-Con (Bluetooth) + gestos das maos
--  * Pistola, SMG, escopeta (bomba), taco; pentes fisicos e bolsa no quadril
--  * Bots com IA: Grunt, Atirador (plasma), Crab (pula no rosto), boneco de treino
--  * Modo ONDAS, SANDBOX, ragdoll, barris explosivos, caixas com fisica
-- ============================================================================

local V = require("vec")
local A = require("api")
local R = require("rig")
local C = require("controls")
local H = require("hands")
local F = require("fx")
local L = require("level")
local Wp = require("weapons")
local I = require("items")
local Bt = require("bots")
local Pr = require("props")
local Cb = require("combat")
local Pl = require("player")
local Gm = require("game")

-- contexto compartilhado entre modulos
local G = {
    time = 0, frame = 0, mode = "boot",
    rig = R, controls = C, hands = H, fx = F, level = L, weapons = Wp, items = I,
    bots = Bt, props = Pr, combat = Cb, player = Pl, game = Gm,
    infiniteAmmo = false, aimAssist = true,
    stats = { shots = 0, kills = 0, headshots = 0 },
    settings = {},
}
BONELAB = G   -- global para depuracao

local started = false
local errCount = 0
local seenErr = {}

local function reportError(where, err)
    errCount = errCount + 1
    local key = tostring(err)
    if not seenErr[key] then
        seenErr[key] = true
        EMRAPI:LogError("[BoneLab] erro em " .. where .. ": " .. key)
    end
end

local function loadSettings()
    local s = G.settings
    s.height = A.getNum("height", 1.65)
    s.moveSpeed = A.getNum("moveSpeed", 2.4)
    s.musicVol = A.getNum("musicVol", 0.45)
    s.aimAssist = A.getBool("aimAssist", true)
    s.gestureWalk = A.getBool("gestureWalk", true)
    s.passthrough = A.getBool("passthrough", false)
    s.smoothTurn = A.getBool("smoothTurn", false)
    s.snapAngle = 45
    G.aimAssist = s.aimAssist
end

local function boot()
    loadSettings()
    pcall(function() EMRAPI.Camera:SetBackground(G.settings.passthrough and "show" or "hide") end)

    R.init(L.playerSpawn, G.settings.height)
    A.probe(R.world)

    L.build(R.world, R)
    F.init(R.world)
    H.init(R.world)
    C.init()
    C.gestureWalk = G.settings.gestureWalk

    Wp.init(G)
    I.init(G)
    Cb.init(G)
    Pr.init(G)
    Bt.init(G)
    Pl.init(G)
    Gm.init(G)

    I.setupTable()
    Pr.setup()

    Gm.toHub()
    Gm.message("BEM-VINDO AO LAB", 3, "welcome")
    if C.padConnected and not A.getBool("calibrated", false) then
        EMRAPI.Timer:Delay(3.5, function()
            Gm.message("Joy-Con detectado! Aperte CALIBRAR no console", 3, "calib")
        end)
    end
    A.log("pronto. CS=" .. tostring(A.hasCS) .. " material=" .. tostring(A.matOk))
end

function OnStart()
    local ok, err = xpcall(boot, debug and debug.traceback or tostring)
    if not ok then
        reportError("OnStart", err)
    end
    started = true
end

---------------------------------------------------------------------------
-- Locomocao: analogico / gesto / botao, virar (snap ou suave)
---------------------------------------------------------------------------
local turnCooldown = 0

local function locomotion(dt)
    local s = G.settings
    local mx, my = C.move[1], C.move[2]
    if Pl.dead then mx, my = 0, 0 end
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local f = R.flatForward()
        local r = { f[3], 0, -f[1] }
        local spd = s.moveSpeed
        if C.walkHeld then spd = spd * 0.6 end
        local d = V.add(V.scale(f, my), V.scale(r, mx))
        if V.len(d) > 1 then d = V.norm(d) end
        R.move(d[1] * spd * dt, d[3] * spd * dt)
        G.walkPhase = (G.walkPhase or 0) + dt * spd * 2.2
        if math.floor(G.walkPhase) ~= math.floor(G.walkPhase - dt * spd * 2.2) then
            A.sound("sounds/step.wav", 0.35)
        end
    else
        R.resolvePhysicalCollision()
    end
    turnCooldown = turnCooldown - dt
    if s.smoothTurn then
        if C.turnL then R.turn(-90 * dt * 4) end
        if C.turnR then R.turn(90 * dt * 4) end
    elseif turnCooldown <= 0 then
        if C.turnR then R.turn(s.snapAngle); turnCooldown = 0.25 end
        if C.turnL then R.turn(-s.snapAngle); turnCooldown = 0.25 end
    end
end

---------------------------------------------------------------------------
-- Desenho das maos fake: pose da arma (se segurando) ou landmarks rastreados
---------------------------------------------------------------------------
local function drawHands()
    for _, side in ipairs({ "left", "right" }) do
        local h = C.hands[side]
        local posed = I.handPose[side]
        if posed then
            H.setVisible(side, true)
            H.draw(side, posed)
        elseif h.tracked then
            H.setVisible(side, true)
            H.draw(side, h.lm)
        else
            H.setVisible(side, false)
        end
    end
end

local function step(dt)
    G.time = G.time + dt
    G.frame = G.frame + 1
    R.update(dt)
    C.update(dt, R)
    if not C.calibrating then locomotion(dt) end
    I.update(dt)
    drawHands()
    Pr.update(dt)
    Bt.update(dt)
    Pl.update(dt)
    F.update(dt)
    Gm.update(dt)
end

function OnUpdate(dt)
    if not started then return end
    if dt == nil or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    local ok, err = xpcall(step, debug and debug.traceback or tostring, dt)
    if not ok then reportError("OnUpdate", err) end
end

function OnPause()
    I.releaseAll()
end

function OnResume() end

function OnDestroy()
    G.mode = "off"
    pcall(function() Gm.shutdown() end)
    pcall(function() EMRAPI.Tween:CancelAll() end)
    pcall(function() EMRAPI.Audio:Stop() end)
    pcall(function() H.reset() end)
    pcall(function() EMRAPI.Camera:Reset() end)
    pcall(function() EMRAPI.Keyboard:Reset() end)
    A.log("encerrado. tiros=" .. G.stats.shots .. " abates=" .. G.stats.kills .. " erros=" .. errCount)
end
