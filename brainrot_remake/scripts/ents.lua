-- ents.lua — personagens: o jogador local e os jogadores remotos (online).
-- Todos tem avatar Roblox, podem carregar um brainrot acima da cabeca, levar
-- pancada (atordoado + empurrao) e segurar itens.

local V = require("vec")
local A = require("api")
local K = require("catalog")
local M = require("models")
local AV = require("avatars")
local Lt = require("layout")

local E = {}

E.list = {}
E.order = {}
local G

function E.init(ctx)
    G = ctx
    E.root = A.empty("ents", G.rig.world)
end

local function add(ent)
    E.list[ent.id] = ent
    E.order[#E.order + 1] = ent
    return ent
end

local function newEnt(id, name, kind, avKind, outfit, base)
    local ent = {
        id = id, name = name, kind = kind, auth = kind ~= "remote", avKind = avKind or "bacon", outfit = outfit or 1,
        base = base, pos = { 0, 0, 0 }, yaw = 0, speed = 0, vel = { 0, 0, 0 }, anim = "idle",
        carry = nil, stunT = 0, swing = 0, item = "bat", invisT = 0, knock = { 0, 0, 0 }, y = 0,
    }
    ent.av = AV.new({ kind = ent.avKind, outfit = ent.outfit, name = kind ~= "local" and name or nil, parent = E.root, isLocal = kind == "local" })
    ent.tool = E.makeTool(ent.av.handR, "bat")
    return ent
end

function E.spawnLocal(id, name, avKind, outfit, base)
    return add(newEnt(id, name, "local", avKind, outfit, base))
end
function E.spawnRemote(id, name, avKind, outfit, base)
    local e = newEnt(id, name, "remote", avKind, outfit, base)
    e.target = nil
    return add(e)
end

function E.remove(id)
    local ent = E.list[id]
    if not ent then return end
    E.clearCarry(ent)
    AV.destroy(ent.av)
    E.list[id] = nil
    for i, e in ipairs(E.order) do
        if e == ent then table.remove(E.order, i); break end
    end
end

function E.get(id) return E.list[id] end

---------------------------------------------------------------------------
-- Itens na mao do avatar (taco etc.)
---------------------------------------------------------------------------
function E.makeTool(parent, item)
    local root = A.empty("tool", parent)
    A.rot(root, 90, 0, 0)
    local parts = {}
    local function p(kind, pos, sc, col, mat)
        parts[#parts + 1] = A.prim(kind, { parent = root, pos = pos, scale = sc, color = col, mat = mat })
    end
    if item == "bat" then
        p("cylinder", { 0, 0.32, 0 }, { 0.07, 0.36, 0.07 }, { 0.72, 0.5, 0.28 })
        p("cylinder", { 0, -0.02, 0 }, { 0.045, 0.06, 0.045 }, { 0.15, 0.15, 0.15 })
    elseif item == "slap" then
        p("cube", { 0, 0.12, 0 }, { 0.2, 0.24, 0.08 }, { 1, 0.85, 0.3 })
        p("cube", { 0, 0.0, 0 }, { 0.12, 0.08, 0.1 }, { 0.9, 0.2, 0.2 })
    elseif item == "coil" then
        for k = 0, 4 do p("cylinder", { 0, 0.04 + k * 0.05, 0 }, { 0.12, 0.012, 0.12 }, { 0.3, 0.6, 1.0 }, { emit = { 0.2, 0.5, 1.2 } }) end
    elseif item == "trap" then
        p("cylinder", { 0, 0.05, 0 }, { 0.22, 0.02, 0.22 }, { 0.5, 0.5, 0.55 }, { metal = 0.8 })
        p("cube", { 0, 0.08, 0 }, { 0.2, 0.04, 0.04 }, { 0.3, 0.3, 0.32 })
    elseif item == "cloak" then
        p("cube", { 0, 0.1, 0 }, { 0.22, 0.26, 0.04 }, { 0.35, 0.2, 0.6 }, { emit = { 0.2, 0.1, 0.4 } })
    end
    return { root = root, item = item, parts = parts }
end

function E.setItem(ent, item)
    if ent.item == item and ent.tool then return end
    ent.item = item
    if ent.tool then A.destroy(ent.tool.root) end
    ent.tool = item and E.makeTool(ent.av.handR, item) or nil
end

---------------------------------------------------------------------------
-- Carregar brainrot
---------------------------------------------------------------------------
function E.setCarry(ent, b, s, id, mut)
    E.clearCarry(ent)
    local d = K.byId[id]
    if not d then return end
    local inst = M.build(d, ent.av.carryPoint, mut)
    A.posXYZ(inst.root, 0, 0, 0)
    ent.carry = { b = b, s = s, id = id, mut = mut, inst = inst }
end

function E.clearCarry(ent)
    if ent.carry then
        if ent.carry.inst then M.destroy(ent.carry.inst) end
        ent.carry = nil
    end
end

---------------------------------------------------------------------------
-- Pancada
---------------------------------------------------------------------------
-- dir = direcao do empurrao (xz), pow = forca (m de empurrao), stun = s
function E.applyHit(ent, dir, pow, stun)
    ent.stunT = math.max(ent.stunT, stun or 1.6)
    local d = V.norm({ dir[1], 0, dir[3] })
    ent.knock = V.scale(d, (pow or 3) * 3.2)
    ent.y = 0.01
    ent.vy = 3.2
    if G.fx then G.fx.hit(V.add(ent.pos, { 0, 1.3, 0 })) end
end

---------------------------------------------------------------------------
-- Pose (rede)
---------------------------------------------------------------------------
function E.pose(ent)
    local c = ent.carry
    return {
        id = ent.id, n = ent.name, av = ent.avKind, of = ent.outfit, b = ent.base,
        p = { math.floor(ent.pos[1] * 100) / 100, math.floor((ent.y or 0) * 100) / 100, math.floor(ent.pos[3] * 100) / 100 },
        y = math.floor(ent.yaw), sp = math.floor(ent.speed * 10) / 10, a = ent.anim,
        c = c and { c.id, c.mut, c.b, c.s } or nil, it = ent.item, sw = ent.swing > 0 and 1 or 0,
        st = ent.stunT > 0 and 1 or 0, iv = ent.invisT > 0 and 1 or 0,
    }
end

function E.applyPose(t)
    local ent = E.list[t.id]
    if not ent then
        ent = E.spawnRemote(t.id, t.n or "?", t.av, t.of, t.b)
        ent.pos = { t.p[1], 0, t.p[3] }
    end
    if ent.auth then return ent end
    ent.base = t.b or ent.base
    ent.target = { t.p[1], t.p[2] or 0, t.p[3] }
    ent.targetYaw = t.y or 0
    ent.speed = t.sp or 0
    ent.anim = t.a or "idle"
    ent.netStun = t.st == 1
    ent.invisT = t.iv == 1 and 1 or 0
    if t.sw == 1 and ent.swing <= 0 then ent.swing = 0.001 end
    if (t.it or "bat") ~= ent.item then E.setItem(ent, t.it) end
    local c = t.c
    if c then
        if not ent.carry or ent.carry.id ~= c[1] or ent.carry.s ~= c[4] then E.setCarry(ent, c[3], c[4], c[1], c[2]) end
    elseif ent.carry then
        E.clearCarry(ent)
    end
    ent.lastPose = G.realTime
    return ent
end

---------------------------------------------------------------------------
-- Atualizacao
---------------------------------------------------------------------------
local function angLerp(a, b, k)
    local d = ((b - a + 540) % 360) - 180
    return a + d * k
end

function E.update(dt, viewer)
    for _, ent in ipairs(E.order) do
        -- fisica de empurrao/pulo (entidades com autoridade local, menos o jogador: ele e o rig)
        if ent.auth and ent.kind == "bot" then
            if V.len(ent.knock) > 0.05 then
                local np = V.madd(ent.pos, ent.knock, dt)
                ent.pos = G.collide(np, 0.3, ent)
                ent.knock = V.scale(ent.knock, math.max(0, 1 - dt * 4))
            end
            if ent.y > 0 or (ent.vy or 0) > 0 then
                ent.vy = (ent.vy or 0) - 12 * dt
                ent.y = math.max(0, ent.y + ent.vy * dt)
                if ent.y <= 0 then ent.vy = 0 end
            end
        end
        if ent.stunT > 0 then ent.stunT = math.max(0, ent.stunT - dt) end
        if ent.invisT > 0 and ent.auth then ent.invisT = math.max(0, ent.invisT - dt) end
        -- remotos: interpolacao
        if ent.kind == "remote" and ent.target then
            local k = V.smoothK(10, dt)
            local d = V.dist(ent.pos, ent.target)
            if d > 6 then ent.pos = V.copy(ent.target) else ent.pos = V.lerp(ent.pos, ent.target, k) end
            ent.y = ent.pos[2]
            ent.pos[2] = 0
            ent.yaw = angLerp(ent.yaw, ent.targetYaw, k)
        end
        -- golpe
        if ent.swing > 0 then
            ent.swing = ent.swing + dt / 0.45
            if ent.swing >= 1 then ent.swing = 0 end
        end
        local anim = ent.anim
        if ent.stunT > 0 or ent.netStun then anim = "stun"
        elseif ent.carry then anim = "carry" end
        local vis = ent.invisT <= 0 or ent.kind == "local"
        if ent.visible ~= vis then ent.visible = vis; AV.setVisible(ent.av, vis) end
        AV.place(ent.av, { ent.pos[1], ent.y or 0, ent.pos[3] }, ent.yaw)
        AV.animate(ent.av, dt, anim, ent.speed, ent.swing > 0 and ent.swing or nil)
        if ent.kind ~= "local" then AV.faceTag(ent.av, viewer) end
        if ent.carry and ent.carry.inst then
            M.animate(ent.carry.inst, G.realTime, "carried")
            if ent.kind ~= "local" and ent.visible then
                local h = ent.carry.inst.size
                G.labels.want("c" .. ent.id, { ent.pos[1], (ent.y or 0) + 1.75 + 0.45 + h * 1.15, ent.pos[3] }, ent.carry.id, ent.carry.mut, nil)
            end
        end
    end
end

-- entidades perto de um ponto (para golpes)
function E.near(p, r, except)
    local out = {}
    for _, e in ipairs(E.order) do
        if e ~= except and V.distXZ(e.pos, p) < r then out[#out + 1] = e end
    end
    return out
end

function E.clear()
    for i = #E.order, 1, -1 do E.remove(E.order[i].id) end
end

return E
