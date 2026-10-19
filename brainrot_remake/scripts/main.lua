-- ============================================================================
--  RE:STEAL A BRAINROT VR — EnJoyTheMR / VR Box
--  Modo Lua puro, display "scene". Ponto de entrada.
--
--  * compre brainrots ITALIANOS na esteira vermelha (comeca com $200)
--  * eles geram dinheiro na sua base: pise na placa verde para coletar
--  * ROUBE dos outros: segure 5 s no brainrot e corra para casa
--  * defenda a base com o taco e tranque com o botao vermelho (lasers!)
--  * noite de Halloween, evento Candy, evento de Lava (raro) com boosts
--  * online (Photon) ou solo com bots rivais; avatares Bacon Hair e Acorn Girl
--  * anda com o analogico do Joy-Con (ou gesto de apontar com a mao esquerda)
-- ============================================================================

local V = require("vec")
local A = require("api")
local R = require("rig")
local C = require("controls")
local H = require("hands")
local L10 = require("i18n")
local W = require("world")
local Bs = require("bases")
local CV = require("conveyor")
local E = require("ents")
local AI = require("ai")
local Pl = require("player")
local Ev = require("events")
local Pr = require("prompts")
local Lb = require("labels")
local Hd = require("hud")
local F = require("fx")
local N = require("net")
local Gm = require("game")

local G = {
    realTime = 0, frame = 0, settings = {},
    rig = R, controls = C, hands = H, world = W, bases = Bs, conveyor = CV, ents = E, ai = AI,
    player = Pl, events = Ev, prompts = Pr, labels = Lb, hud = Hd, fx = F, net = N, game = Gm,
    localId = "me", myBase = nil, localEnt = nil,
}
BRAINROT = G

-- gerador aleatorio proprio (nao depende do math.random global)
local seed = 12345
do
    local ok, t = pcall(function() return os.time() end)
    if ok and type(t) == "number" then seed = t % 2147483647 end
end
function G.rand()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

function G.sound(path, vol) return A.sound(path, vol) end
function G.sound3D(path, p, vol, pitch) return A.sound3D(path, p, vol, pitch) end

local started = false
local seenErr = {}
local errCount = 0

local function reportError(where, err)
    errCount = errCount + 1
    local key = tostring(err)
    if not seenErr[key] then
        seenErr[key] = true
        EMRAPI:LogError("[Brainrot] erro em " .. where .. ": " .. key)
    end
end

local function loadSettings()
    local s = G.settings
    s.height = A.getNum("height", 1.65)
    s.moveSpeed = A.getNum("moveSpeed", 4.0)
    s.musicVol = A.getNum("musicVol", 0.5)
    s.gestureWalk = A.getBool("gestureWalk", true)
    s.smoothTurn = A.getBool("smoothTurn", false)
    s.difficulty = A.getStr("difficulty", "normal")
    s.avatar = A.getStr("avatar", "bacon")
    s.outfit = A.getNum("outfit", s.avatar == "acorn" and 7 or 1)
    s.snapAngle = 45
    local nick = A.getStr("nick", "")
    if nick == "" then
        nick = "Player" .. tostring(1000 + math.floor(G.rand() * 8999))
        A.setStr("nick", nick)
        A.save()
    end
    s.nick = nick
end

local function boot()
    loadSettings()
    L10.init()
    pcall(function() EMRAPI.Camera:SetBackground("hide") end)
    R.init({ 0, 0, 0 }, G.settings.height)
    A.probe(R.world)
    W.build(R.world)
    R.obstacles = W.obstacles
    R.bounds = require("layout").BOUNDS
    Gm.applyAvatarColors(G)
    H.init(R.world)
    C.init()
    C.gestureWalk = G.settings.gestureWalk
    F.init(G, R.world)
    Lb.init(R.world)
    Bs.init(G)
    CV.init(G)
    E.init(G)
    AI.init(G)
    Pl.init(G)
    Ev.init(G)
    Pr.init(G)
    Hd.init(G)
    N.init(G)
    Gm.init(G)
    Gm.startSolo()
    A.log("pronto. CS=" .. tostring(A.hasCS) .. " MP=" .. tostring(N.available()))
end

function OnStart()
    local ok, err = xpcall(boot, debug and debug.traceback or tostring)
    if not ok then reportError("OnStart", err) end
    started = true
end

---------------------------------------------------------------------------
local turnCd = 0

local function locomotion(dt)
    local s = G.settings
    local mx, my = C.move[1], C.move[2]
    local mult = Pl.speedMult()
    G.moveSpeedNow = 0
    -- laser das bases trancadas bloqueia o jogador (menos na propria base)
    local dyn = {}
    local here = { R.head[1], 0, R.head[3] }
    for i = 1, 8 do
        if Bs.isLocked(i) and i ~= G.myBase and not require("layout").inBase(i, here, 0.2) then
            dyn[#dyn + 1] = { box = W.bases[i].laserBox }
        end
    end
    R.dynamic = dyn
    if mult > 0 and (math.abs(mx) > 0.01 or math.abs(my) > 0.01) then
        local f = R.flatForward()
        local r = { f[3], 0, -f[1] }
        local d = V.add(V.scale(f, my), V.scale(r, mx))
        if V.len(d) > 1 then d = V.norm(d) end
        local spd = s.moveSpeed * mult * (C.walkHeld and 0.75 or 1)
        local before = { R.head[1], R.head[3] }
        R.move(d[1] * spd * dt, d[3] * spd * dt)
        G.moveSpeedNow = math.sqrt((R.head[1] - before[1]) ^ 2 + (R.head[3] - before[2]) ^ 2) / math.max(dt, 1e-4)
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

local function step(dt)
    G.realTime = G.realTime + dt
    G.frame = G.frame + 1
    R.update(dt)
    C.update(dt, R)
    if not C.calibrating then locomotion(dt) end
    local feet = { R.head[1], 0, R.head[3] }
    Pl.update(dt)
    local auth = Gm.update(dt)
    AI.update(dt)
    CV.update(dt, G.realTime, feet, auth)
    Bs.update(dt, G.realTime, feet)
    E.update(dt, R.head)
    Ev.update(dt, auth, feet)
    W.update(dt, G.realTime)
    F.update(dt, R.head)
    Lb.update(R.head)
    Hd.update(dt)
end

function OnUpdate(dt)
    if not started or dt == nil or dt <= 0 then return end
    if dt > 0.05 then dt = 0.05 end
    local ok, err = xpcall(step, debug and debug.traceback or tostring, dt)
    if not ok then reportError("OnUpdate", err) end
end

function OnPause() pcall(Gm.save) end
function OnResume() end

function OnDestroy()
    pcall(function() Gm.shutdown() end)
    pcall(function() EMRAPI.Tween:CancelAll() end)
    pcall(function() EMRAPI.Audio:Stop() end)
    pcall(function() H.reset() end)
    pcall(function() EMRAPI.Camera:Reset() end)
    A.log("encerrado. erros=" .. errCount)
end
