-- player.lua — vida, dano (borda vermelha na visao), relogio de vida no pulso esquerdo,
-- socos, regeneracao, morte/respawn e o crab grudado no rosto.

local V = require("vec")
local A = require("api")
local Seg = require("segdisplay")

local Pl = {}
local G

Pl.hp = 100
Pl.maxHp = 100
Pl.dead = false
Pl.lastDamage = -99
Pl.crabs = 0
Pl.god = false

local border = {}
local borderOn = false
local flashT = 0
local watch, watchBar, watchBarBack, watchRoot
local heartT = 0

local function makeBorder()
    -- quatro barras vermelhas presas na camera (nas bordas da visao)
    local defs = {
        { 0, 0.21, 0.32, 0.9, 0.12 }, { 0, -0.21, 0.32, 0.9, 0.12 },
        { -0.27, 0, 0.32, 0.12, 0.6 }, { 0.27, 0, 0.32, 0.12, 0.6 },
    }
    for i, d in ipairs(defs) do
        local o = A.prim("quad", { scale = { d[4], d[5], 1 }, color = { 0.8, 0.02, 0.02 }, mat = { emit = { 1.2, 0, 0 }, noShadow = true } })
        local ok = pcall(function() EMRAPI.Scene:AttachToHeadAt(o, d[1], d[2], d[3]) end)
        border[i] = { obj = o, attached = ok, off = d }
        A.setVisible(o, false)
    end
end

local function showBorder(on, intensity)
    if on == borderOn and not on then return end
    borderOn = on
    for _, b in ipairs(border) do
        A.setVisible(b.obj, on, b.off[4], b.off[5], 1)
        if on then A.colorRGB(b.obj, 0.5 + 0.5 * intensity, 0.02, 0.02) end
    end
end

local function makeWatch()
    watchRoot = A.empty("watch", G.rig.world)
    A.prim("cube", { parent = watchRoot, pos = { 0, 0, 0.004 }, scale = { 0.06, 0.036, 0.01 }, color = { 0.05, 0.05, 0.06 }, mat = { metal = 0.8, smooth = 0.8 } })
    A.prim("cube", { parent = watchRoot, pos = { 0, 0, 0.008 }, scale = { 0.066, 0.042, 0.006 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 0.6, 0.2, 0.02 } } })
    watch = Seg.new({ parent = watchRoot, center = { 0, 0.004, -0.002 }, n = 3, size = 0.017, on = { 0.3, 1, 0.5 }, back = false })
    watchBarBack = A.prim("cube", { parent = watchRoot, pos = { 0, -0.013, -0.002 }, scale = { 0.05, 0.004, 0.002 }, color = { 0.15, 0.03, 0.03 } })
    watchBar = A.prim("cube", { parent = watchRoot, pos = { 0, -0.013, -0.003 }, scale = { 0.05, 0.004, 0.002 }, color = { 0.3, 1, 0.5 }, mat = { emit = { 0.3, 1.5, 0.5 } } })
end

local lastShownHp = -1
local function updateWatch()
    local hl = G.hands.get("left")
    if not hl or not hl.visible then return end
    local f = hl.basis.f
    local dorsal = hl.dorsal
    local center = V.add(V.madd(hl.wrist, dorsal, 0.034), V.scale(f, -0.035))
    -- quem le olha "para dentro" do mostrador (-dorsal); texto corre em direcao aos dedos
    local up = V.cross(V.scale(dorsal, -1), f)
    local Bw = V.basis(V.scale(dorsal, -1), up)
    A.pos(watchRoot, center)
    A.rotBasis(watchRoot, Bw)
    local hp = math.max(0, math.floor(Pl.hp + 0.5))
    if hp ~= lastShownHp then
        lastShownHp = hp
        watch:set(hp)
        local k = hp / Pl.maxHp
        local c = k > 0.5 and { 0.3, 1, 0.5 } or (k > 0.25 and { 1, 0.8, 0.1 } or { 1, 0.15, 0.1 })
        watch:setColor(c)
        A.scale(watchBar, 0.05 * math.max(0.01, k), 0.004, 0.002)
        A.posXYZ(watchBar, -0.025 + 0.025 * k, -0.013, -0.003)
        A.color(watchBar, c)
    end
end

---------------------------------------------------------------------------
function Pl.hitTest(p, r)
    local head = G.rig.head
    if V.dist(p, head) < 0.14 + r then return true end
    local a = V.add(head, { 0, -0.28, 0 })
    local b = V.add(head, { 0, -1.15, 0 })
    return V.pointSegDist(p, a, b) < 0.22 + r
end

function Pl.damage(amount, from, silent)
    if Pl.dead or Pl.god or G.mode == "menu" then return end
    Pl.hp = Pl.hp - amount
    Pl.lastDamage = G.time
    flashT = math.max(flashT, 0.25 + amount / 60)
    if not silent then A.sound("sounds/player_hurt.wav", 0.9) end
    if G.game then G.game.onPlayerHurt(amount) end
    if Pl.hp <= 0 then
        Pl.hp = 0
        Pl.dead = true
        A.sound("sounds/player_die.wav", 1)
        if G.game then G.game.onPlayerDeath() end
    end
end

function Pl.heal(full)
    Pl.hp = full and Pl.maxHp or math.min(Pl.maxHp, Pl.hp + 25)
    Pl.dead = false
end

function Pl.crabOn(bot)
    Pl.crabs = Pl.crabs + 1
    if G.game then G.game.message("ARRANQUE O CRAB DO ROSTO!", 2.5) end
end

function Pl.crabOff()
    Pl.crabs = math.max(0, Pl.crabs - 1)
end

function Pl.update(dt)
    -- regeneracao
    if not Pl.dead and G.time - Pl.lastDamage > 4 and Pl.hp < Pl.maxHp then
        Pl.hp = math.min(Pl.maxHp, Pl.hp + 6 * dt)
    end
    -- borda vermelha
    flashT = math.max(0, flashT - dt)
    local low = Pl.hp < 30 and not Pl.dead
    if flashT > 0 then
        showBorder(true, math.min(1, flashT * 2))
    elseif low then
        local pulse = (math.sin(G.time * 6) + 1) * 0.5
        showBorder(pulse > 0.55, pulse)
        heartT = heartT - dt
        if heartT <= 0 then heartT = 0.9; A.sound("sounds/heartbeat.wav", 0.7) end
    else
        showBorder(false, 0)
    end
    -- barras manuais se AttachToHeadAt nao existir
    for _, b in ipairs(border) do
        if not b.attached and borderOn then
            local hb = G.rig.headB
            local p = V.add(G.rig.head, V.add(V.add(V.scale(hb.r, b.off[1]), V.scale(hb.u, b.off[2])), V.scale(hb.f, b.off[3])))
            A.parent(b.obj, G.rig.world)
            A.pos(b.obj, p)
            A.rotBasis(b.obj, hb)
        end
    end

    -- socos com a mao livre
    for _, side in ipairs({ "left", "right" }) do
        local h = G.controls.hands[side]
        if h.tracked and not h.busy and h.gestGrip ~= nil then
            G.bots.punch(h.palm, h.palmVel, side)
        end
    end
    updateWatch()
end

function Pl.init(ctx)
    G = ctx
    makeBorder()
    makeWatch()
end

return Pl
