-- items.lua — sistema de itens seguraveis (armas, taco, pentes).
--  * pegar pelo cabo (pose de pistola) e pelo guarda-mao (pose de apoio, duas maos)
--  * a mao fake "encaixa" na arma: os dedos seguem a pose e o indicador acompanha o gatilho
--  * soltar = arremessar com a velocidade real da mao
--  * itens soltos tem fisica propria em Lua (queda, quique, deitar de lado no chao)
--  * pente: leve ate o encaixe da arma para recarregar; bolsa no quadril da pentes infinitos
--  * mesa de armas reabastece sozinha

local V = require("vec")
local A = require("api")
local P = require("poses")
local Wp = require("weapons")

local I = {}
local G

I.list = {}
I.holding = { left = nil, right = nil }     -- { item = it, gp = "grip"|"fore" } ou { prop = p } ou { crab = b }
I.handPose = { left = nil, right = nil }    -- pontos da mao quando posada
I.slots = {}
I.posed = { left = false, right = false }
I.lastGunType = "pistol"

local trigSmooth = { left = 0, right = 0 }

---------------------------------------------------------------------------
-- Criacao
---------------------------------------------------------------------------
function I.spawn(type, pos, B, opt)
    opt = opt or {}
    local it = {
        type = type, def = Wp.defs[type], pos = V.copy(pos), B = B or V.identity(),
        state = opt.rest and "rest" or "falling", vel = { 0, 0, 0 },
        angAxis = { 1, 0, 0 }, angSpeed = 0, holders = {}, born = G.time,
        gunType = opt.gunType, count = opt.count,
    }
    Wp.build(it)
    I.list[#I.list + 1] = it
    I.place(it, it.pos, it.B)
    return it
end

function I.destroy(it)
    for side, h in pairs(I.holding) do
        if h and h.item == it then I.holding[side] = nil end
    end
    for i, x in ipairs(I.list) do
        if x == it then table.remove(I.list, i); break end
    end
    it.dead = true
    A.destroy(it.root)
end

function I.place(it, pos, B)
    A.pos(it.root, pos)
    A.rotBasis(it.root, B)
end

function I.drop(it, vel)
    it.state = "falling"
    it.vel = V.copy(vel or { 0, 0, 0 })
    local sp = V.len(it.vel)
    it.angAxis = V.norm({ math.random() - 0.5, math.random() - 0.5, math.random() - 0.5 })
    it.angSpeed = 90 + sp * 160
    it.settleT = nil
end

local function isHeld(it)
    return it.holders.grip ~= nil or it.holders.fore ~= nil
end
I.isHeld = isHeld

---------------------------------------------------------------------------
-- Fisica simples dos itens soltos
---------------------------------------------------------------------------
local function lieBasis(it)
    local B = it.B
    local up = { 0, B.r[2] >= 0 and 1 or -1, 0 }
    if it.def.kind == "melee" or it.def.kind == "mag" then
        local u = { B.u[1], 0, B.u[3] }
        if V.len2(u) < 1e-4 then u = { 1, 0, 0 } end
        u = V.norm(u)
        return { r = up, u = u, f = V.cross(up, u) }
    end
    local f = { B.f[1], 0, B.f[3] }
    if V.len2(f) < 1e-4 then f = { 0, 0, 1 } end
    f = V.norm(f)
    return { r = up, u = V.cross(f, up), f = f }
end

local function physics(it, dt)
    local L = G.level
    local r = it.def.restR
    if it.settleT then
        it.settleT = it.settleT + dt
        local k = math.min(1, it.settleT / 0.15)
        it.B = V.slerpBasis(it.B, it.lieB, k)
        it.pos = V.lerp(it.pos, it.liePos, k)
        if k >= 1 then it.state = "rest"; it.settleT = nil end
        return
    end
    it.vel[2] = it.vel[2] - 9.81 * dt
    local step = V.scale(it.vel, dt)
    local len = V.len(step)
    if len > 1e-6 then
        local dir = V.scale(step, 1 / len)
        local t, n = L.raycast(it.pos, dir, len + r)
        if t then
            local hitP = V.madd(it.pos, dir, math.max(0, t - r))
            if n[2] > 0.6 and V.len(it.vel) < 2.2 then
                it.lieB = lieBasis(it)
                it.liePos = { hitP[1], hitP[2], hitP[3] }
                it.settleT = 0
                it.vel = { 0, 0, 0 }
                A.sound3D("sounds/drop.wav", hitP, 0.5, 0.9 + math.random() * 0.3)
            else
                local vn = V.dot(it.vel, n)
                it.vel = V.scale(V.madd(it.vel, n, -2 * vn), 0.35)
                it.angSpeed = it.angSpeed * 0.5
                it.pos = hitP
                if math.abs(vn) > 1 then A.sound3D("sounds/drop.wav", hitP, 0.6, 1.1) end
            end
        else
            it.pos = V.add(it.pos, step)
        end
    end
    if it.angSpeed > 1 then
        local R = V.axisAngle(it.angAxis, it.angSpeed * dt)
        it.B = V.mulMM(R, it.B)
        it.B = V.basis(it.B.f, it.B.u)
    end
    if it.pos[2] < -3 then it.lost = true end
end

---------------------------------------------------------------------------
-- Pegar / soltar
---------------------------------------------------------------------------
local function gpPalm(it, gpName, side)
    local gp = it.def.grabs[gpName]
    local c = P.get(gp.pose, side)
    return V.poseApply(it.pos, it.B, V.add(gp.at, c.palm))
end

local function other(side) return side == "left" and "right" or "left" end

local function pouchPoints()
    return {
        left = G.rig.bodyPoint(-0.2, -0.62, 0.04),
        right = G.rig.bodyPoint(0.2, -0.62, 0.04),
        chest = G.rig.bodyPoint(0, -0.38, 0.12),
    }
end
I.pouchPoints = pouchPoints

local function tryGrab(side, h)
    local best, bestD, bestGp = nil, 1e9, nil
    local otherHold = I.holding[other(side)]
    for _, it in ipairs(I.list) do
        if not it.dead then
            for gpName, gp in pairs(it.def.grabs) do
                if it.holders[gpName] == nil and not (gpName == "fore" and it.holders.grip == nil and isHeld(it)) then
                    local d = V.dist(gpPalm(it, gpName, side), h.palm)
                    local lim = gp.r
                    if it.state ~= "rest" and not isHeld(it) then lim = lim * 1.4 end
                    if d < lim then
                        local score = d - (gp.main and 0.02 or 0)
                        if score < bestD then best, bestD, bestGp = it, score, gpName end
                    end
                end
            end
            -- puxar o pente de uma arma segurada pela outra mao
            if it.def.kind == "gun" and it.magCount ~= nil and otherHold and otherHold.item == it then
                local d = V.dist(Wp.magWellPos(it), h.palm)
                if d < 0.07 and d < bestD then best, bestD, bestGp = it, d, "magwell" end
            end
        end
    end

    if best and bestGp == "magwell" then
        local count = best.magCount
        best.magCount = nil
        Wp.refreshMagVisual(best)
        Wp.updateDisplay(best)
        local mag = I.spawn("mag", Wp.magWellPos(best), best.B, { gunType = best.type, count = count })
        mag.holders.grip = side
        I.holding[side] = { item = mag, gp = "grip" }
        A.sound3D("sounds/mag_out.wav", h.palm, 0.9)
        return true
    end

    -- bolsa de pentes no quadril
    if not best then
        local pts = pouchPoints()
        local near = V.dist(pts.left, h.palm) < 0.17 or V.dist(pts.right, h.palm) < 0.17
        if near then
            local gunType = I.lastGunType
            if otherHold and otherHold.item and otherHold.item.def.kind == "gun" then gunType = otherHold.item.type end
            if gunType ~= "bat" then
                local mag = I.spawn("mag", h.palm, h.basis, { gunType = gunType, count = Wp.defs[gunType].magSize })
                mag.holders.grip = side
                I.holding[side] = { item = mag, gp = "grip" }
                A.sound3D("sounds/pouch.wav", h.palm, 0.8)
                return true
            end
        end
    end

    if best then
        best.holders[bestGp] = side
        best.state = "held"
        best.settleT = nil
        I.holding[side] = { item = best, gp = bestGp }
        if best.def.kind == "gun" then I.lastGunType = best.type end
        A.sound3D("sounds/grab.wav", h.palm, 0.7)
        return true
    end

    -- props com fisica (caixas, barris) e crab no rosto
    if G.bots then
        local crab = G.bots.tryGrabCrab(side, h.palm)
        if crab then I.holding[side] = { crab = crab }; return true end
    end
    if G.props then
        local p = G.props.tryGrab(side, h)
        if p then I.holding[side] = { prop = p }; return true end
    end
    return false
end

local function release(side, h)
    local hold = I.holding[side]
    I.holding[side] = nil
    if not hold then return end
    if hold.item then
        local it = hold.item
        it.holders[hold.gp] = nil
        if not isHeld(it) then
            local v = V.scale(h.palmVel, 1.15)
            if V.len(v) > 12 then v = V.scale(V.norm(v), 12) end
            I.drop(it, v)
        end
    elseif hold.prop and G.props then
        G.props.release(hold.prop, h.palmVel)
    elseif hold.crab and G.bots then
        G.bots.releaseCrab(hold.crab, h.palmVel)
    end
end

---------------------------------------------------------------------------
-- Pose do item segurado
---------------------------------------------------------------------------
local function minimalRotation(a, b)
    local axis = V.cross(a, b)
    local s = V.len(axis)
    local c = V.dot(a, b)
    if s < 1e-6 then return V.identity() end
    return V.axisAngle(V.scale(axis, 1 / s), math.atan(s, c) * V.DEG)
end

local function heldTarget(it)
    local C = G.controls
    local mainGp = it.holders.grip and "grip" or "fore"
    local mainSide = it.holders[mainGp]
    local hm = C.hands[mainSide]
    local gp = it.def.grabs[mainGp]
    local poseO, R = P.objectFromHand(hm.palm, hm.basis, gp.pose, mainSide)
    local pos = V.sub(poseO, V.mulMV(R, gp.at))
    -- duas maos: o cano aponta da mao principal para a de apoio
    if it.holders.grip and it.holders.fore then
        local sSide = it.holders.fore
        local hs = C.hands[sSide]
        local mPalm = V.add(it.def.grabs.grip.at, P.get(it.def.grabs.grip.pose, mainSide).palm)
        local sPalm = V.add(it.def.grabs.fore.at, P.get(it.def.grabs.fore.pose, sSide).palm)
        local vObj = V.norm(V.sub(sPalm, mPalm))
        local vW = V.sub(hs.palm, hm.palm)
        if V.len(vW) > 0.08 then
            local Rf = minimalRotation(V.mulMV(R, vObj), V.norm(vW))
            R = V.mulMM(Rf, R)
            R = V.basis(R.f, R.u)
            pos = V.sub(hm.palm, V.mulMV(R, mPalm))
        end
    end
    return pos, R
end

local function posedHand(it, gpName, side, rPos, rB)
    local gp = it.def.grabs[gpName]
    local pts
    if gp.pose == "pistol" then
        pts = P.pistolBlend(side, trigSmooth[side])
    else
        pts = P.get(gp.pose, side).pts
    end
    local origin = V.poseApply(rPos, rB, gp.at)
    I.handPose[side] = P.toWorld(pts, origin, rB, I.handPose[side])
end

---------------------------------------------------------------------------
-- Mesa de armas (dispensador)
---------------------------------------------------------------------------
local function lyingOnTable(x, gunLen)
    local t = G.level.tableTop
    local B = { r = { 0, 1, 0 }, u = { -1, 0, 0 }, f = { 0, 0, 1 } }
    return { t[1] + x, t[2] + 0.016, t[3] - gunLen * 0.25 }, B
end

function I.setupTable()
    local defs = {
        { "pistol", -0.62, 0.15, 0.016 },
        { "smg", -0.2, 0.35, 0.022 },
        { "shotgun", 0.25, 0.6, 0.024 },
    }
    for _, d in ipairs(defs) do
        local pos, B = lyingOnTable(d[2], d[3])
        pos[2] = G.level.tableTop[2] + d[4]
        I.slots[#I.slots + 1] = { type = d[1], pos = pos, B = B }
    end
    -- taco deitado ao longo da mesa
    local t = G.level.tableTop
    I.slots[#I.slots + 1] = {
        type = "bat", pos = { t[1] + 0.58, t[2] + 0.04, t[3] - 0.12 },
        B = { r = { 0, 1, 0 }, u = { 0, 0, 1 }, f = { -1, 0, 0 } },
    }
    for _, s in ipairs(I.slots) do
        s.item = I.spawn(s.type, s.pos, s.B, { rest = true })
        s.away = 0
    end
end

local function updateSlots(dt)
    for _, s in ipairs(I.slots) do
        local it = s.item
        local gone = it == nil or it.dead or isHeld(it) or V.dist(it.pos, s.pos) > 0.4
        if gone then s.away = s.away + dt else s.away = 0 end
        if s.away > 5 and (it == nil or it.dead or not isHeld(it)) then
            -- tira o antigo se estiver largado longe
            if it and not it.dead and not isHeld(it) then I.destroy(it) end
            s.item = I.spawn(s.type, s.pos, s.B, { rest = true })
            s.away = 0
            G.fx.sparks(s.pos, 6, { 0, 1, 0 }, { 0.3, 0.8, 1 }, 1.2)
            A.sound3D("sounds/respawn.wav", s.pos, 0.6)
        elseif it and isHeld(it) then
            -- a arma esta na mao: quando sair da mesa, poe outra no lugar
            if s.away > 6 then
                s.item = I.spawn(s.type, s.pos, s.B, { rest = true })
                s.away = 0
                A.sound3D("sounds/respawn.wav", s.pos, 0.6)
            end
        end
    end
end

-- limpa pentes e armas largadas demais
local function cleanup()
    local mags, guns = {}, {}
    for _, it in ipairs(I.list) do
        if not isHeld(it) and not it.dead then
            local inSlot = false
            for _, s in ipairs(I.slots) do if s.item == it then inSlot = true end end
            if not inSlot then
                if it.def.kind == "mag" then mags[#mags + 1] = it else guns[#guns + 1] = it end
            end
        end
    end
    for _, it in ipairs(mags) do
        if (it.count or 0) == 0 and G.time - it.born > 6 and it.state == "rest" then I.destroy(it)
        elseif G.time - it.born > 40 then I.destroy(it) end
    end
    if #mags > 10 then I.destroy(mags[1]) end
    if #guns > 8 then I.destroy(guns[1]) end
    for _, it in ipairs(I.list) do
        if it.lost then I.destroy(it); break end
    end
end

---------------------------------------------------------------------------
-- Visual das bolsas no quadril
---------------------------------------------------------------------------
local pouchObjs = {}
local function makePouches()
    for _, k in ipairs({ "left", "right" }) do
        local root = A.empty("pouch_" .. k, G.rig.world)
        A.prim("cube", { parent = root, scale = { 0.07, 0.1, 0.05 }, color = { 0.12, 0.12, 0.14 }, mat = { smooth = 0.3 } })
        A.prim("cube", { parent = root, pos = { 0, 0.045, 0.0 }, scale = { 0.075, 0.025, 0.056 }, color = { 1, 0.45, 0.08 }, mat = { emit = { 0.6, 0.2, 0.02 } } })
        A.prim("capsule", { parent = root, pos = { 0, 0.07, 0 }, scale = { 0.012, 0.012, 0.012 }, color = { 0.85, 0.65, 0.2 }, mat = { metal = 0.9, smooth = 0.8 } })
        pouchObjs[k] = root
    end
    -- cinto
    local belt = A.empty("belt", G.rig.world)
    A.prim("cylinder", { parent = belt, scale = { 0.36, 0.025, 0.24 }, color = { 0.09, 0.09, 0.1 }, mat = { smooth = 0.3 } })
    pouchObjs.belt = belt
end

local function updatePouches(dt)
    local pts = pouchPoints()
    local yawB = V.basisFromEuler(0, G.rig.bodyYaw, 0)
    for _, k in ipairs({ "left", "right" }) do
        A.pos(pouchObjs[k], pts[k])
        A.rotBasis(pouchObjs[k], yawB)
    end
    A.pos(pouchObjs.belt, G.rig.bodyPoint(0, -0.66, -0.02))
    A.rotBasis(pouchObjs.belt, yawB)
end

---------------------------------------------------------------------------
-- Update principal
---------------------------------------------------------------------------
local cleanT = 0

function I.update(dt)
    local C = G.controls
    -- 1) pegar / soltar
    for _, side in ipairs({ "left", "right" }) do
        local h = C.hands[side]
        local hold = I.holding[side]
        if hold then
            if h.gripUp or not h.tracked then release(side, h) end
        elseif h.tracked then
            -- janela de 0.3 s: apertar "pegar" um pouco antes de encostar tambem pega
            if h.gripDown then h.grabWindow = 0.3 end
            if h.grip and (h.grabWindow or 0) > 0 then
                h.grabWindow = h.grabWindow - dt
                if tryGrab(side, h) then h.grabWindow = 0 end
            end
        end
        h.busy = I.holding[side] ~= nil
        -- gatilho suavizado para animar o indicador
        local target = h.usingPad and (h.trigHeld and 1 or 0) or V.clamp((h.curl[2] - 0.2) / 0.6, 0, 1)
        trigSmooth[side] = trigSmooth[side] + (target - trigSmooth[side]) * V.smoothK(30, dt)
        I.posed[side] = false
    end

    -- 2) itens
    for _, it in ipairs(I.list) do
        if not it.dead then
            if isHeld(it) then
                local pos, R = heldTarget(it)
                if it.prevHeld ~= true then
                    it.pos, it.B = pos, R
                else
                    it.pos = V.lerp(it.pos, pos, V.smoothK(45, dt))
                    it.B = V.slerpBasis(it.B, R, V.smoothK(32, dt))
                end
                it.prevHeld = true
                -- velocidade (para arremesso e para quem precisa)
                local mainSide = it.holders.grip or it.holders.fore
                it.vel = C.hands[mainSide].palmVel

                if it.def.kind == "gun" and it.holders.grip then
                    local fore = it.holders.fore and C.hands[it.holders.fore] or nil
                    Wp.updateHeld(it, dt, C.hands[it.holders.grip], fore)
                elseif it.def.kind == "melee" then
                    Wp.updateMelee(it, dt)
                end

                local rPos, rB = Wp.recoilPose(it, it.pos, it.B)
                I.place(it, rPos, rB)
                Wp.animate(it, it.holders.grip and trigSmooth[it.holders.grip] or 0)
                for gpName, side in pairs(it.holders) do
                    posedHand(it, gpName, side, rPos, rB)
                    I.posed[side] = true
                end

                -- pente segurado perto do encaixe de uma arma vazia
                if it.def.kind == "mag" then
                    local top = V.poseApply(it.pos, it.B, { 0, 0.03, 0 })
                    for _, g in ipairs(I.list) do
                        if g.def.kind == "gun" and g.type == it.gunType and g.magCount == nil and not g.dead then
                            if V.dist(top, Wp.magWellPos(g)) < 0.075 then
                                Wp.insertMag(g, it)
                                I.destroy(it)
                                break
                            end
                        end
                    end
                end
            else
                it.prevHeld = false
                if it.state == "falling" then
                    physics(it, dt)
                    I.place(it, it.pos, it.B)
                    if it.def.kind == "gun" then Wp.animate(it, 0) end
                end
            end
        end
    end

    for _, side in ipairs({ "left", "right" }) do
        if not I.posed[side] then I.handPose[side] = nil end
    end

    updateSlots(dt)
    updatePouches(dt)
    cleanT = cleanT + dt
    if cleanT > 1 then cleanT = 0; cleanup() end
end

-- Arma (item) segurada pelo cabo nesta mao, se houver
function I.gunIn(side)
    local h = I.holding[side]
    if h and h.item and h.gp == "grip" and h.item.def.kind == "gun" then return h.item end
    return nil
end

function I.releaseAll()
    for _, side in ipairs({ "left", "right" }) do
        if I.holding[side] then release(side, G.controls.hands[side]) end
    end
end

function I.init(ctx)
    G = ctx
    makePouches()
end

return I
