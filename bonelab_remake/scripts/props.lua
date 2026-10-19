-- props.lua — objetos com fisica REAL da Unity (Rigidbody): caixas e barris explosivos.
-- Da para empurrar com as maos, atirar (impulso), pegar e arremessar (se a plataforma
-- liberar Rigidbody.isKinematic), e os barris vermelhos explodem.

local V = require("vec")
local A = require("api")

local Pr = {}
local G

Pr.list = {}

local KINDS = {
    crate = { size = 0.55, mass = 10, tex = "images/crate.png", color = { 1, 1, 1 }, r = 0.33, grab = false },
    box = { size = 0.3, mass = 2, tex = "images/crate_small.png", color = { 1, 1, 1 }, r = 0.19, grab = true },
    barrel = { size = 0.55, mass = 6, tex = "images/barrel.png", color = { 1, 1, 1 }, r = 0.36, grab = true, explosive = true, hp = 2 },
}

local function build(p)
    local k = KINDS[p.kind]
    local o
    if p.kind == "barrel" then
        o = A.prim("cylinder", { parent = G.rig.world, pos = p.home, scale = { 0.55, 0.45, 0.55 }, color = k.color, tex = k.tex, mat = { metal = 0.5, smooth = 0.55 } })
        A.boxCollider(o)
    else
        o = A.prim("cube", { parent = G.rig.world, pos = p.home, scale = { k.size, k.size, k.size }, color = k.color, tex = k.tex, mat = { metal = 0.1, smooth = 0.35 } })
        A.boxCollider(o)
    end
    A.rot(o, 0, p.yaw or 0, 0)
    p.obj = o
    p.rb = A.addBody(o, k.mass, true)
    p.pos = V.copy(p.home)
    p.hp = k.hp or 1
    p.dead = false
end

function Pr.add(kind, pos, yaw)
    local p = { kind = kind, home = V.copy(pos), yaw = yaw, def = KINDS[kind] }
    build(p)
    Pr.list[#Pr.list + 1] = p
    return p
end

function Pr.setup()
    -- pilhas de caixas
    for _, c in ipairs({ { -7.5, 7.5 }, { 7.6, -6.5 }, { -3.2, 8.4 } }) do
        Pr.add("crate", { c[1], 0.28, c[2] }, math.random() * 20)
        Pr.add("crate", { c[1] + 0.6, 0.28, c[2] + 0.1 }, math.random() * 20)
        Pr.add("crate", { c[1] + 0.3, 0.84, c[2] + 0.05 }, math.random() * 20)
    end
    for _, c in ipairs({ { 1.4, -6.6 }, { -1.5, -6.4 }, { 3, 2 }, { -3, 2.5 } }) do
        Pr.add("box", { c[1], 0.16, c[2] }, math.random() * 45)
    end
    for _, c in ipairs({ { -6.5, -2.5 }, { 6.6, 5.6 }, { 1.6, 6.2 }, { -9.5, 4.5 }, { 9.4, -3.8 } }) do
        Pr.add("barrel", { c[1], 0.46, c[2] }, 0)
    end
end

local frameToggle = 0
local function refreshPositions()
    for _, p in ipairs(Pr.list) do
        if not p.dead and not p.held then
            p.pos = A.readPos(p.obj)
            if p.pos[2] < -3 then
                -- caiu do mundo: volta pra casa
                A.destroy(p.obj)
                build(p)
            end
        end
    end
end

function Pr.raycast(o, d, maxT)
    local best, bp = maxT, nil
    for _, p in ipairs(Pr.list) do
        if not p.dead then
            local t = V.raySphere(o, d, p.pos, p.def.r * 0.9)
            if t and t < best then best, bp = t, p end
        end
    end
    if bp then return best, bp end
end

function Pr.hit(p, dir, force, dmg, kind)
    if p.dead then return end
    local w = G.rig.dirToWorld(V.scale(dir, force))
    A.addImpulse(p.rb, w[1], w[2], w[3])
    if p.def.explosive then
        p.hp = p.hp - 1
        if p.hp <= 0 or kind == "explosion" then
            Pr.explode(p)
        end
    end
end

function Pr.explode(p)
    if p.dead then return end
    p.dead = true
    if p.held then
        for side, h in pairs(G.items.holding) do
            if h and h.prop == p then G.items.holding[side] = nil end
        end
    end
    local c = V.copy(p.pos)
    A.destroy(p.obj)
    p.obj = nil
    -- o resto da explosao vem um tiquinho depois (reacao em cadeia fica bonita)
    EMRAPI.Timer:Delay(0.05, function() G.combat.explode(c, 3.6, 120) end)
    EMRAPI.Timer:Delay(18, function()
        if G.mode ~= "off" then build(p) end
    end)
end

-- impulso radial (explosoes)
function Pr.blast(c, radius, force)
    for _, p in ipairs(Pr.list) do
        if not p.dead and not p.held then
            local d = V.sub(p.pos, c)
            local dist = V.len(d)
            if dist < radius then
                local k = 1 - dist / radius
                local dir = V.norm(V.add(d, { 0, 0.6, 0 }))
                if p.def.explosive and dist < radius * 0.7 then
                    p.hp = 0
                    EMRAPI.Timer:Delay(0.12 + math.random() * 0.15, function() Pr.explode(p) end)
                else
                    local w = G.rig.dirToWorld(V.scale(dir, force * k * p.def.mass))
                    A.addImpulse(p.rb, w[1], w[2], w[3])
                end
            end
        end
    end
end

function Pr.meleeSweep(a, b, r, vel)
    for _, p in ipairs(Pr.list) do
        if not p.dead and not p.held and V.pointSegDist(p.pos, a, b) < p.def.r + r then
            local w = G.rig.dirToWorld(V.scale(vel, p.def.mass * 0.25))
            A.addImpulse(p.rb, w[1], w[2], w[3])
            if p.def.explosive and V.len(vel) > 5 then Pr.hit(p, V.norm(vel), 0, 0, "melee") end
        end
    end
end

---------------------------------------------------------------------------
-- Pegar/arremessar (precisa de isKinematic)
---------------------------------------------------------------------------
function Pr.tryGrab(side, h)
    if not A.rbOk then return nil end
    for _, p in ipairs(Pr.list) do
        if not p.dead and not p.held and p.def.grab then
            if V.dist(p.pos, h.palm) < p.def.r + 0.1 then
                if A.setKinematic(p.rb, true) then
                    p.held = side
                    p.offset = V.mulTMV(h.basis, V.sub(p.pos, h.palm))
                    local pb = A.readBasis(p.obj)
                    p.relB = pb and V.mulMM(V.transpose(h.basis), pb) or nil
                    A.sound3D("sounds/grab.wav", h.palm, 0.7)
                    return p
                end
            end
        end
    end
    return nil
end

function Pr.release(p, vel)
    if p.dead then return end
    p.held = nil
    A.setKinematic(p.rb, false)
    local w = G.rig.dirToWorld(V.scale(vel, 1.1))
    A.setVelocity(p.rb, w[1], w[2], w[3])
end

function Pr.update(dt)
    frameToggle = frameToggle + 1
    if frameToggle % 2 == 0 then refreshPositions() end
    for _, p in ipairs(Pr.list) do
        if p.held and not p.dead then
            local h = G.controls.hands[p.held]
            p.pos = V.add(h.palm, V.mulMV(h.basis, p.offset))
            A.pos(p.obj, p.pos)
            if p.relB then A.rotBasis(p.obj, V.mulMM(h.basis, p.relB)) end
        end
    end
end

function Pr.init(ctx)
    G = ctx
end

return Pr
