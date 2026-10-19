-- player.lua — jogador do SUPERHOT: um acerto mata (bala, katana ou soco inimigo).
-- Morte: borda vermelha, tempo congela, fase recomeca. Socos com a mao livre.

local V = require("vec")
local A = require("api")

local Pl = {}
local G

Pl.dead = false
Pl.god = false

local border = {}
local borderOn = false

local function makeBorder()
    local defs = {
        { 0, 0.21, 0.32, 0.9, 0.14 }, { 0, -0.21, 0.32, 0.9, 0.14 },
        { -0.27, 0, 0.32, 0.14, 0.6 }, { 0.27, 0, 0.32, 0.14, 0.6 },
    }
    for i, d in ipairs(defs) do
        local o = A.prim("quad", { scale = { d[4], d[5], 1 }, color = { 0.9, 0.04, 0.03 }, mat = { emit = { 1.5, 0, 0 }, noShadow = true } })
        local ok = pcall(function() EMRAPI.Scene:AttachToHeadAt(o, d[1], d[2], d[3]) end)
        border[i] = { obj = o, attached = ok, off = d }
        A.setVisible(o, false)
    end
end

local function showBorder(on)
    if on == borderOn then return end
    borderOn = on
    for _, b in ipairs(border) do A.setVisible(b.obj, on, b.off[4], b.off[5], 1) end
end

function Pl.die(dir)
    if Pl.dead or Pl.god or G.mode ~= "level" then return end
    Pl.dead = true
    Pl.deathT = 0
    G.sound("sounds/player_die.wav", 1)
    G.time.force(0.015)
    showBorder(true)
    G.items.releaseAll()
    if G.game then G.game.onPlayerDeath() end
end

function Pl.revive()
    Pl.dead = false
    showBorder(false)
    G.time.force(nil)
end

function Pl.update(dt)
    if Pl.dead then
        Pl.deathT = Pl.deathT + dt
        -- borda pisca
        showBorder(math.floor(Pl.deathT * 6) % 2 == 0 or Pl.deathT > 0.8)
    end
    for _, b in ipairs(border) do
        if not b.attached and borderOn then
            local hb = G.rig.headB
            local p = V.add(G.rig.head, V.add(V.add(V.scale(hb.r, b.off[1]), V.scale(hb.u, b.off[2])), V.scale(hb.f, b.off[3])))
            A.parent(b.obj, G.rig.world)
            A.pos(b.obj, p)
            A.rotBasis(b.obj, hb)
        end
    end
    if Pl.dead then return end
    -- socos com a mao livre (velocidade real)
    for _, side in ipairs({ "left", "right" }) do
        local h = G.controls.hands[side]
        if h.tracked and not h.busy then
            G.enemies.punch(h.palm, h.palmVel)
            -- mao aberta rapida tambem rebate bala (tapa)
            if V.len(h.palmVel) > 2.5 then G.bullets.blockSphere(h.palm, 0.08) end
        end
    end
end

function Pl.init(ctx)
    G = ctx
    makeBorder()
end

return Pl
