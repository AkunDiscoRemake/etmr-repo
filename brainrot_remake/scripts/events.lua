-- events.lua — dia/noite e eventos:
--   * NOITE = HALLOWEEN: abobora nos postes, morcegos, ceu roxo. Sorte x2 e mutacao Halloween.
--   * CANDY (aleatorio): chuva de doces (pegue = dinheiro + corrida doce), dinheiro x2, mutacao Candy.
--   * LAVA (raro): meteoros caem (fuja do circulo vermelho!), sorte x3, mutacao Lava.
-- Quem decide e o mestre da sala (ou o solo); os outros recebem o estado.

local V = require("vec")
local A = require("api")
local Lt = require("layout")
local K = require("catalog")

local Ev = {}

Ev.DAY = 240
Ev.NIGHT = 150
Ev.clock = 25           -- comeca de dia
Ev.current = nil        -- nil | "candy" | "lava"
Ev.eventT = 0
Ev.nextCandy = 85       -- o primeiro doce vem cedo (fisgar o jogador!)
Ev.nextLava = 660
Ev.personal = {}        -- boosts pessoais { kind = tempo }

local G
local deco = {}
local candies = {}
local meteors = {}
local bats = {}
local music = { id = nil, kind = nil }

function Ev.init(ctx)
    G = ctx
    Ev.root = A.empty("events", G.rig.world)
    -- aboboras (so aparecem de noite)
    deco.pumpkins = A.empty("pumpkins", Ev.root)
    local spots = {}
    for z = Lt.CARPET.z0 + 6, Lt.CARPET.z1 - 2, 8 do
        spots[#spots + 1] = { -3.1, z }
        spots[#spots + 1] = { 3.1, z }
    end
    for i = 1, 8 do
        local p = Lt.frontPos(i)
        spots[#spots + 1] = { p[1] + 2.6, p[3] + 1.6 }
    end
    for _, s in ipairs(spots) do
        local root = A.empty("pk", deco.pumpkins, { s[1], 0, s[2] })
        A.prim("sphere", { parent = root, pos = { 0, 0.22, 0 }, scale = { 0.5, 0.42, 0.5 }, color = { 1, 0.5, 0.05 }, mat = { emit = { 0.35, 0.12, 0 } } })
        A.prim("cylinder", { parent = root, pos = { 0, 0.47, 0 }, scale = { 0.06, 0.05, 0.06 }, color = { 0.25, 0.45, 0.1 } })
        for _, sx in ipairs({ -1, 1 }) do
            local e = A.prim("cube", { parent = root, pos = { sx * 0.09, 0.27, 0.24 }, scale = { 0.08, 0.08, 0.02 }, rot = { 0, 0, 45 }, color = { 1, 0.9, 0.3 } })
            A.material(e, { emit = { 3, 2.2, 0.4 }, noShadow = true })
        end
        local m = A.prim("cube", { parent = root, pos = { 0, 0.15, 0.24 }, scale = { 0.22, 0.05, 0.02 }, color = { 1, 0.9, 0.3 } })
        A.material(m, { emit = { 3, 2.2, 0.4 }, noShadow = true })
        A.rot(root, 0, s[1] < 0 and 90 or -90, 0)
    end
    A.setVisible(deco.pumpkins, false)
    -- morcegos
    deco.bats = A.empty("bats", Ev.root)
    for i = 1, 10 do
        local b = A.empty("bat", deco.bats)
        A.prim("sphere", { parent = b, scale = { 0.25, 0.2, 0.3 }, color = { 0.08, 0.06, 0.1 } })
        local wl = A.prim("cube", { parent = b, pos = { -0.3, 0, 0 }, scale = { 0.45, 0.02, 0.22 }, color = { 0.1, 0.08, 0.12 } })
        local wr = A.prim("cube", { parent = b, pos = { 0.3, 0, 0 }, scale = { 0.45, 0.02, 0.22 }, color = { 0.1, 0.08, 0.12 } })
        for _, sx in ipairs({ -1, 1 }) do
            local e = A.prim("cube", { parent = b, pos = { sx * 0.05, 0.03, 0.14 }, scale = { 0.04, 0.04, 0.02 }, color = { 1, 0.2, 0.1 } })
            A.material(e, { emit = { 3, 0.4, 0.2 }, noShadow = true })
        end
        bats[i] = { o = b, wl = wl, wr = wr, a = i * 0.63, r = 8 + (i % 4) * 5, y = 6 + (i % 3) * 2.5, cz = ((i % 3) - 1) * 18, spd = 0.35 + (i % 4) * 0.08 }
    end
    A.setVisible(deco.bats, false)
end

---------------------------------------------------------------------------
-- Consultas
---------------------------------------------------------------------------
function Ev.isNight() return Ev.clock >= Ev.DAY end

function Ev.luck()
    local l = 1
    if Ev.isNight() then l = l * 2 end
    if Ev.current == "lava" then l = l * 3 end
    if G.player and G.player.luckBoost then l = l * G.player.luckBoost() end
    return l
end

-- mutacao do evento ativo e a chance
function Ev.mutation()
    if Ev.current == "lava" then return "lava", 0.3 end
    if Ev.current == "candy" then return "candy", 0.35 end
    if Ev.isNight() then return "halloween", 0.25 end
    return nil, 0
end

function Ev.moneyMult()
    local m = 1
    if Ev.current == "candy" then m = m * 2 end
    return m
end

-- lista de boosts ativos para o HUD: { {kind, tempo restante} }
function Ev.boosts()
    local out = {}
    if Ev.isNight() then out[#out + 1] = { "halloween", Ev.DAY + Ev.NIGHT - Ev.clock } end
    if Ev.current then out[#out + 1] = { Ev.current, Ev.eventT } end
    for k, t in pairs(Ev.personal) do
        if t > 0 then out[#out + 1] = { k, t } end
    end
    return out
end

---------------------------------------------------------------------------
-- Musica e clima
---------------------------------------------------------------------------
local function setMusic(kind)
    if music.kind == kind then return end
    if music.id then pcall(function() EMRAPI.Audio:Stop(music.id) end) end
    music.kind = kind
    local ok, id = pcall(function() return EMRAPI.Audio:PlayLoop("sounds/music_" .. kind .. ".wav") end)
    music.id = ok and id or nil
    if music.id then
        pcall(function() EMRAPI.Audio:SetVolume(music.id, (G.settings.musicVol or 0.5) * 0.55) end)
    end
end

function Ev.setMusicVolume(v)
    if music.id then pcall(function() EMRAPI.Audio:SetVolume(music.id, v * 0.55) end) end
end

local function setAmbient(kind)
    local col = ({ day = { 0.75, 0.78, 0.85 }, night = { 0.22, 0.2, 0.36 }, lava = { 0.7, 0.35, 0.25 }, candy = { 0.9, 0.75, 0.85 } })[kind]
    pcall(function()
        CS.UnityEngine.RenderSettings.ambientLight = CS.UnityEngine.Color(col[1], col[2], col[3], 1)
    end)
end

local look = nil
local function applyLook()
    local kind = "day"
    if Ev.current == "lava" then kind = "lava"
    elseif Ev.isNight() then kind = "night"
    elseif Ev.current == "candy" then kind = "candy" end
    if look == kind then return end
    local first = look == nil
    look = kind
    G.world.setSky(kind)
    setAmbient(kind)
    A.setVisible(deco.pumpkins, Ev.isNight())
    A.setVisible(deco.bats, Ev.isNight())
    setMusic(kind)
    if not first and G.hud then
        if kind == "night" then G.hud.toast("ev_halloween", 4); G.sound("sounds/ev_halloween.wav")
        elseif kind == "candy" then G.hud.toast("ev_candy", 4); G.sound("sounds/ev_candy.wav")
        elseif kind == "lava" then G.hud.toast("ev_lava", 4); G.sound("sounds/ev_lava.wav")
        elseif kind == "day" then G.hud.toast("ev_day", 3) end
    end
end

---------------------------------------------------------------------------
-- Doces (evento Candy) — locais de cada jogador
---------------------------------------------------------------------------
local CANDY_COLS = { { 1, 0.3, 0.6 }, { 0.3, 0.8, 1 }, { 1, 0.85, 0.2 }, { 0.5, 1, 0.5 }, { 0.8, 0.4, 1 } }
local function spawnCandy()
    if #candies >= 18 then return end
    local x = (G.rand() * 2 - 1) * 15
    local z = (G.rand() * 2 - 1) * 33
    if Lt.baseAt({ x, 0, z }) then return end
    local root = A.empty("candy", Ev.root, { x, 9, z })
    local col = CANDY_COLS[math.random(#CANDY_COLS)]
    A.prim("sphere", { parent = root, scale = { 0.3, 0.3, 0.3 }, color = col, mat = { emit = V.scale(col, 0.5), smooth = 0.9 } })
    for _, sx in ipairs({ -1, 1 }) do
        A.prim("cube", { parent = root, pos = { sx * 0.2, 0, 0 }, scale = { 0.12, 0.2, 0.2 }, rot = { 45, 0, 0 }, color = { 1, 1, 1 } })
    end
    candies[#candies + 1] = { o = root, pos = { x, 9, z }, vy = -3, t = 0 }
end

local function updateCandies(dt, feet)
    for i = #candies, 1, -1 do
        local c = candies[i]
        c.t = c.t + dt
        if c.pos[2] > 0.35 then
            c.pos[2] = math.max(0.35, c.pos[2] + c.vy * dt)
        else
            c.pos[2] = 0.35 + math.sin(c.t * 3) * 0.06
        end
        A.pos(c.o, c.pos)
        A.rot(c.o, 0, c.t * 120, 20)
        local got = V.distXZ(c.pos, feet) < 0.85 and c.pos[2] < 1.5
        if got or c.t > 30 or (Ev.current ~= "candy" and c.pos[2] <= 0.4 and c.t > 3) then
            if got and G.player then G.player.candy(c.pos) end
            A.destroy(c.o)
            table.remove(candies, i)
        end
    end
end

---------------------------------------------------------------------------
-- Meteoros (evento Lava)
---------------------------------------------------------------------------
local function spawnMeteor(target)
    local p = target or { (G.rand() * 2 - 1) * 16, 0, (G.rand() * 2 - 1) * 34 }
    local m = { target = p, t = 0, fall = 1.6 }
    m.ring = A.prim("cylinder", { parent = Ev.root, pos = { p[1], 0.04, p[3] }, scale = { 2.6, 0.01, 2.6 }, color = { 1, 0.15, 0.05 } })
    A.material(m.ring, { emit = { 1.5, 0.1, 0.0 }, noShadow = true })
    m.rock = A.prim("sphere", { parent = Ev.root, pos = { p[1] + 6, 25, p[3] + 4 }, scale = { 0.9, 0.9, 0.9 }, color = { 0.35, 0.12, 0.05 } })
    A.material(m.rock, { emit = { 2.2, 0.5, 0.05 } })
    meteors[#meteors + 1] = m
end

local function updateMeteors(dt)
    for i = #meteors, 1, -1 do
        local m = meteors[i]
        m.t = m.t + dt
        local p = m.target
        if not m.landed then
            local k = math.min(1, m.t / m.fall)
            A.posXYZ(m.rock, p[1] + 6 * (1 - k), 25 * (1 - k) + 0.3, p[3] + 4 * (1 - k))
            local s = 2.6 * (0.5 + 0.5 * math.abs(math.sin(m.t * 10)))
            A.scale(m.ring, s, 0.01, s)
            if k >= 1 then
                m.landed = true
                m.t = 0
                A.scale(m.ring, 2.4, 0.02, 2.4)
                A.color(m.ring, { 1, 0.45, 0.05 })
                G.sound3D("sounds/meteor.wav", p, 1)
                if G.fx then
                    for _ = 1, 3 do G.fx.hit(V.add(p, { 0, 0.4, 0 })) end
                    G.fx.sparkle(V.add(p, { 0, 0.3, 0 }), { 1, 0.5, 0.1 }, 20)
                end
                if G.onMeteor then G.onMeteor(p, 1.5) end
            end
        else
            -- poca de lava por alguns segundos
            if G.onLavaPool then G.onLavaPool(p, 1.1) end
            if m.t > 5 then
                A.destroy(m.ring)
                A.destroy(m.rock)
                table.remove(meteors, i)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Atualizacao
---------------------------------------------------------------------------
local meteorT, candyT = 0, 0
local syncT = 0

function Ev.start(kind, dur)
    Ev.current = kind
    Ev.eventT = dur or (kind == "lava" and 60 or 75)
end

function Ev.update(dt, authority, feet)
    -- relogio
    Ev.clock = (Ev.clock + dt) % (Ev.DAY + Ev.NIGHT)
    if Ev.current then
        Ev.eventT = Ev.eventT - dt
        if Ev.eventT <= 0 then Ev.current = nil end
    end
    for k, t in pairs(Ev.personal) do Ev.personal[k] = math.max(0, t - dt) end
    if authority then
        if not Ev.current then
            Ev.nextCandy = Ev.nextCandy - dt
            Ev.nextLava = Ev.nextLava - dt
            if Ev.nextLava <= 0 then
                Ev.start("lava")
                Ev.nextLava = 900 + G.rand() * 700
                Ev.nextCandy = math.max(Ev.nextCandy, 120)
            elseif Ev.nextCandy <= 0 then
                Ev.start("candy")
                Ev.nextCandy = 330 + G.rand() * 240
            end
        end
        syncT = syncT - dt
        if syncT <= 0 then
            syncT = 4
            G.net.send("world", Ev.snapshot())
        end
    end
    applyLook()
    -- efeitos locais
    if Ev.current == "candy" then
        candyT = candyT - dt
        if candyT <= 0 then candyT = 0.45; spawnCandy() end
    end
    updateCandies(dt, feet)
    if Ev.current == "lava" then
        meteorT = meteorT - dt
        if meteorT <= 0 then
            meteorT = 1.1 + G.rand() * 1.2
            -- de vez em quando o meteoro mira perto do jogador (perigo de verdade)
            if G.rand() < 0.35 then
                spawnMeteor({ feet[1] + (G.rand() * 2 - 1) * 3, 0, feet[3] + (G.rand() * 2 - 1) * 3 })
            else
                spawnMeteor()
            end
        end
    end
    updateMeteors(dt)
    if Ev.isNight() then
        local t = G.realTime
        for _, b in ipairs(bats) do
            b.a = b.a + dt * b.spd
            A.posXYZ(b.o, math.sin(b.a) * b.r, b.y + math.sin(t * 2 + b.a) * 0.6, b.cz + math.cos(b.a) * b.r)
            A.rot(b.o, 0, b.a * V.DEG + 90, 0)
            local f = math.sin(t * 18 + b.a) * 35
            A.rot(b.wl, 0, 0, f)
            A.rot(b.wr, 0, 0, -f)
        end
    end
end

function Ev.snapshot()
    return { c = math.floor(Ev.clock), e = Ev.current or "", t = math.floor(Ev.eventT) }
end

function Ev.apply(t)
    Ev.clock = t.c or Ev.clock
    if t.e and t.e ~= "" then
        if Ev.current ~= t.e then Ev.start(t.e, t.t) else Ev.eventT = t.t or Ev.eventT end
    else
        Ev.current = nil
    end
end

function Ev.shutdown()
    if music.id then pcall(function() EMRAPI.Audio:Stop(music.id) end) end
    music.id, music.kind = nil, nil
end

-- forca evento (menu de teste / cenarios)
function Ev.force(kind)
    if kind == "night" then Ev.clock = Ev.DAY + 1
    elseif kind == "day" then Ev.clock = 10; Ev.current = nil
    else Ev.start(kind) end
end

Ev.K = K
return Ev
