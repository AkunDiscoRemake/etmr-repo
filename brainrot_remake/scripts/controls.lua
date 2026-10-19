-- controls.lua — entrada unificada: hand tracking (gestos) + Joy-Con (gamepad Bluetooth).
--
-- A plataforma nao tem API oficial de controle, entao o Joy-Con e lido direto pela
-- Unity (CS.UnityEngine.Input, ou o Input System novo se existir), sempre em pcall.
-- Sem controle, tudo funciona por gestos:
--   * fechar medio/anelar/mindinho = PEGAR (abrir a mao = SOLTAR)
--   * dobrar o indicador = GATILHO
--   * mao esquerda apontando (indicador esticado, resto fechado) = ANDAR
--
-- Joy-Con: segure um em cada mao (vertical). Use "Calibrar Joy-Con" no console
-- para mapear os botoes; os mapeamentos ficam salvos.

local V = require("vec")
local A = require("api")
local L10 = require("i18n")

local C = {}

C.hands = {}
for _, s in ipairs({ "left", "right" }) do
    local lm = {}
    for i = 0, 20 do lm[i] = { 0, 0, 0 } end
    C.hands[s] = {
        side = s,
        tracked = false,
        everTracked = false,
        lostTime = 99,
        lm = lm,                 -- landmarks suavizados (locais)
        raw = {},                -- landmarks crus do frame
        curl = { 0, 0, 0, 0, 0 },-- polegar, indicador, medio, anelar, mindinho (0 esticado .. 1 fechado)
        grip = false, gripDown = false, gripUp = false,
        trigger = 0, trigDown = false, trigUp = false, trigHeld = false,
        primaryDown = false, secondaryDown = false,
        pointing = false,
        palm = { 0, 0, 0 },
        palmVel = { 0, 0, 0 },
        basis = V.identity(),    -- base da mao (f = punho->dedos, u = lado do polegar/indicador)
        hist = {},               -- historico de posicoes da palma para arremesso
        gestGrip = false, gestTrig = false,
        padGrip = false, padTrig = false,
    }
end

C.move = { 0, 0 }        -- analogico (x, y) -1..1
C.turnL, C.turnR = false, false
C.menuDown = false
C.walkHeld = false
C.gestureWalk = true
C.stickyGrab = false
C.padConnected = false
C.padNames = ""
C.calibrating = false
C.calibText = ""
C.onCalibText = nil      -- callback(texto) para mostrar instrucoes
C.lastPadActivity = -99

---------------------------------------------------------------------------
-- Leitura de gamepad
---------------------------------------------------------------------------
local Input = nil
local NIS = nil           -- UnityEngine.InputSystem (se existir)
local legacyOk = false
local nisOk = false

local NIS_CONTROLS = {
    "buttonSouth", "buttonEast", "buttonWest", "buttonNorth",
    "leftShoulder", "rightShoulder", "leftTrigger", "rightTrigger",
    "startButton", "selectButton", "leftStickButton", "rightStickButton",
}

local function initPads()
    if not A.hasCS then return end
    local ok = pcall(function()
        Input = CS.UnityEngine.Input
        local _ = Input.GetKey("joystick button 0")
    end)
    legacyOk = ok
    local ok2 = pcall(function()
        NIS = CS.UnityEngine.InputSystem
        local _ = NIS.Gamepad.all.Count
    end)
    nisOk = ok2
    A.log("Gamepad: legacy=" .. tostring(legacyOk) .. " inputSystem=" .. tostring(nisOk))
end

local function legacyKey(j, b)
    local name
    if j == 0 then name = "joystick button " .. b else name = "joystick " .. j .. " button " .. b end
    local ok, v = pcall(function() return Input.GetKey(name) end)
    return ok and v
end

local function nisKey(dev, ctrl)
    local ok, v = pcall(function()
        local g = NIS.Gamepad.all[dev]
        return g[ctrl].isPressed
    end)
    return ok and v
end

-- chave: string "L:j:b" (legacy) ou "N:dev:ctrl" (Input System)
local function keyDown(key)
    if key == nil or key == "" then return false end
    local kind, a, b = key:match("^(%a):([^:]+):([^:]+)$")
    if kind == "L" and legacyOk then return legacyKey(tonumber(a), tonumber(b)) end
    if kind == "N" and nisOk then return nisKey(tonumber(a), b) end
    return false
end

-- Varre tudo que esta apertado agora (para calibracao).
local function scanPressed()
    local res = {}
    if legacyOk then
        for j = 1, 4 do
            for b = 0, 19 do
                if legacyKey(j, b) then res[#res + 1] = "L:" .. j .. ":" .. b end
            end
        end
    end
    if nisOk then
        local ok, n = pcall(function() return NIS.Gamepad.all.Count end)
        if ok and n then
            for d = 0, n - 1 do
                for _, c in ipairs(NIS_CONTROLS) do
                    if nisKey(d, c) then res[#res + 1] = "N:" .. d .. ":" .. c end
                end
            end
        end
    end
    return res
end

-- analogico direito (so no Input System novo)
local function readRightStick()
    local x = 0
    if nisOk then
        pcall(function()
            local n = NIS.Gamepad.all.Count
            for d = 0, n - 1 do
                local v = NIS.Gamepad.all[d].rightStick:ReadValue()
                if math.abs(v.x) > math.abs(x) then x = v.x end
            end
        end)
    end
    return x
end

local function readStick()
    local x, y = 0, 0
    if nisOk then
        pcall(function()
            local n = NIS.Gamepad.all.Count
            for d = 0, n - 1 do
                local g = NIS.Gamepad.all[d]
                local v = g.leftStick:ReadValue()
                if math.abs(v.x) + math.abs(v.y) > math.abs(x) + math.abs(y) then x, y = v.x, v.y end
            end
        end)
    end
    if legacyOk and math.abs(x) + math.abs(y) < 0.05 then
        pcall(function()
            x = Input.GetAxis("Horizontal")
            y = Input.GetAxis("Vertical")
        end)
    end
    return x or 0, y or 0
end

function C.refreshPads()
    C.padConnected = false
    C.padNames = ""
    if legacyOk then
        pcall(function()
            local names = Input.GetJoystickNames()
            local list = {}
            for i = 0, names.Length - 1 do
                local n = names[i]
                if n ~= nil and n ~= "" then list[#list + 1] = n end
            end
            if #list > 0 then
                C.padConnected = true
                C.padNames = table.concat(list, ", ")
            end
        end)
    end
    if not C.padConnected and nisOk then
        pcall(function()
            if NIS.Gamepad.all.Count > 0 then
                C.padConnected = true
                C.padNames = "Gamepad (Input System)"
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Mapeamento (bindings)
---------------------------------------------------------------------------
-- Padroes para um Joy-Con no Android (qualquer joystick):
-- R1/L1 = PEGAR, R2/L2 (ZR/ZL) = GATILHO, A = soltar pente.
C.bind = {
    right_trigger = "L:0:7", right_grip = "L:0:5", right_primary = "L:0:0",
    left_trigger = "L:0:6",  left_grip = "L:0:4",  left_primary = "L:0:2",
    turnR = "", turnL = "", walk = "", menu = "L:0:10",
}

local BIND_KEYS = { "right_trigger", "right_grip", "right_primary", "left_trigger", "left_grip",
    "left_primary", "turnR", "turnL", "walk", "menu" }

function C.loadBindings()
    for _, k in ipairs(BIND_KEYS) do
        C.bind[k] = A.getStr("bind_" .. k, C.bind[k])
    end
end

function C.saveBindings()
    for _, k in ipairs(BIND_KEYS) do A.setStr("bind_" .. k, C.bind[k] or "") end
    A.setBool("calibrated", true)
    A.save()
end

---------------------------------------------------------------------------
-- Calibracao
---------------------------------------------------------------------------
-- { binding, opcional? } — o texto de cada etapa vem do i18n ("cal_<binding>")
local CAL_STEPS = {
    { "right_trigger", false }, { "right_grip", false }, { "right_primary", true },
    { "left_trigger", false }, { "left_grip", false }, { "left_primary", true },
    { "turnR", true }, { "turnL", true }, { "walk", true }, { "menu", true },
}
local function stepText(i) return L10.t("cal_" .. CAL_STEPS[i][1]) end

local cal = { step = 0, t = 0, waitRelease = true, used = {} }

local function calSay(txt)
    C.calibText = txt
    if C.onCalibText then C.onCalibText(txt) end
end

function C.startCalibration()
    if not (legacyOk or nisOk) then
        calSay(L10.t("calNoAccess"))
        return false
    end
    C.calibrating = true
    cal.step = 1
    cal.t = 0
    cal.waitRelease = true
    cal.used = {}
    cal.newBind = {}
    calSay(stepText(1))
    return true
end

local function calFinish()
    for k, v in pairs(cal.newBind) do C.bind[k] = v end
    C.saveBindings()
    C.calibrating = false
    calSay(L10.t("calDone"))
    A.sound("sounds/ui_confirm.wav")
end

local function calUpdate(dt)
    cal.t = cal.t + dt
    local pressed = scanPressed()
    if cal.waitRelease then
        if #pressed == 0 then cal.waitRelease = false end
        return
    end
    local step = CAL_STEPS[cal.step]
    local chosen = nil
    for _, k in ipairs(pressed) do
        if not cal.used[k] then chosen = k; break end
    end
    if chosen then
        cal.newBind[step[1]] = chosen
        cal.used[chosen] = true
        A.sound("sounds/ui_click.wav")
    elseif step[2] and cal.t > 7 then
        cal.newBind[step[1]] = ""
    else
        if math.floor(cal.t) ~= math.floor(cal.t - dt) and step[2] then
            calSay(stepText(cal.step) .. "\n" .. L10.t("calSkip", math.max(0, 7 - math.floor(cal.t))))
        end
        return
    end
    cal.step = cal.step + 1
    cal.t = 0
    cal.waitRelease = true
    if cal.step > #CAL_STEPS then calFinish() else calSay(stepText(cal.step)) end
end

function C.cancelCalibration()
    C.calibrating = false
end

---------------------------------------------------------------------------
-- Gestos a partir dos landmarks
---------------------------------------------------------------------------
local FINGERS = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 }, { 17, 18, 19, 20 } }

local function fingerCurl(lm, f)
    local a, b, c, d = lm[f[1]], lm[f[2]], lm[f[3]], lm[f[4]]
    local chain = V.dist(a, b) + V.dist(b, c) + V.dist(c, d)
    if chain < 1e-4 then return 0 end
    local straight = V.dist(a, d) / chain     -- 1 = esticado, ~0.35 = fechado
    return V.clamp((0.93 - straight) / (0.93 - 0.5), 0, 1)
end

local function handBasis(lm)
    local wrist = lm[0]
    local midK = lm[9]
    local fwd = V.sub(midK, wrist)
    local across = V.sub(lm[5], lm[17])       -- do mindinho para o indicador
    return V.basis(fwd, across)
end
C.handBasis = handBasis

function C.palmCenter(lm)
    return V.avg({ lm[0], lm[5], lm[9], lm[13], lm[17] })
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local now = 0
local turnLatchR, turnLatchL, menuLatch = false, false, false
local padKeyState = {}

local function edge(key)
    local d = keyDown(C.bind[key])
    local prev = padKeyState[key] or false
    padKeyState[key] = d
    if d then C.lastPadActivity = now end
    return d, d and not prev
end

function C.init()
    initPads()
    C.loadBindings()
    C.refreshPads()
    C.gestureWalk = A.getBool("gestureWalk", true)
end

local padRefreshT = 0

function C.update(dt, rig)
    now = now + dt
    padRefreshT = padRefreshT + dt
    if padRefreshT > 3 then padRefreshT = 0; C.refreshPads() end

    if C.calibrating then calUpdate(dt) end
    local padActive = (legacyOk or nisOk) and not C.calibrating

    for side, h in pairs(C.hands) do
        local ok = rig.readHand(side, h.raw)
        if ok then
            local k = V.smoothK(h.tracked and 28 or 1000, dt)
            for i = 0, 20 do V.lerpInto(h.lm[i], h.raw[i], k) end
            h.tracked = true
            h.everTracked = true
            h.lostTime = 0
        else
            h.lostTime = h.lostTime + dt
            -- segura a ultima pose por um instante (o Joy-Con na mao as vezes some do tracking)
            h.tracked = h.lostTime < 1.0 and h.everTracked
        end

        local lm = h.lm
        if h.everTracked then
            for f = 1, 5 do h.curl[f] = fingerCurl(lm, FINGERS[f]) end
            h.basis = handBasis(lm)
            local pc = C.palmCenter(lm)
            -- historico para velocidade de arremesso
            table.insert(h.hist, { now, pc })
            while #h.hist > 0 and now - h.hist[1][1] > 0.12 do table.remove(h.hist, 1) end
            if #h.hist >= 2 then
                local a, b = h.hist[1], h.hist[#h.hist]
                local ddt = b[1] - a[1]
                if ddt > 1e-3 then h.palmVel = V.scale(V.sub(b[2], a[2]), 1 / ddt) end
            end
            h.palm = pc
            -- pico de velocidade recente: o arremesso usa o pico, porque a mao
            -- so e considerada "aberta" um instante depois do movimento
            h.velHist = h.velHist or {}
            table.insert(h.velHist, { now, V.copy(h.palmVel) })
            while #h.velHist > 0 and now - h.velHist[1][1] > 0.5 do table.remove(h.velHist, 1) end
        end

        -- gestos (com histerese + tolerancia ao tremor do tracking)
        -- Fechar e facil (curl > 0.5 ou o gesto "Fist" da plataforma). Para SOLTAR, a mao
        -- precisa ficar claramente aberta por um tempo — um frame ruim nao derruba a arma.
        local gripCurl = (h.curl[3] + h.curl[4] + h.curl[5]) / 3
        local platFist = false
        if h.tracked and ok then
            local g = rig.gesture(side)
            platFist = g == "Fist"
        end
        if h.gestGrip then
            if not h.tracked then
                -- sem tracking: mantem como estava (nao solta o que esta na mao)
                h.openT = 0
            elseif gripCurl < (h.busy and 0.2 or 0.3) and not platFist then
                h.openT = (h.openT or 0) + dt
                if h.openT > (h.busy and 0.3 or 0.12) then h.gestGrip = false; h.openT = 0 end
            else
                h.openT = 0
            end
        elseif h.tracked and (gripCurl > 0.5 or platFist) then
            h.gestGrip = true
            h.openT = 0
        end
        if h.gestTrig then
            if h.curl[2] < 0.35 then h.gestTrig = false end
        else
            if h.curl[2] > 0.6 then h.gestTrig = true end
        end
        h.pointing = h.tracked and h.curl[2] < 0.25 and gripCurl > 0.6

        -- gamepad
        local pGrip, pTrig, pPrim = false, false, false
        local pPrimDown = false
        if padActive then
            pGrip = edge(side .. "_grip")
            pTrig = edge(side .. "_trigger")
            pPrim, pPrimDown = edge(side .. "_primary")
        end
        h.padGrip, h.padTrig = pGrip, pTrig
        local usingPad = (now - C.lastPadActivity) < 20 and padActive

        local grip
        if usingPad then grip = pGrip else grip = h.gestGrip end
        -- modo alternado: cada "fechar" alterna entre segurar e soltar
        if C.stickyGrab then
            local closedEdge = grip and not h.rawGrip
            h.rawGrip = grip
            if closedEdge then
                if h.busy then h.toggled = false else h.toggled = true; h.toggleT = 0 end
            end
            if h.toggled and not h.busy then
                -- fechou a mao mas nao pegou nada: depois de meio segundo volta a "solto"
                h.toggleT = (h.toggleT or 0) + dt
                if h.toggleT > 0.5 then h.toggled = false end
            end
            grip = h.toggled == true
        end
        h.gripDown = grip and not h.grip
        h.gripUp = (not grip) and h.grip
        h.grip = grip

        local trig
        if usingPad then trig = pTrig and 1 or 0 else trig = h.curl[2] end
        local trigHeld
        if usingPad then trigHeld = pTrig else trigHeld = h.gestTrig end
        h.trigDown = trigHeld and not h.trigHeld
        h.trigUp = (not trigHeld) and h.trigHeld
        h.trigHeld = trigHeld
        h.trigger = trig
        h.primaryDown = pPrimDown
        h.usingPad = usingPad
    end

    -- locomocao e giro
    C.move[1], C.move[2] = 0, 0
    C.turnL, C.turnR, C.menuDown = false, false, false
    if padActive then
        local x, y = readStick()
        if math.abs(x) > 0.15 or math.abs(y) > 0.15 then
            C.move[1], C.move[2] = x, y
            C.lastPadActivity = now
        end
        local w = edge("walk")
        if w then C.move[2] = 1 end
        local _, tr = edge("turnR")
        local _, tl = edge("turnL")
        local _, mn = edge("menu")
        C.turnR, C.turnL, C.menuDown = tr, tl, mn
        local rx = readRightStick()
        local dirR = rx > 0.6 and 1 or (rx < -0.6 and -1 or 0)
        if dirR ~= 0 and (C.smoothTurnHint or dirR ~= C.rsLatch) then
            if dirR > 0 then C.turnR = true else C.turnL = true end
            C.lastPadActivity = now
        end
        C.rsLatch = dirR
    end
    -- andar por gesto: mao esquerda apontando e livre
    local lh = C.hands.left
    C.walkHeld = false
    if C.gestureWalk and lh.pointing and not lh.busy and math.abs(C.move[2]) < 0.1 then
        C.move[2] = 1
        C.walkHeld = true
    end
end

-- Velocidade de arremesso: o maior pico dos ultimos 0.4 s
function C.throwVelocity(side)
    local h = C.hands[side]
    local best, bl = h.palmVel, V.len(h.palmVel)
    for _, e in ipairs(h.velHist or {}) do
        local l = V.len(e[2])
        if l > bl then best, bl = e[2], l end
    end
    return V.copy(best)
end

return C
