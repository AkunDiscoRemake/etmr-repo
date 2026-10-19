-- ============================================================================
--  SUPERHOT REMAKE (fan remake) — EnJoyTheMR / VR Box
--  Modo Lua puro, display "scene". Ponto de entrada.
--
--  O TEMPO SO ANDA QUANDO VOCE SE MOVE.
--  * inimigos de cristal vermelho que estilhacam
--  * balas lentas: desvie, corte com a katana, derrube com outra bala
--  * sem recarga: arremesse a arma vazia; arranque armas das maos deles
--  * 10 fases + modo infinito, maos fake articuladas, Joy-Con ou gestos
-- ============================================================================

local V = require("vec")
local A = require("api")
local R = require("rig")
local C = require("controls")
local H = require("hands")
local TF = require("timeflow")
local F = require("fx")
local L = require("level")
local Wp = require("weapons")
local I = require("items")
local Bu = require("bullets")
local E = require("enemies")
local Pl = require("player")
local Gm = require("game")
local L10 = require("i18n")

local G = {
    realTime = 0, frame = 0, mode = "boot", levelTime = 0,
    rig = R, controls = C, hands = H, time = TF, fx = F, level = L, weapons = Wp, items = I,
    bullets = Bu, enemies = E, player = Pl, game = Gm,
    aimAssist = true, stats = { shots = 0, kills = 0 }, settings = {},
}
SUPERHOT = G

-- sons: o tom acompanha o tempo do jogo (camera lenta soa grave)
function G.sound3D(path, p, vol, pitch)
    local tp = 0.62 + 0.38 * TF.ts
    return A.sound3D(path, p, vol, (pitch or 1) * tp)
end
function G.sound(path, vol) return A.sound(path, vol) end

local started = false
local seenErr = {}
local errCount = 0

local function reportError(where, err)
    errCount = errCount + 1
    local key = tostring(err)
    if not seenErr[key] then
        seenErr[key] = true
        EMRAPI:LogError("[SuperHot] erro em " .. where .. ": " .. key)
    end
end

local function loadSettings()
    local s = G.settings
    s.height = A.getNum("height", 1.65)
    s.moveSpeed = A.getNum("moveSpeed", 1.8)
    s.musicVol = A.getNum("musicVol", 0.5)
    s.aimAssist = A.getBool("aimAssist", true)
    s.gestureWalk = A.getBool("gestureWalk", true)
    s.passthrough = A.getBool("passthrough", false)
    s.smoothTurn = A.getBool("smoothTurn", false)
    s.stickyGrab = A.getBool("stickyGrab", false)
    s.snapAngle = 45
    G.aimAssist = s.aimAssist
end

local function boot()
    loadSettings()
    L10.init()
    pcall(function() EMRAPI.Camera:SetBackground(G.settings.passthrough and "show" or "hide") end)
    R.init({ 0, 0, 0 }, G.settings.height)
    A.probe(R.world)
    F.init(R.world)
    F.setRaycast(function(o, d, m) return L.raycast(o, d, m) end)
    H.init(R.world)
    C.init()
    C.gestureWalk = G.settings.gestureWalk
    C.stickyGrab = G.settings.stickyGrab
    Wp.init(G)
    I.init(G)
    Bu.init(G)
    E.init(G)
    Pl.init(G)
    Gm.init(G)
    Gm.toLobby()
    if C.padConnected and not A.getBool("calibrated", false) then
        EMRAPI.Timer:Delay(3, function() Gm.message("padFound", 3) end)
    end
    A.log("pronto. CS=" .. tostring(A.hasCS))
end

function OnStart()
    local ok, err = xpcall(boot, debug and debug.traceback or tostring)
    if not ok then reportError("OnStart", err) end
    started = true
end

---------------------------------------------------------------------------
local turnCd = 0
local moving = false

local function locomotion(dt)
    local s = G.settings
    local mx, my = C.move[1], C.move[2]
    moving = false
    if Pl.dead or G.mode == "win" then mx, my = 0, 0 end
    if math.abs(mx) > 0.01 or math.abs(my) > 0.01 then
        local f = R.flatForward()
        local r = { f[3], 0, -f[1] }
        local d = V.add(V.scale(f, my), V.scale(r, mx))
        if V.len(d) > 1 then d = V.norm(d) end
        local spd = s.moveSpeed * (C.walkHeld and 0.7 or 1)
        R.move(d[1] * spd * dt, d[3] * spd * dt)
        moving = true
    else
        R.resolvePhysicalCollision()
    end
    turnCd = turnCd - dt
    if s.smoothTurn then
        if C.turnL then R.turn(-90 * dt * 4) end
        if C.turnR then R.turn(90 * dt * 4) end
    elseif turnCd <= 0 then
        if C.turnR then R.turn(s.snapAngle); turnCd = 0.25 end
        if C.turnL then R.turn(-s.snapAngle); turnCd = 0.25 end
    end
end

local function drawHands()
    for _, side in ipairs({ "left", "right" }) do
        local h = C.hands[side]
        local posed = I.handPose[side]
        if posed then
            H.setVisible(side, true); H.draw(side, posed)
        elseif h.tracked then
            H.setVisible(side, true); H.draw(side, h.lm)
        else
            H.setVisible(side, false)
        end
    end
end

local function step(dt)
    G.realTime = G.realTime + dt
    G.frame = G.frame + 1
    R.update(dt)
    C.update(dt, R)
    if not C.calibrating then locomotion(dt) end
    local gdt = TF.update(dt, R, C.hands, moving)
    if G.mode == "lobby" then gdt = dt end   -- no saguao o mundo anda normal
    I.update(dt, gdt)
    drawHands()
    E.update(gdt, dt)
    Bu.update(gdt)
    Pl.update(dt)
    F.update(gdt, dt)
    Gm.update(dt, gdt)
end

function OnUpdate(dt)
    if not started or dt == nil or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    local ok, err = xpcall(step, debug and debug.traceback or tostring, dt)
    if not ok then reportError("OnUpdate", err) end
end

function OnPause() I.releaseAll() end
function OnResume() end

function OnDestroy()
    G.mode = "off"
    pcall(function() Gm.shutdown() end)
    pcall(function() EMRAPI.Tween:CancelAll() end)
    pcall(function() EMRAPI.Audio:Stop() end)
    pcall(function() H.reset() end)
    pcall(function() EMRAPI.Camera:Reset() end)
    A.log("encerrado. tiros=" .. G.stats.shots .. " abates=" .. G.stats.kills .. " erros=" .. errCount)
end
