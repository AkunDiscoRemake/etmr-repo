-- game.lua — estado do jogo: Laboratorio (hub), modo ONDAS (arena), SANDBOX,
-- console de botoes 3D (aperte com o dedo!), placar na parede, mensagens, musica e menu.

local V = require("vec")
local A = require("api")
local Seg = require("segdisplay")
local L10 = require("i18n")

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
-- chave da mensagem -> textura (msg_<nome>_<idioma>.png)
local MSG_TEX = {
    wave = "msg_wave", clear = "msg_clear", dead = "msg_dead", crab = "msg_crab", record = "msg_record",
    welcome = "msg_welcome", sandbox = "msg_sandbox", hub = "msg_hub", calib = "msg_calib",
    gameover = "msg_gameover", padFound = "msg_calib",
}

local function makeMessageBoard()
    msg.root = A.empty("msgBoard", G.rig.world)
    msg.quad = A.prim("quad", { parent = msg.root, scale = { 1.6, 0.4, 1 }, color = { 1, 1, 1 }, mat = { emit = { 0.08, 0.08, 0.08 }, noShadow = true } })
    msg.num = Seg.new({ parent = msg.root, center = { 0, -0.33, 0 }, n = 2, size = 0.2, on = { 1, 0.45, 0.08 } })
    A.setVisible(msg.root, false)
end

-- key: chave de traducao (i18n); number: numero opcional (onda)
function Gm.message(key, dur, number)
    local text = L10.t(key, number)
    A.log(text)
    ui.lastStatus = { key = key, number = number }
    if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, text) end) end
    local tex = MSG_TEX[key]
    if not tex then return end
    A.texture(msg.quad, L10.tex(tex))
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
    local function label(key, x, y, w)
        local q = A.prim("quad", { parent = G.rig.world, pos = { x, y, z }, scale = { w, w * 0.25, 1 }, color = { 1, 1, 1 }, mat = { noShadow = true } })
        L10.bindTex(q, key)
    end
    A.prim("cube", { parent = G.rig.world, pos = { 0, 3.05, z + 0.02 }, scale = { 7.6, 2.5, 0.06 }, color = { 0.05, 0.05, 0.06 }, mat = { metal = 0.6, smooth = 0.7 } })
    A.prim("cube", { parent = G.rig.world, pos = { 0, 4.33, z - 0.01 }, scale = { 7.7, 0.05, 0.05 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.5, 0.5, 0.05 }, noShadow = true } })
    A.prim("cube", { parent = G.rig.world, pos = { 0, 1.77, z - 0.01 }, scale = { 7.7, 0.05, 0.05 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.5, 0.5, 0.05 }, noShadow = true } })
    label("lbl_wave", -2.6, 3.95, 1.6)
    label("lbl_score", 1.2, 3.95, 1.6)
    label("lbl_best", 1.2, 2.75, 1.6)
    label("lbl_enemies", -2.6, 2.75, 1.6)
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
    { id = "waves", tex = "btn_waves", color = { 1, 0.45, 0.08 } },
    { id = "sandbox", tex = "btn_sandbox", color = { 0.2, 0.8, 1 } },
    { id = "hub", tex = "btn_hub", color = { 0.85, 0.85, 0.9 } },
    { id = "calib", tex = "btn_calib", color = { 0.9, 0.2, 0.3 } },
    { id = "grunt", tex = "btn_grunt", color = { 1, 0.45, 0.08 } },
    { id = "gunner", tex = "btn_gunner", color = { 0.2, 0.8, 1 } },
    { id = "crab", tex = "btn_crab", color = { 0.6, 1, 0.2 } },
    { id = "clear", tex = "btn_clear", color = { 0.95, 0.85, 0.2 } },
    { id = "lang", tex = "btn_lang", color = { 0.7, 0.5, 1 } },
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
    local top = A.prim("cube", { parent = G.rig.world, pos = center, scale = { 0.78, 0.04, 0.58 }, color = { 0.16, 0.16, 0.19 }, mat = { metal = 0.7, smooth = 0.7 } })
    L10.bindTex(top, "console")
    A.rotBasis(top, Bc)
    local edge = A.prim("cube", { parent = G.rig.world, pos = V.poseApply(center, Bc, { 0, 0.005, -0.295 }), scale = { 0.8, 0.03, 0.02 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 1.4, 0.45, 0.04 } } })
    A.rotBasis(edge, Bc)
    G.rig.obstacles[#G.rig.obstacles + 1] = { box = { center[1] - 0.32, center[1] + 0.32, center[3] - 0.3, center[3] + 0.3 } }

    for i, b in ipairs(BUTTONS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local lp = { -0.27 + col * 0.18, 0.02, 0.17 - row * 0.16 }
        local cap = A.prim("cylinder", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.035, lp[3] }), scale = { 0.1, 0.018, 0.1 }, color = b.color, mat = { metal = 0.3, smooth = 0.8, emit = { b.color[1] * 0.5, b.color[2] * 0.5, b.color[3] * 0.5 } } })
        A.rotBasis(cap, Bc)
        local ring = A.prim("cylinder", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.022, lp[3] }), scale = { 0.125, 0.01, 0.125 }, color = { 0.08, 0.08, 0.09 }, mat = { metal = 0.8, smooth = 0.6 } })
        A.rotBasis(ring, Bc)
        -- etiqueta deitada no tampo, abaixo do botao
        local lbl = A.prim("quad", { parent = G.rig.world, pos = V.poseApply(center, Bc, { lp[1], 0.0215, lp[3] - 0.075 }), scale = { 0.16, 0.04, 1 }, color = { 1, 1, 1 }, mat = { noShadow = true } })
        L10.bindTex(lbl, b.tex)
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
        if G.controls.startCalibration() then Gm.message("calib", 3) end
    elseif id == "lang" then
        L10.cycle()
        Gm.message("langSet", 2)
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
    Gm.message("hub", 2.5)
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
    Gm.message("sandbox", 3)
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
    Gm.message("wave", 2.5, n)
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
            Gm.message("clear", 3)
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
            Gm.message("record", 2)
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
        Gm.message("gameover", 4.5, Gm.wave)
        for _, b in ipairs(G.bots.list) do b.passive = true end
    else
        Gm.message("dead", 3)
        EMRAPI.Timer:Delay(2.5, function() G.player.heal(true) end)
    end
end

---------------------------------------------------------------------------
-- Painel de UI (configuracoes) — usa o EMRAPI.UI da plataforma
---------------------------------------------------------------------------
local padText = ""
local updatePadText

local function uiTry(fn)
    local ok, err = pcall(fn)
    if not ok then A.warnOnce("ui", "UI: " .. tostring(err)) end
    return ok
end

local function makeUI()
    uiTry(function()
        local U = EMRAPI.UI
        local t = L10.t
        local panel = U:CreatePanel(0.9, 1.05)
        ui.panel = panel
        U:SetColor(panel, 0.06, 0.06, 0.08, 0.94)
        local title = U:CreateText(panel, t("title"))
        U:SetPosition(title, 0, 230, 0); U:SetSize(title, 420, 40)
        local st = ui.lastStatus and t(ui.lastStatus.key, ui.lastStatus.number) or t("intro")
        ui.status = U:CreateText(panel, st)
        U:SetPosition(ui.status, 0, 180, 0); U:SetSize(ui.status, 420, 70)
        ui.pad = U:CreateText(panel, t("padSearch"))
        U:SetPosition(ui.pad, 0, 130, 0); U:SetSize(ui.pad, 420, 40)
        padText = ""

        local function btn(text, x, y, cb)
            local b = U:CreateButton(panel, text, cb)
            U:SetPosition(b, x, y, 0); U:SetSize(b, 200, 44)
            return b
        end
        btn(t("bWaves"), -105, 80, function() Gm.startWaves() end)
        btn(t("bSandbox"), 105, 80, function() Gm.startSandbox() end)
        btn(t("bCalib"), -105, 30, function()
            if G.controls.startCalibration() then Gm.message("calib", 3) end
        end)
        btn(t("bRecenter"), 105, 30, function() G.rig.recenter(G.level.playerSpawn) end)

        local function toggle(text, key, x, y, apply)
            local tg = U:CreateToggle(panel, text, function(state)
                G.settings[key] = state
                A.setBool(key, state); A.save()
                if apply then apply(state) end
            end)
            U:SetPosition(tg, x, y, 0); U:SetSize(tg, 200, 36)
            return tg
        end
        toggle(t("tAim"), "aimAssist", -105, -20, function(v) G.aimAssist = v end)
        toggle(t("tWalk"), "gestureWalk", 105, -20, function(v) G.controls.gestureWalk = v end)
        toggle(t("tMR"), "passthrough", -105, -60, function(v)
            pcall(function() EMRAPI.Camera:SetBackground(v and "show" or "hide") end)
        end)
        toggle(t("tSmooth"), "smoothTurn", 105, -60)
        toggle(t("tSticky"), "stickyGrab", -105, -100, function(v) G.controls.stickyGrab = v end)

        local function slider(text, lo, hi, x, y, cb)
            local l = U:CreateText(panel, text)
            U:SetPosition(l, x, y + 22, 0); U:SetSize(l, 200, 28)
            local sl = U:CreateSlider(panel, lo, hi, cb)
            U:SetPosition(sl, x, y, 0); U:SetSize(sl, 190, 26)
            return sl
        end
        slider(t("sHeight"), 1.2, 2.0, -105, -160, function(v)
            G.settings.height = v
            G.rig.setHeight(v)
            A.setNum("height", v); A.save()
        end)
        slider(t("sSpeed"), 1, 4, 105, -160, function(v)
            G.settings.moveSpeed = v
            A.setNum("moveSpeed", v); A.save()
        end)
        slider(t("sMusic"), 0, 1, -105, -215, function(v)
            Gm.setMusicVolume(v)
            A.setNum("musicVol", v); A.save()
        end)
        btn(t("bLang"), 105, -110, function()
            L10.cycle()
            Gm.message("langSet", 2)
        end)
        btn(t("bClose"), 105, -215, function() Gm.toggleMenu(false) end)
    end)
    G.controls.onCalibText = function(txt)
        if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, txt) end) end
    end
end

-- troca de idioma: o painel e recriado com os textos novos
local function rebuildUI()
    local wasVisible = ui.visible
    if ui.panel then pcall(function() EMRAPI.UI:Destroy(ui.panel) end) end
    ui.panel, ui.status, ui.pad = nil, nil, nil
    makeUI()
    ui.visible = true
    if wasVisible == false then Gm.toggleMenu(false) end
end

function Gm.toggleMenu(state)
    if not ui.panel then return end
    if state == nil then state = not ui.visible end
    ui.visible = state
    pcall(function() EMRAPI.UI:SetActive(ui.panel, state) end)
end

updatePadText = function()
    if not ui.pad then return end
    local C = G.controls
    local t
    if C.calibrating then
        t = L10.t("padCal")
    elseif C.padConnected then
        t = L10.t("padOn", C.padNames)
    else
        t = L10.t("padOff")
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
    L10.onChange(function() rebuildUI() end)
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
