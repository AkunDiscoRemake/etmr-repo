-- player.lua — o jogador local: dinheiro, pulo, itens (taco, luva, mola, armadilha, capa),
-- golpes (gatilho do Joy-Con OU balancando a mao de verdade), levar pancada,
-- coletar dinheiro das placas, trancar a base, entregar brainrot roubado e doces.

local V = require("vec")
local A = require("api")
local K = require("catalog")
local Lt = require("layout")
local P = require("poses")
local H = require("hands")

local Pl = {}

local G
Pl.money = 200
Pl.rebirths = 0
Pl.owned = { bat = true }
Pl.traps = 0
Pl.equipped = "bat"
Pl.stunT = 0
Pl.vy = 0
Pl.y = 0
Pl.knock = { 0, 0, 0 }
Pl.swingT = 0          -- >0 durante o golpe
Pl.swingCd = 0
Pl.cloakCd = 0
Pl.stats = { stolen = 0, bought = 0, hits = 0, collected = 0 }

-- itens da loja: preco, cooldown do golpe, empurrao, atordoamento
Pl.ITEMS = {
    bat   = { price = 0,     cd = 0.6,  pow = 3.2, stun = 1.8, reach = 2.5 },
    slap  = { price = 15000, cd = 0.5,  pow = 7.5, stun = 2.4, reach = 2.6 },
    coil  = { price = 30000, speed = 1.35 },
    trap  = { price = 8000,  uses = 3 },
    cloak = { price = 90000, dur = 10, cd = 45 },
}
Pl.ORDER = { "bat", "slap", "coil", "trap", "cloak" }

local vrTool = {}
local traps = {}

function Pl.init(ctx)
    G = ctx
end

---------------------------------------------------------------------------
-- Dinheiro
---------------------------------------------------------------------------
function Pl.addMoney(v, pos)
    if v <= 0 then return end
    Pl.money = Pl.money + v
    if pos and G.fx then G.fx.popText(pos, "+$" .. K.fmt(v)) end
end

function Pl.spend(v)
    if Pl.money < v then return false end
    Pl.money = Pl.money - v
    return true
end

function Pl.moneyMult()
    return (1 + 0.5 * Pl.rebirths) * G.events.moneyMult()
end

function Pl.luckBoost()
    return 1 + 0.1 * Pl.rebirths
end

---------------------------------------------------------------------------
-- Ferramenta na mao (VR)
---------------------------------------------------------------------------
local function buildVrTool(item)
    if vrTool.root then A.destroy(vrTool.root) end
    vrTool = { item = item }
    if not item then return end
    local root = A.empty("vrTool", G.rig.world)
    vrTool.root = root
    local function p(kind, pos, sc, col, rot, mat)
        return A.prim(kind, { parent = root, pos = pos, scale = sc, color = col, rot = rot, mat = mat })
    end
    if item == "bat" then
        p("cylinder", { 0, 0.05, 0 }, { 0.032, 0.1, 0.032 }, { 0.15, 0.15, 0.15 })
        p("cylinder", { 0, 0.36, 0 }, { 0.048, 0.22, 0.048 }, { 0.75, 0.52, 0.28 }, nil, { smooth = 0.5 })
        p("cylinder", { 0, 0.57, 0 }, { 0.066, 0.05, 0.066 }, { 0.78, 0.55, 0.3 }, nil, { smooth = 0.5 })
        vrTool.len = 0.64
    elseif item == "slap" then
        p("cylinder", { 0, 0.08, 0 }, { 0.04, 0.12, 0.04 }, { 0.9, 0.2, 0.2 })
        p("cube", { 0, 0.32, 0 }, { 0.26, 0.3, 0.07 }, { 1, 0.85, 0.3 }, nil, { smooth = 0.4 })
        for k = 0, 3 do p("cube", { -0.09 + k * 0.06, 0.53, 0 }, { 0.045, 0.14, 0.06 }, { 1, 0.85, 0.3 }) end
        vrTool.len = 0.6
    elseif item == "coil" then
        for k = 0, 5 do p("cylinder", { 0, 0.05 + k * 0.035, 0 }, { 0.1, 0.008, 0.1 }, { 0.3, 0.6, 1.0 }, nil, { emit = { 0.2, 0.6, 1.4 } }) end
        p("cylinder", { 0, 0.12, 0 }, { 0.03, 0.1, 0.03 }, { 0.8, 0.8, 0.85 }, nil, { metal = 0.8 })
        vrTool.len = 0.25
    elseif item == "trap" then
        p("cylinder", { 0, 0.08, 0.06 }, { 0.22, 0.015, 0.22 }, { 0.5, 0.5, 0.55 }, { 90, 0, 0 }, { metal = 0.8 })
        p("cube", { 0, 0.08, 0.08 }, { 0.2, 0.03, 0.03 }, { 0.3, 0.3, 0.32 })
        vrTool.len = 0.2
    elseif item == "cloak" then
        p("cube", { 0, 0.16, 0.02 }, { 0.22, 0.3, 0.03 }, { 0.35, 0.2, 0.6 }, nil, { emit = { 0.25, 0.12, 0.5 } })
        vrTool.len = 0.3
    end
end

function Pl.equip(item)
    if not Pl.owned[item] then return end
    if item == "trap" and Pl.traps <= 0 then return end
    Pl.equipped = item
    buildVrTool(item)
    if G.localEnt then G.ents.setItem(G.localEnt, item) end
    G.sound("sounds/equip.wav", 0.6)
end

function Pl.cycleItem()
    local idx = 1
    for i, k in ipairs(Pl.ORDER) do if k == Pl.equipped then idx = i end end
    for n = 1, #Pl.ORDER do
        local k = Pl.ORDER[(idx + n - 1) % #Pl.ORDER + 1]
        if Pl.owned[k] and (k ~= "trap" or Pl.traps > 0) then Pl.equip(k); return end
    end
end

---------------------------------------------------------------------------
-- Maos: rastreadas (mao fake articulada) ou "virtuais" (Joy-Con sem tracking)
---------------------------------------------------------------------------
Pl.handPts = { left = {}, right = {} }
local function virtualHand(side, swing)
    local R = G.rig
    local f = R.flatForward()
    local up = { 0, 1, 0 }
    local sx = side == "right" and 1 or -1
    local rgt = { f[3], 0, -f[1] }
    local base = V.add(R.bodyPoint(0, -0.58, 0), V.add(V.scale(rgt, 0.26 * sx), V.scale(f, 0.22)))
    local yObj
    if side == "right" and swing then
        -- golpe: do alto/atras para frente/baixo
        local a = math.rad(-75 + 150 * swing)
        yObj = V.norm(V.add(V.scale(up, math.cos(a)), V.scale(f, math.sin(a))))
        base = V.add(base, V.add(V.scale(up, 0.18 * math.cos(a)), V.scale(f, 0.15 * math.sin(a) + 0.05)))
    else
        -- descansando: quase em pe, inclinado para fora (nao tampa a visao)
        yObj = V.norm(V.add(V.add(V.scale(up, 0.42), V.scale(f, 1.0)), V.scale(rgt, 0.22 * sx)))
    end
    local zObj = V.norm(V.cross(rgt, yObj))
    if V.dot(zObj, f) < 0 then zObj = V.scale(zObj, -1) end
    local basis = V.basis(zObj, yObj)
    local c = P.get("fist", side)
    return P.toWorld(c.pts, base, basis, Pl.handPts[side]), base, basis
end

local function drawHands(swing)
    local C = G.controls
    for _, side in ipairs({ "left", "right" }) do
        local h = C.hands[side]
        local holding = side == "right" and vrTool.root
        if h.tracked then
            local pts = h.lm
            if holding then
                -- a mao fecha no cabo do item
                local pos, B = P.objectFromHand(h.palm, h.basis, "fist", side)
                pts = P.toWorld(P.get("fist", side).pts, pos, B, Pl.handPts[side])
                vrTool.pos, vrTool.basis = pos, B
            end
            H.setVisible(side, true)
            H.draw(side, pts)
        else
            local pts, pos, B = virtualHand(side, side == "right" and swing or nil)
            H.setVisible(side, true)
            H.draw(side, pts)
            if holding then vrTool.pos, vrTool.basis = pos, B end
        end
    end
    if vrTool.root and vrTool.pos then
        A.pos(vrTool.root, vrTool.pos)
        A.rotBasis(vrTool.root, vrTool.basis)
    end
end

---------------------------------------------------------------------------
-- Golpe
---------------------------------------------------------------------------
local function doHits()
    if not G.localEnt then return end
    local it = Pl.ITEMS[Pl.equipped]
    if not it or not it.pow then return end
    local R = G.rig
    local feet = { R.head[1], 0, R.head[3] }
    local f = R.flatForward()
    local tip = vrTool.pos and vrTool.basis and V.madd(vrTool.pos, vrTool.basis.u, vrTool.len or 0.6) or nil
    local hit = false
    for _, e in ipairs(G.ents.order) do
        if e ~= G.localEnt and e.stunT <= 0 then
            local d = V.sub(e.pos, feet)
            d[2] = 0
            local dist = V.len(d)
            local inCone = dist < it.reach and (dist < 0.8 or V.dot(V.scale(d, 1 / math.max(dist, 1e-3)), f) > 0.35)
            local byTip = tip and V.distXZ(tip, e.pos) < 0.75
            if inCone or byTip then
                G.game.hitEnt(e, d, it.pow, it.stun, G.localEnt.id)
                hit = true
            end
        end
    end
    if hit then
        Pl.stats.hits = Pl.stats.hits + 1
        G.sound(Pl.equipped == "slap" and "sounds/slap.wav" or "sounds/bonk.wav", 1)
    end
end

local function startSwing()
    if not G.localEnt then return end
    local it = Pl.ITEMS[Pl.equipped]
    if not it or not it.pow or Pl.swingCd > 0 or Pl.stunT > 0 then return end
    Pl.swingT = 0.0001
    Pl.swingCd = it.cd
    Pl.swingHit = false
    G.localEnt.swing = 0.001
    G.sound("sounds/swing.wav", 0.7)
end

local function useItem()
    if not G.localEnt then return end
    local k = Pl.equipped
    if k == "bat" or k == "slap" then startSwing()
    elseif k == "trap" and Pl.traps > 0 then
        local R = G.rig
        local p = V.madd({ R.head[1], 0, R.head[3] }, R.flatForward(), 1.0)
        Pl.placeTrap(p)
        Pl.traps = Pl.traps - 1
        if Pl.traps <= 0 then Pl.equip("bat") end
    elseif k == "cloak" and Pl.cloakCd <= 0 then
        G.localEnt.invisT = Pl.ITEMS.cloak.dur
        Pl.cloakCd = Pl.ITEMS.cloak.cd
        G.sound("sounds/cloak.wav", 0.9)
        G.hud.toast("cloak_on", 2.5)
    end
end

-- armadilhas (locais)
function Pl.placeTrap(p)
    local o = A.empty("trap", G.rig.world, { p[1], 0, p[3] })
    A.prim("cylinder", { parent = o, pos = { 0, 0.03, 0 }, scale = { 0.6, 0.03, 0.6 }, color = { 0.45, 0.45, 0.5 }, mat = { metal = 0.8 } })
    for k = 0, 5 do
        A.prim("cube", { parent = o, pos = { math.sin(k) * 0.25, 0.08, math.cos(k) * 0.25 }, scale = { 0.04, 0.12, 0.04 }, rot = { 0, k * 60, 20 }, color = { 0.75, 0.75, 0.8 }, mat = { metal = 0.9 } })
    end
    traps[#traps + 1] = { o = o, pos = { p[1], 0, p[3] }, t = 120 }
    G.sound3D("sounds/trap_set.wav", p, 0.8)
end

local function updateTraps(dt)
    for i = #traps, 1, -1 do
        local t = traps[i]
        t.t = t.t - dt
        local sprung = false
        for _, e in ipairs(G.ents.order) do
            if e ~= G.localEnt and V.distXZ(e.pos, t.pos) < 0.55 and e.stunT <= 0 then
                G.game.hitEnt(e, { 0, 0, 0.01 }, 0.2, 3.0, G.localEnt.id)
                sprung = true
            end
        end
        if sprung or t.t <= 0 then
            if sprung then G.sound3D("sounds/trap_snap.wav", t.pos, 1) end
            A.destroy(t.o)
            table.remove(traps, i)
        end
    end
end

---------------------------------------------------------------------------
-- Levar pancada / perigo
---------------------------------------------------------------------------
function Pl.onHit(dir, pow, stun)
    if Pl.stunT > 0.3 or not G.localEnt then return end
    Pl.stunT = stun or 1.6
    local d = V.norm({ dir[1], 0, dir[3] })
    Pl.knock = V.scale(d, (pow or 3) * 3.0)
    if Pl.y <= 0.01 then Pl.vy = 3.0 end
    G.localEnt.stunT = Pl.stunT
    G.game.dropCarry(G.localEnt)
    G.hud.flash()
    G.sound("sounds/hurt.wav", 1)
end

-- pulo
local function jump()
    if Pl.y > 0.02 or Pl.stunT > 0 then return end
    Pl.vy = 4.8
    G.sound("sounds/jump.wav", 0.5)
end

---------------------------------------------------------------------------
-- Doces
---------------------------------------------------------------------------
function Pl.candy(pos)
    local inc = G.bases.totalIncome(G.myBase)
    local v = math.floor(25 + inc * 8)
    Pl.addMoney(v, V.add(pos, { 0, 0.6, 0 }))
    G.events.personal.sugar = math.min(30, (G.events.personal.sugar or 0) + 6)
    G.sound("sounds/candy.wav", 0.8)
    G.fx.sparkle(pos, { 1, 0.5, 0.8 }, 8)
end

-- multiplicador de velocidade
function Pl.speedMult()
    if Pl.stunT > 0 then return 0 end
    local m = 1
    if G.localEnt and G.localEnt.carry then m = m * 0.8 end
    if Pl.equipped == "coil" then m = m * Pl.ITEMS.coil.speed end
    if (G.events.personal.sugar or 0) > 0 then m = m * 1.2 end
    return m
end

---------------------------------------------------------------------------
-- Atualizacao
---------------------------------------------------------------------------
local padCd = {}
function Pl.update(dt)
    local R, C = G.rig, G.controls
    local feet = { R.head[1], 0, R.head[3] }
    Pl.swingCd = math.max(0, Pl.swingCd - dt)
    Pl.cloakCd = math.max(0, Pl.cloakCd - dt)
    if Pl.stunT > 0 then Pl.stunT = math.max(0, Pl.stunT - dt) end

    -- empurrao
    if V.len(Pl.knock) > 0.05 then
        R.move(Pl.knock[1] * dt, Pl.knock[3] * dt)
        Pl.knock = V.scale(Pl.knock, math.max(0, 1 - dt * 4))
    end
    -- pulo / gravidade
    if Pl.y > 0 or Pl.vy > 0 then
        Pl.vy = Pl.vy - 13 * dt
        Pl.y = math.max(0, Pl.y + Pl.vy * dt)
        if Pl.y <= 0 then Pl.vy = 0; G.fx.dust(feet, 4) end
        R.setLift(Pl.y)
    end

    if not C.calibrating then
        local rh, lh = C.hands.right, C.hands.left
        if rh.primaryDown or lh.primaryDown then jump() end
        if lh.trigDown then Pl.cycleItem() end
        if rh.trigDown then useItem() end
        -- golpe com a mao rastreada (balanco rapido)
        if rh.tracked and not rh.usingPad and (Pl.equipped == "bat" or Pl.equipped == "slap") then
            local sp = V.len(rh.palmVel)
            if sp > 3.2 and Pl.swingCd <= 0 then startSwing() end
        end
    end
    -- progresso do golpe
    local swing = nil
    if Pl.swingT > 0 then
        Pl.swingT = Pl.swingT + dt / 0.38
        swing = math.min(1, Pl.swingT)
        if not Pl.swingHit and Pl.swingT > 0.35 then Pl.swingHit = true; doHits() end
        if Pl.swingT >= 1 then Pl.swingT = 0 end
    end
    drawHands(swing)
    updateTraps(dt)

    -- coletar dinheiro: pisar na placa verde (ou encostar a mao)
    local my = G.myBase
    if my then
        local wb = G.world.bases[my]
        for s = 1, Lt.SLOTS do
            padCd[s] = math.max(0, (padCd[s] or 0) - dt)
            local pad = wb.pads[s]
            local touch = V.distXZ(feet, pad.pos) < 0.6
            if not touch then
                for _, side in ipairs({ "left", "right" }) do
                    local h = C.hands[side]
                    if h.tracked and V.dist(h.palm, { pad.pos[1], 0.3, pad.pos[3] }) < 0.35 then touch = true end
                end
            end
            if touch and padCd[s] <= 0 then
                local v = G.bases.collect(my, s)
                if v > 0 then
                    Pl.addMoney(v, V.add(pad.pos, { 0, 0.9, 0 }))
                    Pl.stats.collected = Pl.stats.collected + v
                    G.sound("sounds/cash.wav", 0.8)
                    G.fx.sparkle(V.add(pad.pos, { 0, 0.3, 0 }), { 0.4, 1, 0.45 }, 8)
                    padCd[s] = 0.5
                end
            end
        end
        -- trancar: pisar no botao vermelho
        local lp = G.world.bases[my].lockPos
        if V.distXZ(feet, lp) < 0.55 and not G.bases.isLocked(my) then
            G.game.lockMyBase()
        end
        -- entregar o brainrot roubado
        if G.localEnt.carry and Lt.inBase(my, feet, 0.4) then
            G.game.deliver(G.localEnt)
        end
    end
end

function Pl.reset()
    Pl.stunT, Pl.vy, Pl.y = 0, 0, 0
    Pl.knock = { 0, 0, 0 }
    if G.rig.liftY ~= 0 then G.rig.setLift(0) end
end

function Pl.getVrTool() return vrTool end

return Pl
