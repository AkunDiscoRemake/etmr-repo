-- game.lua — fluxo do SUPERHOT Remake:
--   SAGUAO (pegue o cubo vermelho de uma fase) -> FASE -> "SUPER... HOT..." -> PROXIMA / SAGUAO
--   Morreu? Recomeca na hora. Modo INFINITO com ondas e recorde. Progresso salvo.

local V = require("vec")
local A = require("api")
local Seg = require("segdisplay")
local L10 = require("i18n")
local LV = require("levels")

local Gm = {}
local G

Gm.unlocked = 1
Gm.best = {}          -- melhor tempo por fase
Gm.endlessBest = 0
Gm.current = 0
Gm.kills = 0

local ui = {}
local msg = {}
local letters = {}
local choices = {}     -- cubos selecionaveis (saguao / fim de fase)
local amb = { id = nil, t = 0 }
local spawnQ = {}
local levelClock = 0
local endless = nil
local winSeq = nil
local deathT = nil

---------------------------------------------------------------------------
-- Som ambiente (o tom acompanha o tempo do jogo)
---------------------------------------------------------------------------
local function startAmbience()
    if amb.id then return end
    local ok, id = pcall(function() return EMRAPI.Audio:PlayLoop("sounds/ambience.wav") end)
    if ok then
        amb.id = id
        pcall(function() EMRAPI.Audio:SetVolume(id, G.settings.musicVol) end)
    end
end

local function updateAmbience(dt)
    amb.t = amb.t - dt
    if amb.t > 0 or not amb.id then return end
    amb.t = 0.1
    local p = 0.55 + 0.45 * G.time.ts
    pcall(function() EMRAPI.Audio:SetPitch(amb.id, p) end)
end

function Gm.setVolume(v)
    G.settings.musicVol = v
    if amb.id then pcall(function() EMRAPI.Audio:SetVolume(amb.id, v) end) end
end

---------------------------------------------------------------------------
-- Placa de mensagem + texto no painel
---------------------------------------------------------------------------
local MSG_TEX = {
    level = "msg_level", dead = "msg_dead", endless = "msg_endless", endlessWave = "msg_wave",
    record = "msg_record", complete = "msg_complete", locked = "msg_locked", lobby = "msg_lobby",
    welcome = "msg_welcome", calib = "msg_calib", padFound = "msg_calib",
}

local function makeMessageBoard()
    msg.root = A.empty("msgBoard", G.rig.world)
    msg.quad = A.prim("quad", { parent = msg.root, scale = { 1.6, 0.4, 1 }, color = { 1, 1, 1 }, mat = { emit = { 0.1, 0.1, 0.1 }, noShadow = true } })
    msg.num = Seg.new({ parent = msg.root, center = { 0, -0.34, 0 }, n = 2, size = 0.2, on = { 1, 0.1, 0.06 } })
    A.setVisible(msg.root, false)
end

function Gm.message(key, dur, number, extra)
    local text = L10.t(key, number)
    if extra then text = text .. "\n" .. extra end
    A.log(text)
    ui.lastStatus = { key = key, number = number, extra = extra }
    if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, text) end) end
    local tex = MSG_TEX[key]
    if not tex then return end
    A.texture(msg.quad, L10.tex(tex))
    local f = G.rig.flatForward()
    local p = V.add(G.rig.head, V.scale(f, 2.2))
    p[2] = G.rig.head[2] + 0.15
    A.pos(msg.root, p)
    A.rotBasis(msg.root, V.basis(f, { 0, 1, 0 }))
    A.setVisible(msg.root, true)
    A.setVisible(msg.num.root, number ~= nil)
    if number then msg.num:set(number) end
    A.scale(msg.root, 0.01)
    pcall(function() EMRAPI.Tween:ScaleTo(msg.root, 1, 1, 1, 0.25) end)
    msg.t, msg.dur, msg.active = 0, dur or 2.5, true
end

local function updateMessage(dt)
    if not msg.active then return end
    msg.t = msg.t + dt
    if msg.t > msg.dur then msg.active = false; A.setVisible(msg.root, false) end
end

---------------------------------------------------------------------------
-- Letras 3D "SUPER" e "HOT" (feitas de cubos)
---------------------------------------------------------------------------
local FONT = {
    S = { "01111", "10000", "01110", "00001", "11110" },
    U = { "10001", "10001", "10001", "10001", "01110" },
    P = { "11110", "10001", "11110", "10000", "10000" },
    E = { "11111", "10000", "11110", "10000", "11111" },
    R = { "11110", "10001", "11110", "10010", "10001" },
    H = { "10001", "10001", "11111", "10001", "10001" },
    O = { "01110", "10001", "10001", "10001", "01110" },
    T = { "11111", "00100", "00100", "00100", "00100" },
}

local function makeWord(word)
    local root = A.empty("word_" .. word, G.rig.world)
    local cell = 0.13
    local totalW = (#word * 6 - 1) * cell
    for i = 1, #word do
        local g = FONT[word:sub(i, i)]
        for row = 1, 5 do
            for col = 1, 5 do
                if g[row]:sub(col, col) == "1" then
                    local x = -totalW / 2 + ((i - 1) * 6 + (col - 1)) * cell + cell / 2
                    local y = (3 - row) * cell
                    A.prim("cube", { parent = root, pos = { x, y, 0 }, scale = { cell * 0.94, cell * 0.94, cell * 0.94 },
                        color = { 0.97, 0.97, 1 }, mat = { emit = { 0.6, 0.6, 0.65 }, smooth = 0.9, noShadow = true } })
                end
            end
        end
    end
    A.setVisible(root, false)
    return root
end

local function showWord(which)
    local f = G.rig.flatForward()
    local p = V.add(G.rig.head, V.scale(f, 3.2))
    p[2] = G.rig.head[2] + 0.1
    for k, root in pairs(letters) do
        local on = k == which
        A.setVisible(root, on)
        if on then
            A.pos(root, p)
            A.rotBasis(root, V.basis(f, { 0, 1, 0 }))
            A.scale(root, 1.15)
            pcall(function() EMRAPI.Tween:ScaleTo(root, 1, 1, 1, 0.3) end)
        end
    end
end

---------------------------------------------------------------------------
-- Cubos selecionaveis (fases no saguao, PROXIMA/SAGUAO no fim)
---------------------------------------------------------------------------
local function clearChoices()
    for _, c in ipairs(choices) do A.destroy(c.root) end
    choices = {}
end

local function addChoice(pos, facing, color, emit, labelTex, number, onPick, size)
    size = size or 0.2
    local c = { pos = pos, onPick = onPick, size = size, spin = math.random() * 360 }
    c.root = A.empty("choice", G.level.root or G.rig.world, pos)
    c.cube = A.prim("cube", { parent = c.root, scale = { size, size, size }, color = color, mat = { emit = emit, smooth = 0.95 } })
    local Bf = V.basis(facing, { 0, 1, 0 })
    if labelTex then
        local q = A.prim("quad", { parent = G.level.root or G.rig.world, pos = V.add(pos, { 0, size * 0.5 + 0.17, 0 }), scale = { 0.44, 0.11, 1 },
            color = { 1, 1, 1 }, mat = { noShadow = true } })
        L10.bindTex(q, labelTex)
        A.rotBasis(q, Bf)
    end
    if number then
        local d = Seg.new({ parent = G.level.root or G.rig.world, center = V.add(pos, { 0, size * 0.5 + 0.14, 0 }), basis = Bf, n = 2, size = 0.1,
            on = { 0.1, 0.1, 0.12 }, off = { 0.86, 0.86, 0.88 }, backColor = { 0.93, 0.93, 0.95 } })
        d:set(number)
    end
    choices[#choices + 1] = c
    return c
end

local function updateChoices(dt)
    for _, c in ipairs(choices) do
        c.spin = c.spin + dt * 40
        local hover = false
        for _, side in ipairs({ "left", "right" }) do
            local h = G.controls.hands[side]
            if h.tracked and not h.busy and V.dist(h.palm, c.pos) < c.size * 0.5 + 0.13 then
                hover = true
                if h.grip then
                    if not c.picked then
                        c.picked = true
                        G.fx.shatter({ c.pos }, { 0, 0.4, 0 }, 1.5, 18, "shard")
                        G.sound3D("sounds/shatter.wav", c.pos, 0.9)
                        local fn = c.onPick
                        EMRAPI.Timer:Delay(0.35, function() fn() end)
                    end
                end
            end
        end
        local s = hover and 1.25 or 1
        A.rot(c.cube, 25, c.spin, 15)
        A.scale(c.cube, c.size * s, c.size * s, c.size * s)
    end
end

---------------------------------------------------------------------------
-- Itens a partir dos dados
---------------------------------------------------------------------------
local REST = { pistol = 0.016, shotgun = 0.024, uzi = 0.018, katana = 0.02, bottle = 0.212, ashtray = 0.04, phone = 0.006 }

local function spawnItem(type, x, y, z, yaw)
    local a = (yaw or 0) * V.RAD
    local fdir = { math.sin(a), 0, math.cos(a) }
    local up = { 0, 1, 0 }
    local B
    if type == "bottle" or type == "ashtray" then
        B = V.basisFromEuler(0, yaw or 0, 0)
    elseif type == "phone" then
        B = V.basis(up, fdir)
    elseif type == "katana" then
        B = { r = up, u = fdir, f = V.cross(up, fdir) }
    else
        B = { r = up, u = V.cross(fdir, up), f = fdir }
    end
    return G.items.spawn(type, { x, y + (REST[type] or 0.02), z }, B, { rest = true })
end

---------------------------------------------------------------------------
-- Montagem de fases
---------------------------------------------------------------------------
local function resetWorld()
    clearChoices()
    G.enemies.clear()
    G.items.clear()
    G.bullets.clear()
    G.fx.clear()
    G.player.revive()
    G.time.reset()
    winSeq = nil
    G.levelTime = 0
    spawnQ = {}
    deathT = nil
    for _, r in pairs(letters) do A.setVisible(r, false) end
end

local LOBBY = {
    name = "lobby", size = { 4.5, 4.5 }, player = { 0, -2.6 },
    boxes = {}, doors = {}, items = {},
}

function Gm.toLobby()
    resetWorld()
    G.mode = "lobby"
    endless = nil
    G.level.build(LOBBY, G.rig.world, G.rig)
    G.rig.recenter({ LOBBY.player[1], 0, LOBBY.player[2] })
    local P = LOBBY.player
    local center = { P[1], 0, P[2] }
    -- logo e dica na parede
    local z = LOBBY.size[2] - 0.03
    A.prim("quad", { parent = G.level.root, pos = { 0, 2.35, z }, scale = { 4.2, 1.05, 1 }, color = { 1, 1, 1 }, tex = "images/logo.png", mat = { noShadow = true } })
    local hint = A.prim("quad", { parent = G.level.root, pos = { 0, 1.55, z }, scale = { 3.2, 0.4, 1 }, color = { 1, 1, 1 }, mat = { noShadow = true } })
    L10.bindTex(hint, "lbl_hint")
    -- pedestais das fases em arco
    for i = 1, LV.count do
        local ang = (-72 + (i - 1) * 16) * V.RAD
        local pos = { center[1] + math.sin(ang) * 1.75, 0, center[3] + math.cos(ang) * 1.75 }
        A.prim("cylinder", { parent = G.level.root, pos = { pos[1], 0.5, pos[3] }, scale = { 0.26, 0.5, 0.26 }, color = { 0.96, 0.96, 0.98 }, mat = { smooth = 0.6, emit = { 0.1, 0.1, 0.11 } } })
        local cp = { pos[1], 1.15, pos[3] }
        local facing = V.norm(V.sub({ pos[1], 0, pos[3] }, center))
        local unlocked = i <= Gm.unlocked
        local col = unlocked and { 1, 0.08, 0.05 } or { 0.55, 0.55, 0.58 }
        local emit = unlocked and { 1.6, 0.06, 0.03 } or { 0.05, 0.05, 0.05 }
        local lvl = i
        addChoice(cp, facing, col, emit, nil, i, function()
            if lvl <= Gm.unlocked then Gm.startLevel(lvl) else
                Gm.message("locked", 2)
                Gm.toLobby()
            end
        end, 0.16)
    end
    -- modo infinito: cubo maior ao fundo
    local ep = { center[1], 1.3, center[3] + 3.3 }
    A.prim("cylinder", { parent = G.level.root, pos = { ep[1], 0.55, ep[3] }, scale = { 0.4, 0.55, 0.4 }, color = { 0.96, 0.96, 0.98 }, mat = { smooth = 0.6, emit = { 0.1, 0.1, 0.11 } } })
    addChoice(ep, { 0, 0, 1 }, { 1, 0.08, 0.05 }, { 1.8, 0.06, 0.03 }, "lbl_endless", nil, function() Gm.startEndless() end, 0.3)
    local bestDisp = Seg.new({ parent = G.level.root, center = { ep[1], 1.95, ep[3] }, basis = V.identity(), n = 3, size = 0.12, on = { 1, 0.1, 0.05 } })
    bestDisp:set(Gm.endlessBest)
    Gm.message("lobby", 2.5)
end

local function scheduleSpawns(list)
    spawnQ = {}
    for _, s in ipairs(list) do spawnQ[#spawnQ + 1] = { t = s.t, x = s.x, z = s.z, w = s.w } end
    table.sort(spawnQ, function(a, b) return a.t < b.t end)
end

function Gm.startLevel(n)
    resetWorld()
    local def = LV[n]
    if not def then Gm.toLobby(); return end
    G.mode = "level"
    Gm.current = n
    G.level.build(def, G.rig.world, G.rig)
    G.rig.recenter({ def.player[1], 0, def.player[2] })
    for _, it in ipairs(def.items) do spawnItem(it[1], it[2], it[3], it[4], it[5]) end
    scheduleSpawns(def.spawns)
    levelClock = 0
    G.stats.levelKills = 0
    Gm.message("level", 2.2, n, L10.t(def.name))
    G.sound("sounds/level_start.wav", 0.9)
end

---------------------------------------------------------------------------
-- Modo infinito
---------------------------------------------------------------------------
local WEAPON_POOL = { "none", "none", "pistol", "pistol", "pistol", "katana", "uzi", "shotgun" }

local function endlessWave()
    endless.wave = endless.wave + 1
    local k = endless.wave
    local list = {}
    local t = 0.4
    for i = 1, math.min(14, 2 + k) do
        local d = LV.endlessDoors[math.random(1, #LV.endlessDoors)]
        list[#list + 1] = { t = t, x = d[1], z = d[2], w = WEAPON_POOL[math.random(1, #WEAPON_POOL)] }
        t = t + math.max(0.5, 1.6 - k * 0.08)
    end
    scheduleSpawns(list)
    endless.speed = 1 + 0.04 * k
    -- reabastece: uma arma nova nos pedestais se a mao estiver vazia
    local types = { "pistol", "uzi", "shotgun", "katana" }
    spawnItem(types[math.random(1, #types)], (math.random() < 0.5) and -1 or 1, 0.9, -4, 80)
    Gm.message("endlessWave", 2, k)
end

function Gm.startEndless()
    resetWorld()
    G.mode = "level"
    Gm.current = 0
    local def = LV[10]
    G.level.build(def, G.rig.world, G.rig)
    G.rig.recenter({ def.player[1], 0, def.player[2] })
    for _, it in ipairs(def.items) do spawnItem(it[1], it[2], it[3], it[4], it[5]) end
    endless = { wave = 0, kills = 0 }
    endlessWave()
    Gm.message("endless", 2.5)
end

---------------------------------------------------------------------------
-- Vitoria: SUPER... HOT...
---------------------------------------------------------------------------
local function finishWin()
    local n = Gm.current
    local t = levelClock
    if not Gm.best[n] or t < Gm.best[n] then
        Gm.best[n] = t
        A.setNum("best_" .. n, t)
    end
    if n >= Gm.unlocked then
        Gm.unlocked = math.min(LV.count, n + 1)
        A.setNum("unlocked", Gm.unlocked)
        if n == LV.count then A.setBool("beaten", true) end
    end
    A.save()
    for _, r in pairs(letters) do A.setVisible(r, false) end
    G.time.force(nil)
    G.mode = "cleared"
    if n == LV.count then Gm.message("complete", 4) end
    if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, L10.t("cleared", string.format("%.1f", t))) end) end
    -- PROXIMA e SAGUAO
    local f = G.rig.flatForward()
    local r = { f[3], 0, -f[1] }
    local base = V.add(G.rig.head, V.scale(f, 0.75))
    base[2] = 1.15
    if n < LV.count then
        addChoice(V.add(base, V.scale(r, 0.3)), f, { 1, 0.08, 0.05 }, { 1.6, 0.06, 0.03 }, "btn_next", nil, function() Gm.startLevel(n + 1) end, 0.16)
    end
    addChoice(V.add(base, V.scale(r, n < LV.count and -0.3 or 0)), f, { 0.95, 0.95, 0.97 }, { 0.3, 0.3, 0.32 }, "btn_lobby", nil, function() Gm.toLobby() end, 0.16)
end

local function startWin()
    G.mode = "win"
    G.time.force(0.03)
    winSeq = { t = 0, step = 0 }
    G.items.releaseAll()
end

local function updateWin(dt)
    if not winSeq then return end
    winSeq.t = winSeq.t + dt
    local step = math.floor(winSeq.t / 0.8)
    if step ~= winSeq.step and step <= 6 then
        winSeq.step = step
        if step < 6 then
            local word = (step % 2 == 0) and "SUPER" or "HOT"
            showWord(word)
            G.sound(word == "SUPER" and "sounds/super.wav" or "sounds/hot.wav", 1)
        else
            winSeq = nil
            finishWin()
        end
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
function Gm.onKill(en, cause)
    Gm.kills = Gm.kills + 1
    G.stats.kills = G.stats.kills + 1
    if endless then
        endless.kills = endless.kills + 1
        if endless.kills > Gm.endlessBest then
            if Gm.endlessBest > 0 and not endless.recordShown then
                endless.recordShown = true
                Gm.message("record", 1.5)
            end
            Gm.endlessBest = endless.kills
            A.setNum("endlessBest", Gm.endlessBest)
            A.save()
        end
    end
end

function Gm.onPlayerDeath()
    deathT = 0
    Gm.message("dead", 1.8)
end

local hintT = -99
function Gm.hintThrow()
    -- arma vazia: dica de arremesso (no maximo a cada 6 s)
    if G.realTime - hintT > 6 then
        hintT = G.realTime
        A.log("empty -> throw it")
    end
end

local function updateLevel(dt, gdt)
    levelClock = levelClock + dt
    if G.player.dead then return end
    -- fila de spawns no tempo do jogo
    local lt = (G.levelTime or 0) + gdt
    G.levelTime = lt
    local alive = G.enemies.alive()
    if #spawnQ > 0 and alive == 0 and spawnQ[1].t > lt + 0.3 then
        -- ninguem vivo: adianta o proximo
        local skip = spawnQ[1].t - lt - 0.3
        for _, s in ipairs(spawnQ) do s.t = s.t - skip end
    end
    while #spawnQ > 0 and spawnQ[1].t <= lt do
        local s = table.remove(spawnQ, 1)
        local head = G.rig.head
        local yaw = math.atan(head[1] - s.x, head[3] - s.z) * V.DEG
        G.enemies.spawn({ s.x, 0, s.z }, s.w, { yaw = yaw, speed = endless and endless.speed or 1 })
    end
    if #spawnQ == 0 and G.enemies.alive() == 0 then
        if endless then endlessWave() else startWin() end
    end
end

---------------------------------------------------------------------------
-- Painel de UI
---------------------------------------------------------------------------
local padText = ""
local updatePadText

local function uiTry(fn)
    local ok, err = pcall(fn)
    if not ok then A.warnOnce("ui", "UI: " .. tostring(err)) end
end

local function makeUI()
    uiTry(function()
        local U = EMRAPI.UI
        local t = L10.t
        local panel = U:CreatePanel(0.9, 1.05)
        ui.panel = panel
        U:SetColor(panel, 0.95, 0.95, 0.97, 0.96)
        local title = U:CreateText(panel, t("title"))
        U:SetPosition(title, 0, 230, 0); U:SetSize(title, 420, 40)
        local ls = ui.lastStatus
        ui.status = U:CreateText(panel, ls and t(ls.key, ls.number) or t("intro"))
        U:SetPosition(ui.status, 0, 180, 0); U:SetSize(ui.status, 420, 70)
        ui.pad = U:CreateText(panel, t("padSearch"))
        U:SetPosition(ui.pad, 0, 130, 0); U:SetSize(ui.pad, 420, 40)
        padText = ""
        local function btn(text, x, y, cb)
            local b = U:CreateButton(panel, text, cb)
            U:SetPosition(b, x, y, 0); U:SetSize(b, 200, 44)
        end
        btn(t("bLobby"), -105, 80, function() Gm.toLobby() end)
        btn(t("bRestart"), 105, 80, function()
            if Gm.current > 0 then Gm.startLevel(Gm.current) elseif endless then Gm.startEndless() end
        end)
        btn(t("bEndless"), -105, 30, function() Gm.startEndless() end)
        btn(t("bCalib"), 105, 30, function()
            if G.controls.startCalibration() then Gm.message("calib", 3) end
        end)
        local function toggle(text, key, x, y, apply)
            local tg = U:CreateToggle(panel, text, function(state)
                G.settings[key] = state
                A.setBool(key, state); A.save()
                if apply then apply(state) end
            end)
            U:SetPosition(tg, x, y, 0); U:SetSize(tg, 200, 36)
        end
        toggle(t("tAim"), "aimAssist", -105, -20, function(v) G.aimAssist = v end)
        toggle(t("tWalk"), "gestureWalk", 105, -20, function(v) G.controls.gestureWalk = v end)
        toggle(t("tMR"), "passthrough", -105, -60, function(v)
            pcall(function() EMRAPI.Camera:SetBackground(v and "show" or "hide") end)
        end)
        toggle(t("tSmooth"), "smoothTurn", 105, -60)
        toggle(t("tSticky"), "stickyGrab", -105, -100, function(v) G.controls.stickyGrab = v end)
        btn(t("bLang"), 105, -110, function()
            L10.cycle()
            Gm.message("langSet", 2)
        end)
        local function slider(text, lo, hi, x, y, cb)
            local l = U:CreateText(panel, text)
            U:SetPosition(l, x, y + 22, 0); U:SetSize(l, 200, 28)
            local sl = U:CreateSlider(panel, lo, hi, cb)
            U:SetPosition(sl, x, y, 0); U:SetSize(sl, 190, 26)
        end
        slider(t("sHeight"), 1.2, 2.0, -105, -160, function(v)
            G.settings.height = v; G.rig.setHeight(v); A.setNum("height", v); A.save()
        end)
        slider(t("sSpeed"), 1, 4, 105, -160, function(v)
            G.settings.moveSpeed = v; A.setNum("moveSpeed", v); A.save()
        end)
        slider(t("sMusic"), 0, 1, -105, -215, function(v)
            Gm.setVolume(v); A.setNum("musicVol", v); A.save()
        end)
        btn(t("bRecenter"), 105, -165, function() G.rig.recenter() end)
        btn(t("bClose"), 105, -215, function() Gm.toggleMenu(false) end)
    end)
    G.controls.onCalibText = function(txt)
        if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, txt) end) end
    end
end

local function rebuildUI()
    local was = ui.visible
    if ui.panel then pcall(function() EMRAPI.UI:Destroy(ui.panel) end) end
    ui.panel, ui.status, ui.pad = nil, nil, nil
    makeUI()
    ui.visible = true
    if was == false then Gm.toggleMenu(false) end
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
    if C.calibrating then t = L10.t("padCal")
    elseif C.padConnected then t = L10.t("padOn", C.padNames)
    else t = L10.t("padOff") end
    if t ~= padText then
        padText = t
        pcall(function() EMRAPI.UI:SetText(ui.pad, t) end)
    end
end

---------------------------------------------------------------------------
function Gm.init(ctx)
    G = ctx
    Gm.unlocked = math.floor(A.getNum("unlocked", 1))
    Gm.endlessBest = math.floor(A.getNum("endlessBest", 0))
    for i = 1, LV.count do
        local b = A.getNum("best_" .. i, -1)
        if b > 0 then Gm.best[i] = b end
    end
    makeMessageBoard()
    letters.SUPER = makeWord("SUPER")
    letters.HOT = makeWord("HOT")
    makeUI()
    ui.visible = true
    L10.onChange(function() rebuildUI() end)
    startAmbience()
end

local padT = 0
function Gm.update(dt, gdt)
    updateChoices(dt)
    updateMessage(dt)
    updateAmbience(dt)
    if G.mode == "level" then updateLevel(dt, gdt) end
    if G.mode == "win" then updateWin(dt) end
    if deathT then
        deathT = deathT + dt
        if deathT > 1.7 then
            deathT = nil
            if endless then Gm.toLobby()
            elseif Gm.current > 0 then Gm.startLevel(Gm.current)
            else Gm.toLobby() end
        end
    end
    padT = padT - dt
    if padT <= 0 then padT = 0.5; updatePadText() end
    if G.controls.menuDown then Gm.toggleMenu() end
end

function Gm.shutdown()
    if amb.id then pcall(function() EMRAPI.Audio:Stop(amb.id) end) end
end

return Gm
