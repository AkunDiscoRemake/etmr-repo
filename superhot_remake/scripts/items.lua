-- items.lua — objetos do SUPERHOT (armas, katana, garrafa, cinzeiro, telefone).
--  * pegar perto, PUXAR A DISTANCIA (palma apontada) e ARRANCAR da mao do inimigo
--  * arremesso forte; o objeto voa no TEMPO DO JOGO (fica parado no ar se voce parar)
--  * objeto voando que acerta inimigo = desarma/derruba; garrafa quebra
--  * segurar uma arma/objeto na frente BLOQUEIA balas
--  * a mao fake encaixa no objeto e o indicador acompanha o gatilho

local V = require("vec")
local A = require("api")
local P = require("poses")
local Wp = require("weapons")

local I = {}
local G

I.list = {}
I.holding = { left = nil, right = nil }
I.handPose = { left = nil, right = nil }
I.posed = { left = false, right = false }

local trigSmooth = { left = 0, right = 0 }

function I.spawn(type, pos, B, opt)
    opt = opt or {}
    local it = {
        type = type, def = Wp.defs[type], pos = V.copy(pos), B = B or V.identity(),
        state = opt.held == "enemy" and "enemy" or (opt.rest and "rest" or "falling"),
        vel = { 0, 0, 0 }, angAxis = { 1, 0, 0 }, angSpeed = 0, holders = {}, ammo = opt.ammo,
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

local function isHeld(it) return it.holders.grip ~= nil or it.holders.fore ~= nil end
I.isHeld = isHeld

function I.drop(it, vel)
    it.state = "falling"
    it.vel = V.copy(vel or { 0, 0, 0 })
    it.angAxis = V.norm({ math.random() - 0.5, math.random() - 0.5, math.random() - 0.5 })
    it.angSpeed = 120 + V.len(it.vel) * 180
    it.settleT = nil
    it.hitDone = false
end

---------------------------------------------------------------------------
-- Fisica (tempo do jogo)
---------------------------------------------------------------------------
local function lieBasis(it)
    local Bm = it.B
    local up = { 0, Bm.r[2] >= 0 and 1 or -1, 0 }
    if it.def.kind == "gun" then
        local f = { Bm.f[1], 0, Bm.f[3] }
        if V.len2(f) < 1e-4 then f = { 0, 0, 1 } end
        f = V.norm(f)
        return { r = up, u = V.cross(f, up), f = f }
    end
    local u = { Bm.u[1], 0, Bm.u[3] }
    if V.len2(u) < 1e-4 then u = { 1, 0, 0 } end
    u = V.norm(u)
    return { r = up, u = u, f = V.cross(up, u) }
end

local function breakBottle(it, p)
    G.fx.shatter({ p, V.add(p, { 0, 0.05, 0 }) }, V.norm(it.vel), 1.5, 14, "glass")
    G.sound3D("sounds/glass.wav", p, 1)
    I.destroy(it)
end

local function physics(it, gdt)
    local r = it.def.restR
    if it.settleT then
        it.settleT = it.settleT + gdt
        local k = math.min(1, it.settleT / 0.15)
        it.B = V.slerpBasis(it.B, it.lieB, k)
        it.pos = V.lerp(it.pos, it.liePos, k)
        if k >= 1 then it.state = "rest"; it.settleT = nil end
        return
    end
    it.vel[2] = it.vel[2] - 9.81 * gdt
    local step = V.scale(it.vel, gdt)
    local len = V.len(step)
    local speed = V.len(it.vel)
    -- bate em inimigo?
    if not it.hitDone and speed > 1.8 then
        if G.enemies.itemHit(it, it.pos, it.def.hitR or 0.08, it.vel) then
            it.hitDone = true
            if it.def.breaks then breakBottle(it, it.pos); return end
            it.vel = V.add(V.scale(it.vel, -0.25), { 0, 1, 0 })
        end
    end
    if len > 1e-6 then
        local dir = V.scale(step, 1 / len)
        local t, n = G.level.raycast(it.pos, dir, len + r)
        if t then
            local hitP = V.madd(it.pos, dir, math.max(0, t - r))
            if it.def.breaks and speed > 3 then breakBottle(it, hitP); return end
            if n[2] > 0.6 and speed < 2.4 then
                it.lieB = lieBasis(it)
                it.liePos = hitP
                it.settleT = 0
                it.vel = { 0, 0, 0 }
                G.sound3D("sounds/drop.wav", hitP, 0.5)
            else
                local vn = V.dot(it.vel, n)
                it.vel = V.scale(V.madd(it.vel, n, -2 * vn), 0.35)
                it.angSpeed = it.angSpeed * 0.5
                it.pos = hitP
                if math.abs(vn) > 1 then G.sound3D("sounds/drop.wav", hitP, 0.6) end
            end
        else
            it.pos = V.add(it.pos, step)
        end
    end
    if it.angSpeed > 1 then
        it.B = V.mulMM(V.axisAngle(it.angAxis, it.angSpeed * gdt), it.B)
        it.B = V.basis(it.B.f, it.B.u)
    end
    if it.pos[2] < -3 then it.lost = true end
end

-- objeto voando perto de p (para bloquear balas)
function I.sphereAt(p, r)
    for _, it in ipairs(I.list) do
        if not it.dead and it.state == "falling" and V.len(it.vel) > 0.5 then
            if V.dist(it.pos, p) < r + (it.def.hitR or 0.06) then return it end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Pegar / soltar
---------------------------------------------------------------------------
local function gpPalm(it, gpName, side)
    local gp = it.def.grabs[gpName]
    local c = P.get(gp.pose, side)
    return V.poseApply(it.pos, it.B, V.add(gp.at, c.palm))
end

local function startHold(it, gpName, side, dur)
    if it.enemy then G.enemies.snatch(it) end
    it.holders[gpName] = side
    it.state = "held"
    it.settleT = nil
    it.grabFrom = { pos = V.copy(it.pos), B = it.B }
    it.grabT, it.grabDur = 0, dur or 0.08
    I.holding[side] = { item = it, gp = gpName }
end

local function tryGrab(side, h)
    local best, bestD, bestGp = nil, 1e9, nil
    for _, it in ipairs(I.list) do
        if not it.dead then
            for gpName, gp in pairs(it.def.grabs) do
                if it.holders[gpName] == nil and not (gpName == "fore" and it.holders.grip == nil and isHeld(it)) then
                    local d = V.dist(gpPalm(it, gpName, side), h.palm)
                    local lim = gp.r
                    if it.state == "falling" or it.state == "enemy" then lim = lim * 1.5 end
                    if d < lim then
                        local score = d - (gp.main and 0.02 or 0)
                        if score < bestD then best, bestD, bestGp = it, score, gpName end
                    end
                end
            end
        end
    end
    if best then
        startHold(best, bestGp, side, 0.08)
        G.sound3D("sounds/grab.wav", h.palm, 0.7)
        return true
    end
    -- puxar a distancia (mao fechada inteira ou Joy-Con)
    if h.usingPad or h.curl[2] > 0.4 then
        local palmar = side == "right" and V.scale(h.basis.r, -1) or h.basis.r
        local fbest, fscore = nil, math.cos(18 * V.RAD)
        for _, it in ipairs(I.list) do
            if not it.dead and not isHeld(it) and it.state ~= "enemy" then
                local v = V.sub(it.pos, h.palm)
                local d = V.len(v)
                if d > 0.15 and d < 3.5 then
                    local score = V.dot(V.scale(v, 1 / d), palmar) - d * 0.01
                    if score > fscore then fbest, fscore = it, score end
                end
            end
        end
        if fbest then
            startHold(fbest, "grip", side, 0.3)
            G.sound3D("sounds/swing.wav", fbest.pos, 0.5)
            G.sound3D("sounds/grab.wav", h.palm, 0.7)
            return true
        end
    end
    return false
end

local function release(side, h)
    local hold = I.holding[side]
    I.holding[side] = nil
    if not hold or not hold.item then return end
    local it = hold.item
    it.holders[hold.gp] = nil
    if not isHeld(it) then
        -- arremesso do SUPERHOT: forte e reto
        local v = V.scale(G.controls.throwVelocity(side), 1.6)
        local sp = V.len(v)
        if sp > 14 then v = V.scale(V.norm(v), 14) end
        I.drop(it, v)
        if sp > 2 then
            G.time.pulse(0.7, 0.15)
            G.sound3D("sounds/throw.wav", it.pos, 0.7)
        end
    end
end

---------------------------------------------------------------------------
-- Pose do item segurado
---------------------------------------------------------------------------
local function minimalRotation(a, b)
    local axis = V.cross(a, b)
    local s = V.len(axis)
    if s < 1e-6 then return V.identity() end
    return V.axisAngle(V.scale(axis, 1 / s), math.atan(s, V.dot(a, b)) * V.DEG)
end

local function heldTarget(it)
    local C = G.controls
    local mainGp = it.holders.grip and "grip" or "fore"
    local mainSide = it.holders[mainGp]
    local hm = C.hands[mainSide]
    local gp = it.def.grabs[mainGp]
    local poseO, R = P.objectFromHand(hm.palm, hm.basis, gp.pose, mainSide)
    local pos = V.sub(poseO, V.mulMV(R, gp.at))
    if it.holders.grip and it.holders.fore then
        local sSide = it.holders.fore
        local hs = C.hands[sSide]
        local mPalm = V.add(it.def.grabs.grip.at, P.get(it.def.grabs.grip.pose, mainSide).palm)
        local sPalm = V.add(it.def.grabs.fore.at, P.get(it.def.grabs.fore.pose, sSide).palm)
        local vObj = V.norm(V.sub(sPalm, mPalm))
        local vW = V.sub(hs.palm, hm.palm)
        if V.len(vW) > 0.08 then
            R = V.mulMM(minimalRotation(V.mulMV(R, vObj), V.norm(vW)), R)
            R = V.basis(R.f, R.u)
            pos = V.sub(hm.palm, V.mulMV(R, mPalm))
        end
    end
    return pos, R
end

local function posedHand(it, gpName, side, rPos, rB)
    local gp = it.def.grabs[gpName]
    local pts
    if gp.pose == "pistol" then pts = P.pistolBlend(side, trigSmooth[side]) else pts = P.get(gp.pose, side).pts end
    I.handPose[side] = P.toWorld(pts, V.poseApply(rPos, rB, gp.at), rB, I.handPose[side])
end

---------------------------------------------------------------------------
function I.update(dt, gdt)
    local C = G.controls
    for _, side in ipairs({ "left", "right" }) do
        local h = C.hands[side]
        local hold = I.holding[side]
        if hold then
            if hold.item and hold.item.dead then I.holding[side] = nil
            elseif h.gripUp then release(side, h) end
        elseif h.tracked then
            if h.gripDown then h.grabWindow = 0.45 end
            if h.grip and (h.grabWindow or 0) > 0 then
                h.grabWindow = h.grabWindow - dt
                if tryGrab(side, h) then h.grabWindow = 0 end
            end
        end
        h.busy = I.holding[side] ~= nil
        local target = h.usingPad and (h.trigHeld and 1 or 0) or V.clamp((h.curl[2] - 0.2) / 0.6, 0, 1)
        trigSmooth[side] = trigSmooth[side] + (target - trigSmooth[side]) * V.smoothK(30, dt)
        I.posed[side] = false
    end

    local i = 1
    while i <= #I.list do
        local it = I.list[i]
        if not it.dead then
            if isHeld(it) then
                local pos, R = heldTarget(it)
                if it.grabFrom then
                    it.grabT = it.grabT + dt
                    local k = math.min(1, it.grabT / it.grabDur)
                    k = k * k * (3 - 2 * k)
                    local arc = it.grabDur > 0.2 and math.sin(k * math.pi) * 0.15 or 0
                    it.pos = V.add(V.lerp(it.grabFrom.pos, pos, k), { 0, arc, 0 })
                    it.B = V.slerpBasis(it.grabFrom.B, R, k)
                    if k >= 1 then it.grabFrom = nil end
                else
                    it.pos = V.lerp(it.pos, pos, V.smoothK(45, dt))
                    it.B = V.slerpBasis(it.B, R, V.smoothK(32, dt))
                end
                local mainSide = it.holders.grip or it.holders.fore
                it.vel = C.hands[mainSide].palmVel
                if it.def.kind == "gun" and it.holders.grip then
                    Wp.updateHeld(it, dt, gdt, C.hands[it.holders.grip])
                elseif it.def.kind == "melee" then
                    Wp.updateMelee(it, dt)
                end
                if it.def.kind ~= "melee" then G.bullets.blockSphere(it.pos, 0.07) end
                local rPos, rB = Wp.recoilPose(it, it.pos, it.B)
                I.place(it, rPos, rB)
                Wp.animate(it, it.holders.grip and trigSmooth[it.holders.grip] or 0)
                for gpName, side in pairs(it.holders) do
                    posedHand(it, gpName, side, rPos, rB)
                    I.posed[side] = true
                end
            elseif it.state == "falling" then
                physics(it, gdt)
                if not it.dead then
                    I.place(it, it.pos, it.B)
                    if it.def.kind == "gun" then Wp.animate(it, 0) end
                end
            end
        end
        if it.lost then I.destroy(it) end
        if I.list[i] == it then i = i + 1 end
    end
    for _, side in ipairs({ "left", "right" }) do
        if not I.posed[side] then I.handPose[side] = nil end
    end
end

function I.releaseAll()
    for _, side in ipairs({ "left", "right" }) do
        local hold = I.holding[side]
        if hold and hold.item then
            hold.item.holders[hold.gp] = nil
            if not isHeld(hold.item) then I.drop(hold.item, { 0, 0, 0 }) end
        end
        I.holding[side] = nil
    end
end

function I.clear()
    I.holding = { left = nil, right = nil }
    for _, it in ipairs(I.list) do
        it.dead = true
        A.destroy(it.root)
    end
    I.list = {}
end

function I.init(ctx) G = ctx end

return I
