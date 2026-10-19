-- game.lua — estado do jogo: Laboratorio (hub), modo ONDAS (arena), SANDBOX,
-- console de botoes 3D (aperte com o dedo!), placar na parede, mensagens, musica e menu.

local V = require("vec")
local A = require("api")
local Seg = require("segdisplay")

local Gm = {}
local G

Gm.score = 0
Gm.best = 0
Gm.wave = 0
Gm.kills = 0
Gm.combo = 0
Gm.comboT = 0
Gm.shake = 0

local board = {}
local console = { buttons = {} }
local msg = { obj = nil, t = 0, dur = 0 }
local waveState = { phase = "idle", t = 0, toSpawn = 0, spawned = 0, spawnT = 0 }
local music = { id = nil, track = nil }
local ui = {}

---------------------------------------------------------------------------
-- Musica
---------------------------------------------------------------------------
local function playMusic(track)
    if music.track == track then return end
    if music.id then pcall(function() EMRAPI.Audio:Stop(music.id) end) end
    music.track = track
    music.id = nil
    if not track then return end
    local ok, id = pcall(function() return EMRAPI.Audio:PlayLoop(track) end)
    if ok then
        music.id = id
        pcall(function() EMRAPI.Audio:SetVolume(id, G.settings.musicVol) end)
    end
end

function Gm.setMusicVolume(v)
    G.settings.musicVol = v
    if music.id then pcall(function() EMRAPI.Audio:SetVolume(music.id, v) end) end
end

---------------------------------------------------------------------------
-- Mensagens grandes (texturas pre-renderizadas) + texto no painel de UI
---------------------------------------------------------------------------
local MSG_TEX = {
    wave = "images/msg_wave.png", clear = "images/msg_clear.png", dead = "images/msg_dead.png",
    crab = "images/msg_crab.png", record = "images/msg_record.png", welcome = "images/msg_welcome.png",
    sandbox = "images/msg_sandbox.png", hub = "images/msg_hub.png", calib = "images/msg_calib.png",
    gameover = "images/msg_gameover.png",
}

local function makeMessageBoard()
    msg.root = A.empty("msgBoard", G.rig.world)
    msg.quad = A.prim("quad", { parent = msg.root, scale = { 1.6, 0.4, 1 }, color = { 1, 1, 1 }, mat = { emit = { 0.08, 0.08, 0.08 }, noShadow = true } })
    msg.num = Seg.new({ parent = msg.root, center = { 0, -0.33, 0 }, n = 2, size = 0.2, on = { 1, 0.45, 0.08 } })
    A.setVisible(msg.root, false)
end

function Gm.message(text, dur, key, number)
    A.log(text)
    if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, text) end) end
    if not key then
        if text:find("CRAB") then key = "crab" end
    end
    if not key or not MSG_TEX[key] then return end
    A.texture(msg.quad, MSG_TEX[key])
    -- 2.2 m a frente do jogador, na altura dos olhos, virado pra ele
    local f = G.rig.flatForward()
    local p = V.add(G.rig.head, V.scale(f, 2.2))
    p[2] = G.rig.head[2] + 0.1
    A.pos(msg.root, p)
    A.rotBasis(msg.root, V.basis(f, { 0, 1, 0 }))
    A.setVisible(msg.root, true)
    A.setVisible(msg.num.root, number ~= nil)
    if number then msg.num:set(number) end
    A.scale(msg.root, 0.01)
    pcall(function() EMRAPI.Tween:ScaleTo(msg.root, 1, 1, 1, 0.25) end)
    msg.t = 0
    msg.dur = dur or 2.5
    msg.active = true
end

local function updateMessage(dt)
    if not msg.active then return end
    msg.t = msg.t + dt
    if msg.t > msg.dur then
        msg.active = false
        A.setVisible(msg.root, false)
    end
end

---------------------------------------------------------------------------
-- Placar na parede do fundo
---------------------------------------------------------------------------
local function makeScoreboard()
    local z = G.level.size - 0.06
    local B = V.identity()   -- leitor olha para +Z
    local function label(tex, x, y, w)
        A.prim("quad", { parent = G.rig.world, pos = { x, y, z }, scale = { w, w * 0.25, 1 }, color = { 1, 1, 1 }, tex = tex, mat = { noShadow = true } })
    end
    A.prim("cube", { parent = G.rig.world, pos = { 0, 3.05, z + 0.02 }, scale = { 7.6, 2.5, 0.06 }, color = { 0.05, 0.05, 0.06 }, mat = { metal = 0.6, smooth = 0.7 } })
    A.prim("cube", { parent = G.rig.world, pos = { 0, 4.33, z - 0.01 }, scale = { 7.7, 0.05, 0.05 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.5, 0.5, 0.05 }, noShadow = true } })
    A.prim("cube", { parent = G.rig.world, pos = { 0, 1.77, z - 0.01 }, scale = { 7.7, 0.05, 0.05 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.5, 0.5, 0.05 }, noShadow = true } })
    label("images/lbl_wave.png", -2.6, 3.95, 1.6)
    label("images/lbl_score.png", 1.2, 3.95, 1.6)
    label("images/lbl_best.png", 1.2, 2.75, 1.6)
    label("images/lbl_enemies.png", -2.6, 2.75, 1.6)
    board.wave = Seg.new({ parent = G.rig.world, center = { -2.6, 3.4, z - 0.02 }, basis = B, n = 2, size = 0.42 })
    board.enemies = Seg.new({ parent = G.rig.world, center = { -2.6, 2.2, z - 0.02 }, basis = B, n = 2, size = 0.42, on = { 0.2, 0.8, 1 } })
    board.score = Seg.new({ parent = G.rig.world, center = { 1.2, 3.4, z - 0.02 }, basis = B, n = 6, size = 0.42, on = { 0.3, 1, 0.5 } })
    board.best = Seg.new({ parent = G.rig.world, center = { 1.2, 2.2, z - 0.02 }, basis = B, n = 6, size = 0.42, on = { 1, 0.85, 0.2 } })
end

local function refreshBoard()
    board.wave:set(Gm.wave, "0")
    board.score:set(Gm.score)
    board.best:set(Gm.best)
    board.enemies:set(G.bots.aliveCount(false) + math.max(0, waveState.toSpawn - waveState.spawned), "0")
end

---------------------------------------------------------------------------
-- Console com botoes 3D
---------------------------------------------------------------------------
local BUTTONS = {
    { id = "waves", tex = "images/btn_waves.png", color = { 1, 0.45, 0.08 } },
    { id = "sandbox", tex = "images/btn_sandbox.png", color = { 0.2, 0.8, 1 } },
    { id = "hub", tex = "images/btn_hub.png", color = { 0.85, 0.85, 0.9 } },
    { id = "calib", tex = "images/btn_calib.png", color = { 0.9, 0.2, 0.3 } },
    { id = "grunt", tex = "images/btn_grunt.png", color = { 1, 0.45, 0.08 } },
    { id = "gunner", tex = "images/btn_gunner.png", color = { 0.2, 0.8, 1 } },
    { id = "crab", tex = "images/btn_crab.png", color = { 0.6, 1, 0.2 } },
    { id = "clear", tex = "images/btn_clear.png", color = { 0.95, 0.85, 0.2 } },
}

local function makeConsole()
    local t = G.level.tableTop
    -- console a direita da mesa, inclinado para o jogador
    local center = { t[1] + 1.35, 1.0, t[3] - 0.35 }
    -- frente do console (local -Z) virada para o ponto de spawn do jogador
    local ps = G.level.playerSpawn
    local yaw = math.atan(center[1] - ps[1], center[3] - ps[3]) * V.DEG
    local tilt = 35
    local Bc = V.mulMM(V.basisFromEuler(0, yaw, 0), V.basisFromEuler(-tilt, 0, 0))
    console.B = Bc
    console.center = center
    -- pe e tampo
    A.prim("cube", { parent = G.rig.world, pos = { center[1], 0.45, center[3] + 0.08 }, scale = { 0.18, 0.9, 0.18 }, color = { 0.13, 0.13, 0.15 }, mat = { metal = 0.8, smooth = 0.6 } })
    local top = A.prim("cube", { parent = G.rig.world, pos = center, scale = { 0.78, 0.04, 0.42 }, color = { 0.16, 0.16, 0.19 }, mat = { metal = 0.7, smooth = 0.7 }, tex = "images/console.png" })
    A.rotBasis(top, Bc)
    local edge = A.prim("cube", { parent = G.rig.world, pos = V.poseApply(center, Bc, { 0, 0.005, -0.215 }), scale = { 0.8, 0.03, 0.02 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.4, 0.45, 0.04 } } })
    A.rotBasis(edge, Bc)
    G.rig.obstacles[#G.rig.obstacles + 1] = { box = { center[1] - 0.3, center[1] + 0.3, center[3] - 0.25, center[3] + 0.25 } }

    for i, b in ipairs(BUTTONS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local lp = { -0.27 + col * 0.18, 0.02, 0.09 - row * 0.17 }
        local cap = A.prim("cylinder", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.035, lp[3] }), scale = { 0.1, 0.018, 0.1 }, color = b.color, mat = { metal = 0.3, smooth = 0.8, emit = { b.color[1] * 0.5, b.color[2] * 0.5, b.color[3] * 0.5 } } })
        A.rotBasis(cap, Bc)
        local ring = A.prim("cylinder", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.022, lp[3] }), scale = { 0.125, 0.01, 0.125 }, color = { 0.08, 0.08, 0.09 }, mat = { metal = 0.8, smooth = 0.6 } })
        A.rotBasis(ring, Bc)
        -- etiqueta deitada no tampo, abaixo do botao
        local lbl = A.prim("quad", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.0215, lp[3] - 0.075 }), scale = { 0.16, 0.04, 1 }, color = { 1, 1, 1 }, tex = b.tex, mat = { noShadow = true } })
        -- quad olha para -Z; queremos olhar para +u do tampo (para cima)
        A.rotBasis(lbl, { r = Bc.r, u = Bc.f, f = V.scale(Bc.u, -1) })
        console.buttons[#console.buttons + 1] = {
            id = b.id, cap = cap, lp = lp, top = V.poseApply(center, Bc, { lp[1], 0.045, lp[3] }), pressT = 0, held = false, color = b.color,
        }
    end
end

local function pressButton(id)
    A.sound("sounds/ui_click.wav", 1)
    if id == "waves" then Gm.startWaves()
    elseif id == "sandbox" then Gm.startSandbox()
    elseif id == "hub" then Gm.toHub()
    elseif id == "calib" then
        if G.controls.startCalibration() then Gm.message("CALIBRANDO JOY-CON", 3, "calib") end
    elseif id == "clear" then
        G.bots.clear(false)
    elseif id == "grunt" or id == "gunner" or id == "crab" then
        if G.mode ~= "sandbox" then Gm.startSandbox() end
        Gm.spawnNear(id)
    end
end

local function updateConsole(dt)
    for _, b in ipairs(console.buttons) do
        b.pressT = math.max(0, b.pressT - dt)
        local pressedNow = false
        for _, side in ipairs({ "left", "right" }) do
            local h = G.hands.get(side)
            local cs = G.controls.hands[side]
            if h and h.visible and cs.tracked then
                for _, tip in ipairs({ 8, 12 }) do
                    if V.dist(h.pts[tip], b.top) < 0.055 then pressedNow = true end
                end
            end
        end
        if pressedNow and not b.held and b.pressT <= 0 then
            b.pressT = 0.6
            pressButton(b.id)
        end
        if pressedNow ~= b.held then
            b.held = pressedNow
            local depth = pressedNow and 0.022 or 0.035
            A.pos(b.cap, V.poseApply(console.center, console.B, { b.lp[1], depth, b.lp[3] }))
        end
    end
end

---------------------------------------------------------------------------
-- Modos
---------------------------------------------------------------------------
local function farPortal()
    local best, bd = nil, -1
    local list = {}
    for _, p in ipairs(G.level.portals) do
        local d = V.distXZ(p, G.rig.head)
        if d > 6 then list[#list + 1] = p end
        if d > bd then bd = d; best = p end
    end
    if #list > 0 then return list[math.random(1, #list)] end
    return best
end

function Gm.spawnNear(type)
    local p = farPortal()
    local f = G.rig.flatForward()
    local yaw = math.atan(-f[1], -f[3]) * V.DEG
    G.bots.spawn(type, p, { yaw = yaw })
end

local function spawnDummies()
    G.bots.spawn("dummy", { -1.6, 0, -4.6 }, { yaw = 180, force = true })
    G.bots.spawn("dummy", { 1.6, 0, -4.6 }, { yaw = 180, force = true })
end

function Gm.toHub()
    G.mode = "hub"
    G.modeGen = (G.modeGen or 0) + 1
    G.bots.clear(true)
    waveState.phase = "idle"
    waveState.toSpawn, waveState.spawned = 0, 0
    G.player.heal(true)
    G.infiniteAmmo = false
    spawnDummies()
    playMusic("sounds/music_lab.wav")
    Gm.message("LABORATORIO", 2.5, "hub")
    refreshBoard()
end

function Gm.startSandbox()
    G.mode = "sandbox"
    G.modeGen = (G.modeGen or 0) + 1
    G.bots.clear(true)
    waveState.phase = "idle"
    waveState.toSpawn, waveState.spawned = 0, 0
    G.player.heal(true)
    G.infiniteAmmo = true
    spawnDummies()
    playMusic("sounds/music_lab.wav")
    Gm.message("SANDBOX: aperte GRUNT/ATIRADOR/CRAB no console", 3, "sandbox")
    refreshBoard()
end

function Gm.startWaves()
    G.mode = "waves"
    G.modeGen = (G.modeGen or 0) + 1
    G.bots.clear(true)
    G.player.heal(true)
    G.infiniteAmmo = false
    Gm.score, Gm.kills, Gm.combo = 0, 0, 0
    Gm.wave = 0
    waveState.phase = "break"
    waveState.t = 2.5
    playMusic("sounds/music_combat.wav")
    refreshBoard()
end

local function beginWave()
    Gm.wave = Gm.wave + 1
    local n = Gm.wave
    waveState.phase = "fight"
    waveState.toSpawn = math.min(30, 3 + n * 2)
    waveState.spawned = 0
    waveState.spawnT = 1
    waveState.maxAlive = math.min(9, 2 + n)
    Gm.message("ONDA " .. n, 2.5, "wave", n)
    A.sound("sounds/wave_start.wav", 1)
    refreshBoard()
end

local function pickType(n)
    local r = math.random()
    if n >= 3 and r < 0.22 then return "crab" end
    if n >= 2 and r < 0.5 then return "gunner" end
    return "grunt"
end

local function updateWaves(dt)
    if G.mode ~= "waves" then return end
    local ws = waveState
    if ws.phase == "break" then
        ws.t = ws.t - dt
        if ws.t <= 0 then beginWave() end
    elseif ws.phase == "fight" then
        ws.spawnT = ws.spawnT - dt
        local alive = G.bots.aliveCount(false)
        if ws.spawned < ws.toSpawn and alive < ws.maxAlive and ws.spawnT <= 0 then
            local n = Gm.wave
            local p = farPortal()
            local f = V.sub(G.rig.head, p)
            local yaw = math.atan(f[1], f[3]) * V.DEG
            local b = G.bots.spawn(pickType(n), p, { yaw = yaw, hpMult = 1 + 0.08 * (n - 1), speedMult = 1 + 0.03 * (n - 1) })
            if b then
                ws.spawned = ws.spawned + 1
                ws.spawnT = math.max(0.6, 1.8 - n * 0.08)
            end
            refreshBoard()
        end
        if ws.spawned >= ws.toSpawn and alive == 0 then
            ws.phase = "break"
            ws.t = 6
            local bonus = Gm.wave * 200
            Gm.addScore(bonus, "bonus da onda")
            G.player.heal(false)
            Gm.message("ONDA COMPLETA!", 3, "clear")
            A.sound("sounds/wave_clear.wav", 1)
        end
    elseif ws.phase == "over" then
        ws.t = ws.t - dt
        if ws.t <= 0 then Gm.toHub() end
    end
end

---------------------------------------------------------------------------
-- Pontuacao / eventos
---------------------------------------------------------------------------
function Gm.addScore(n, why)
    Gm.score = Gm.score + math.floor(n)
    if G.mode == "waves" and Gm.score > Gm.best then
        if not Gm.recordShown and Gm.best > 0 then
            Gm.recordShown = true
            Gm.message("NOVO RECORDE!", 2, "record")
            A.sound("sounds/record.wav", 1)
        end
        Gm.best = Gm.score
        A.setNum("best", Gm.best)
        A.save()
    end
    refreshBoard()
end

function Gm.onKill(bot, zone)
    Gm.kills = Gm.kills + 1
    if G.mode == "hub" then return end
    Gm.combo = Gm.combo + 1
    Gm.comboT = 3
    local pts = bot.T.score * (1 + (Gm.combo - 1) * 0.15)
    if zone == "head" then pts = pts + 50 end
    Gm.addScore(pts, "abate")
    G.stats.kills = G.stats.kills + 1
end

function Gm.onHeadshot()
    G.stats.headshots = G.stats.headshots + 1
end

function Gm.onPlayerHurt(amount) end

function Gm.onPlayerDeath()
    G.items.releaseAll()
    if G.mode == "waves" then
        waveState.phase = "over"
        waveState.t = 4.5
        Gm.message("VOCE MORREU - FIM DE JOGO", 4.5, "gameover", Gm.wave)
        for _, b in ipairs(G.bots.list) do b.passive = true end
    else
        Gm.message("VOCE MORREU", 3, "dead")
        EMRAPI.Timer:Delay(2.5, function() G.player.heal(true) end)
    end
end

---------------------------------------------------------------------------
-- Painel de UI (configuracoes) — usa o EMRAPI.UI da plataforma
---------------------------------------------------------------------------
local function uiTry(fn)
    local ok, err = pcall(fn)
    if not ok then A.warnOnce("ui", "UI: " .. tostring(err)) end
    return ok
end

local function makeUI()
    uiTry(function()
        local U = EMRAPI.UI
        local panel = U:CreatePanel(0.9, 0.95)
        ui.panel = panel
        U:SetColor(panel, 0.06, 0.06, 0.08, 0.94)
        local title = U:CreateText(panel, "BONELAB REMAKE  |  LAB")
        U:SetPosition(title, 0, 205, 0); U:SetSize(title, 420, 40)
        ui.status = U:CreateText(panel, "Pegue uma arma na mesa. Aperte os botoes do console com o dedo.")
        U:SetPosition(ui.status, 0, 155, 0); U:SetSize(ui.status, 420, 70)
        ui.pad = U:CreateText(panel, "Joy-Con: procurando...")
        U:SetPosition(ui.pad, 0, 105, 0); U:SetSize(ui.pad, 420, 40)

        local function btn(text, x, y, cb)
            local b = U:CreateButton(panel, text, cb)
            U:SetPosition(b, x, y, 0); U:SetSize(b, 200, 44)
            return b
        end
        btn("Modo ONDAS", -105, 55, function() Gm.startWaves() end)
        btn("SANDBOX", 105, 55, function() Gm.startSandbox() end)
        btn("Calibrar Joy-Con", -105, 5, function()
            if G.controls.startCalibration() then Gm.message("CALIBRANDO JOY-CON", 3, "calib") end
        end)
        btn("Recentralizar", 105, 5, function() G.rig.recenter(G.level.playerSpawn) end)

        local function toggle(text, key, x, y, apply)
            local t = U:CreateToggle(panel, text, function(state)
                G.settings[key] = state
                A.setBool(key, state); A.save()
                if apply then apply(state) end
            end)
            U:SetPosition(t, x, y, 0); U:SetSize(t, 200, 36)
            return t
        end
        toggle("Mira assistida", "aimAssist", -105, -45, function(s) G.aimAssist = s end)
        toggle("Andar com gesto", "gestureWalk", 105, -45, function(s) G.controls.gestureWalk = s end)
        toggle("Ver o quarto (MR)", "passthrough", -105, -85, function(s)
            pcall(function() EMRAPI.Camera:SetBackground(s and "show" or "hide") end)
        end)
        toggle("Virar suave", "smoothTurn", 105, -85)

        local function slider(text, lo, hi, x, y, cb)
            local l = U:CreateText(panel, text)
            U:SetPosition(l, x, y + 22, 0); U:SetSize(l, 200, 28)
            local s = U:CreateSlider(panel, lo, hi, cb)
            U:SetPosition(s, x, y, 0); U:SetSize(s, 190, 26)
            return s
        end
        slider("Altura (m)", 1.2, 2.0, -105, -140, function(v)
            G.settings.height = v
            G.rig.setHeight(v)
            A.setNum("height", v); A.save()
        end)
        slider("Velocidade", 1, 4, 105, -140, function(v)
            G.settings.moveSpeed = v
            A.setNum("moveSpeed", v); A.save()
        end)
        slider("Musica", 0, 1, -105, -195, function(v)
            Gm.setMusicVolume(v)
            A.setNum("musicVol", v); A.save()
        end)
        btn("Fechar menu", 105, -195, function() Gm.toggleMenu(false) end)
    end)
    G.controls.onCalibText = function(txt)
        if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, txt) end) end
    end
end

function Gm.toggleMenu(state)
    if not ui.panel then return end
    if state == nil then state = not ui.visible end
    ui.visible = state
    pcall(function() EMRAPI.UI:SetActive(ui.panel, state) end)
end

local padText = ""
local function updatePadText()
    if not ui.pad then return end
    local C = G.controls
    local t
    if C.calibrating then
        t = "Joy-Con: calibrando..."
    elseif C.padConnected then
        t = "Joy-Con conectado: " .. C.padNames
    else
        t = "Sem Joy-Con: usando gestos das maos"
    end
    if t ~= padText then
        padText = t
        pcall(function() EMRAPI.UI:SetText(ui.pad, t) end)
    end
end

---------------------------------------------------------------------------
function Gm.init(ctx)
    G = ctx
    Gm.best = A.getNum("best", 0)
    makeMessageBoard()
    makeScoreboard()
    makeConsole()
    makeUI()
    ui.visible = true
    refreshBoard()
end

local padT = 0
function Gm.update(dt)
    updateConsole(dt)
    updateWaves(dt)
    updateMessage(dt)
    Gm.comboT = Gm.comboT - dt
    if Gm.comboT <= 0 then Gm.combo = 0 end
    Gm.shake = math.max(0, Gm.shake - dt * 2)
    padT = padT - dt
    if padT <= 0 then padT = 0.5; updatePadText(); refreshBoard() end
    if G.controls.menuDown then Gm.toggleMenu() end
end

function Gm.shutdown()
    playMusic(nil)
end

return Gm
