-- enemies.lua — os RED MEN de cristal.
--  * um tiro = estilhaca em dezenas de cacos vermelhos (que ficam suspensos no tempo parado)
--  * soco ou objeto arremessado = DESARMA e desequilibra; segundo soco = estilhaca
--  * katana = corta ao meio; da pra ARRANCAR a arma da mao deles
--  * pistola/uzi: mantem distancia e mira; escopeta: chega perto; katana/mao vazia: corre e ataca
-- Toda a IA anda no TEMPO DO JOGO (gdt).

local V = require("vec")
local A = require("api")

local E = {}
local G

E.list = {}

local RED = { 0.95, 0.07, 0.04 }
local RED2 = { 0.78, 0.04, 0.03 }
local RED3 = { 1.0, 0.18, 0.1 }
local M_RED = { smooth = 0.95, metal = 0.15, emit = { 1.0, 0.04, 0.02 } }
local M_RED2 = { smooth = 0.9, metal = 0.2, emit = { 0.6, 0.02, 0.01 } }
local M_RED3 = { smooth = 0.95, metal = 0.1, emit = { 1.6, 0.12, 0.06 } }

local RANGE = {
    pistol = { 3.5, 7.5, 1.6, 2.6 },   -- distancia min, max, cooldown min, max
    uzi = { 3.5, 7.0, 2.0, 3.0 },
    shotgun = { 1.8, 4.0, 2.0, 3.0 },
}

---------------------------------------------------------------------------
-- Corpo de cristal (no = articulacao; malha = primitivo)
---------------------------------------------------------------------------
local function node(en, name, parent, pos)
    local o = A.empty(name, parent and parent.obj or en.rootObj, pos)
    local n = { name = name, obj = o, parent = parent, pos = V.copy(pos), rot = { 0, 0, 0 }, last = { 0, 0, 0 } }
    en.nodes[name] = n
    return n
end

local function mesh(en, nd, kind, pos, scale, color, mat, rot)
    local o = A.prim(kind, { parent = nd.obj, pos = pos, scale = scale, color = color, mat = mat, rot = rot })
    en.meshes[#en.meshes + 1] = { obj = o, color = color }
    return o
end

-- membro facetado: cubo girado 45 graus em Y (secao de losango) = visual de cristal
local function limb(en, nd, len, w, color, mat)
    mesh(en, nd, "cube", { 0, -len * 0.5, 0 }, { w, len, w }, color, mat, { 0, 45, 0 })
end

local function build(en)
    local hips = node(en, "hips", nil, { 0, 0.95, 0 })
    mesh(en, hips, "cube", { 0, 0, 0 }, { 0.3, 0.16, 0.19 }, RED2, M_RED2, { 0, 0, 0 })
    local spine = node(en, "spine", hips, { 0, 0.08, 0 })
    mesh(en, spine, "cube", { 0, 0.24, 0 }, { 0.36, 0.44, 0.2 }, RED, M_RED)
    mesh(en, spine, "cube", { 0, 0.3, 0.06 }, { 0.26, 0.26, 0.16 }, RED3, M_RED3, { 0, 45, 0 })
    mesh(en, spine, "cube", { 0, 0.44, 0 }, { 0.42, 0.08, 0.2 }, RED2, M_RED2)
    local neck = node(en, "neck", spine, { 0, 0.5, 0 })
    mesh(en, neck, "cube", { 0, 0.04, 0 }, { 0.08, 0.08, 0.08 }, RED2, M_RED2, { 0, 45, 0 })
    -- cabeca: duas "gemas" sobrepostas = poliedro facetado
    mesh(en, neck, "cube", { 0, 0.16, 0 }, { 0.17, 0.2, 0.17 }, RED, M_RED, { 0, 45, 0 })
    mesh(en, neck, "cube", { 0, 0.16, 0 }, { 0.2, 0.17, 0.2 }, RED3, M_RED3, { 35, 0, 35 })

    for _, s in ipairs({ { "L", -1 }, { "R", 1 } }) do
        local k, sx = s[1], s[2]
        local sh = node(en, "shoulder" .. k, spine, { 0.24 * sx, 0.42, 0 })
        mesh(en, sh, "cube", { 0, 0, 0 }, { 0.12, 0.12, 0.12 }, RED3, M_RED3, { 45, 0, 45 })
        limb(en, sh, 0.29, 0.09, RED, M_RED)
        local el = node(en, "elbow" .. k, sh, { 0, -0.3, 0 })
        limb(en, el, 0.27, 0.075, RED2, M_RED2)
        mesh(en, el, "cube", { 0, -0.3, 0 }, { 0.08, 0.09, 0.08 }, RED3, M_RED3, { 0, 45, 0 })
        local hp = node(en, "hip" .. k, hips, { 0.11 * sx, -0.05, 0 })
        limb(en, hp, 0.44, 0.12, RED, M_RED)
        local kn = node(en, "knee" .. k, hp, { 0, -0.44, 0 })
        mesh(en, kn, "cube", { 0, 0, 0 }, { 0.1, 0.1, 0.1 }, RED3, M_RED3, { 45, 0, 45 })
        limb(en, kn, 0.42, 0.1, RED2, M_RED2)
        mesh(en, kn, "cube", { 0, -0.44, 0.04 }, { 0.1, 0.05, 0.2 }, RED2, M_RED2)
    end

    en.shapes = {
        { "head", "neck", { 0, 0.16, 0 }, nil, nil, 0.13 },
        { "torso", "spine", { 0, 0.05, 0 }, "spine", { 0, 0.44, 0 }, 0.2 },
        { "torso", "hips", { 0, 0, 0 }, nil, nil, 0.16 },
        { "arm", "shoulderL", { 0, 0, 0 }, "elbowL", { 0, 0, 0 }, 0.07 },
        { "arm", "elbowL", { 0, 0, 0 }, "elbowL", { 0, -0.3, 0 }, 0.06 },
        { "arm", "shoulderR", { 0, 0, 0 }, "elbowR", { 0, 0, 0 }, 0.07 },
        { "arm", "elbowR", { 0, 0, 0 }, "elbowR", { 0, -0.3, 0 }, 0.06 },
        { "leg", "hipL", { 0, 0, 0 }, "kneeL", { 0, 0, 0 }, 0.08 },
        { "leg", "kneeL", { 0, 0, 0 }, "kneeL", { 0, -0.44, 0 }, 0.07 },
        { "leg", "hipR", { 0, 0, 0 }, "kneeR", { 0, 0, 0 }, 0.08 },
        { "leg", "kneeR", { 0, 0, 0 }, "kneeR", { 0, -0.44, 0 }, 0.07 },
    }
end

---------------------------------------------------------------------------
-- Cinematica direta (Lua)
---------------------------------------------------------------------------
local function nodeWorld(en, n, cache)
    local c = cache[n]
    if c then return c end
    local nb = V.basisFromEuler(n.rot[1], n.rot[2], n.rot[3])
    local pos, Bm
    if n.parent then
        local p = nodeWorld(en, n.parent, cache)
        pos = V.poseApply(p.pos, p.B, V.scale(n.pos, en.scale))
        Bm = V.mulMM(p.B, nb)
    else
        pos = V.poseApply(en.pos, en.B, V.scale(n.pos, en.scale))
        Bm = V.mulMM(en.B, nb)
    end
    c = { pos = pos, B = Bm }
    cache[n] = c
    return c
end

local function shapes(en)
    if en.shapeFrame == G.frame then return en.shapeCache end
    local cache, out = {}, {}
    for _, s in ipairs(en.shapes) do
        local na = nodeWorld(en, en.nodes[s[2]], cache)
        local a = V.poseApply(na.pos, na.B, V.scale(s[3], en.scale))
        local b = nil
        if s[4] then
            local nb = nodeWorld(en, en.nodes[s[4]], cache)
            b = V.poseApply(nb.pos, nb.B, V.scale(s[5], en.scale))
        end
        out[#out + 1] = { zone = s[1], a = a, b = b, r = s[6] * en.scale }
    end
    local hand = nodeWorld(en, en.nodes.elbowR, cache)
    en.handPos = V.poseApply(hand.pos, hand.B, { 0, -0.3, 0 })
    en.handB = hand.B
    en.shapeFrame = G.frame
    en.shapeCache = out
    return out
end
E.shapes = shapes

local function setRot(n, x, y, z)
    n.rot[1], n.rot[2], n.rot[3] = x, y, z
    local l = n.last
    if math.abs(l[1] - x) + math.abs(l[2] - y) + math.abs(l[3] - z) > 0.4 then
        l[1], l[2], l[3] = x, y, z
        A.rot(n.obj, x, y, z)
    end
end

---------------------------------------------------------------------------
-- Spawn
---------------------------------------------------------------------------
function E.spawn(pos, weapon, opt)
    opt = opt or {}
    local en = {
        pos = { pos[1], 0, pos[3] }, yaw = opt.yaw or 0, vel = { 0, 0, 0 }, nodes = {}, meshes = {},
        state = "spawn", t = 0, scale = 0.01, phase = math.random() * 6, cooldown = 0.8 + math.random() * 1.2,
        stagger = 0, aim = 0, swing = 0, weaponType = weapon, strafe = math.random() < 0.5 and -1 or 1, strafeT = 1,
        hits = 0, speedMult = opt.speed or 1, passive = opt.passive,
    }
    en.B = V.basisFromEuler(0, en.yaw, 0)
    en.rootObj = A.empty("enemy", G.rig.world, en.pos)
    A.rot(en.rootObj, 0, en.yaw, 0)
    A.scale(en.rootObj, 0.01)
    build(en)
    if weapon and weapon ~= "none" then
        local it = G.items.spawn(weapon, en.pos, en.B, { held = "enemy", ammo = opt.ammo })
        it.enemy = en
        en.weapon = it
    end
    E.list[#E.list + 1] = en
    G.fx.spawn(en.pos)
    G.sound3D("sounds/spawn.wav", V.add(en.pos, { 0, 1, 0 }), 0.8)
    return en
end

---------------------------------------------------------------------------
-- Desarmar / matar
---------------------------------------------------------------------------
function E.disarm(en, vel)
    local it = en.weapon
    if not it then return nil end
    en.weapon = nil
    it.enemy = nil
    it.holderEnemy = nil
    G.items.drop(it, vel or { (math.random() - 0.5), 1.5, (math.random() - 0.5) })
    return it
end

function E.stagger(en, dir, amount)
    en.stagger = math.max(en.stagger, amount or 0.8)
    en.state = "stagger"
    en.swing, en.aim = 0, 0
    en.charging = false
    if dir then en.pos = V.add(en.pos, V.scale({ dir[1], 0, dir[3] }, 0.25)) end
end

function E.kill(en, dir, force, hitPoint, cause)
    if en.dead then return end
    en.dead = true
    dir = dir or { 0, 0, 1 }
    shapes(en)
    local pts = {}
    for _, s in ipairs(en.shapeCache) do
        pts[#pts + 1] = s.a
        if s.b then pts[#pts + 1] = s.b; pts[#pts + 1] = V.mid(s.a, s.b) end
    end
    if hitPoint then for _ = 1, 4 do pts[#pts + 1] = hitPoint end end
    G.fx.shatter(pts, dir, force or 3, 40, "shard")
    G.sound3D("sounds/shatter.wav", V.add(en.pos, { 0, 1.1, 0 }), 1, 0.9 + math.random() * 0.2)
    if en.weapon then E.disarm(en, V.add(V.scale(dir, 1.2), { 0, 1.2, 0 })) end
    A.destroy(en.rootObj)
    if G.game then G.game.onKill(en, cause) end
end

---------------------------------------------------------------------------
-- Consultas (balas, katana, socos, objetos)
---------------------------------------------------------------------------
local function segSegDist(a1, b1, a2, b2)
    local best = 1e9
    for i = 0, 5 do
        local p = V.lerp(a1, b1, i / 5)
        local d = b2 and V.pointSegDist(p, a2, b2) or V.dist(p, a2)
        if d < best then best = d end
    end
    return best
end

local function alive(en) return not en.dead and en.scale > 0.4 end

-- segmento (bala). exclude = inimigo que atirou
function E.hitSegment(a, b, exclude)
    local best, bEn, bZone, bP = 1e9, nil, nil, nil
    for _, en in ipairs(E.list) do
        if alive(en) and en ~= exclude then
            local c = V.add(en.pos, { 0, 1.0, 0 })
            if V.pointSegDist(c, a, b) < 1.1 then
                for _, s in ipairs(shapes(en)) do
                    local d = segSegDist(a, b, s.a, s.b)
                    if d < s.r then
                        local da = V.dist(a, s.a)
                        if da < best then best, bEn, bZone, bP = da, en, s.zone, s.a end
                    end
                end
            end
        end
    end
    return bEn, bZone, bP
end

function E.slash(a, b, r, vel)
    for _, en in ipairs(E.list) do
        if alive(en) then
            for _, s in ipairs(shapes(en)) do
                if segSegDist(a, b, s.a, s.b) < r + s.r then
                    G.sound3D("sounds/slash.wav", s.a, 1)
                    E.kill(en, V.norm(vel), 2.5, s.a, "katana")
                    break
                end
            end
        end
    end
end

-- soco: velocidade REAL da mao
function E.punch(p, vel)
    local sp = V.len(vel)
    if sp < 2.0 then return false end
    for _, en in ipairs(E.list) do
        if alive(en) and (en.punchCd or 0) <= 0 then
            for _, s in ipairs(shapes(en)) do
                local d = s.b and V.pointSegDist(p, s.a, s.b) or V.dist(p, s.a)
                if d < s.r + 0.06 then
                    local dir = V.norm(vel)
                    en.punchCd = 0.4
                    G.sound3D("sounds/punch.wav", p, 1)
                    G.time.pulse(0.8, 0.1)
                    if en.weapon then
                        E.disarm(en, V.add(V.scale(dir, 1.5), { 0, 2, 0 }))
                        E.stagger(en, dir, 0.9)
                    elseif en.state == "stagger" or sp > 4.5 or s.zone == "head" then
                        E.kill(en, dir, 3, p, "punch")
                    else
                        E.stagger(en, dir, 0.9)
                    end
                    return true
                end
            end
        end
    end
    return false
end

-- objeto voando (item) bate no inimigo
function E.itemHit(it, p, r, vel)
    local sp = V.len(vel)
    if sp < 1.8 then return false end
    for _, en in ipairs(E.list) do
        if alive(en) and en.weapon ~= it then
            for _, s in ipairs(shapes(en)) do
                local d = s.b and V.pointSegDist(p, s.a, s.b) or V.dist(p, s.a)
                if d < s.r + r then
                    local dir = V.norm(vel)
                    G.sound3D("sounds/thud.wav", p, 1)
                    if it.type == "katana" then
                        E.kill(en, dir, 2.5, p, "katana")
                    elseif en.weapon then
                        E.disarm(en, V.add(V.scale(dir, 1.2), { 0, 2.2, 0 }))
                        E.stagger(en, dir, 1.0)
                    elseif en.state == "stagger" or s.zone == "head" then
                        E.kill(en, dir, 2.5, p, "throw")
                    else
                        E.stagger(en, dir, 1.0)
                    end
                    return true
                end
            end
        end
    end
    return false
end

function E.aimAssist(o, d, maxDeg)
    local bestAng, bestDir = maxDeg * V.RAD, nil
    for _, en in ipairs(E.list) do
        if alive(en) then
            for _, s in ipairs(shapes(en)) do
                if s.zone == "head" or s.zone == "torso" then
                    local p = s.b and V.mid(s.a, s.b) or s.a
                    local v = V.sub(p, o)
                    local dist = V.len(v)
                    if dist > 0.3 then
                        local ang = math.acos(V.clamp(V.dot(V.scale(v, 1 / dist), d), -1, 1))
                        if ang < bestAng and G.level.lineClear(o, p) then bestAng, bestDir = ang, V.scale(v, 1 / dist) end
                    end
                end
            end
        end
    end
    if bestDir then return V.norm(V.lerp(d, bestDir, 0.75)) end
end

---------------------------------------------------------------------------
-- Navegacao (mesma ideia do BoneLab: contorna caixas escolhendo um lado)
---------------------------------------------------------------------------
local function steer(en, desired, gdt)
    local p = en.pos
    local av = { 0, 0, 0 }
    local near = false
    for _, ob in ipairs(G.level.obstacles) do
        local cx = V.clamp(p[1], ob[1], ob[2])
        local cz = V.clamp(p[3], ob[3], ob[4])
        local dx, dz = p[1] - cx, p[3] - cz
        local d = math.sqrt(dx * dx + dz * dz)
        if d < 0.9 and d > 1e-4 then
            near = true
            local w = (0.9 - d) * 2.8
            av[1], av[3] = av[1] + dx / d * w, av[3] + dz / d * w
            local tx, tz = -dz / d, dx / d
            if not en.avoidSign then
                local side = tx * (p[1] - (ob[1] + ob[2]) * 0.5) + tz * (p[3] - (ob[3] + ob[4]) * 0.5)
                en.avoidSign = side >= 0 and 1 or -1
            end
            av[1], av[3] = av[1] + tx * en.avoidSign * w * 1.2, av[3] + tz * en.avoidSign * w * 1.2
        end
    end
    if near then en.avoidT = 1.2 else
        en.avoidT = (en.avoidT or 0) - gdt
        if en.avoidT <= 0 then en.avoidSign = nil end
    end
    for _, o in ipairs(E.list) do
        if o ~= en and not o.dead then
            local dx, dz = p[1] - o.pos[1], p[3] - o.pos[3]
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 0.7 and d > 1e-4 then
                av[1], av[3] = av[1] + dx / d * (0.7 - d) * 6, av[3] + dz / d * (0.7 - d) * 6
            end
        end
    end
    local v = V.add(desired, av)
    v[2] = 0
    local sp = V.len(desired)
    if V.len(v) > sp and sp > 0 then v = V.scale(V.norm(v), sp) end
    en.vel = V.lerp(en.vel, v, V.smoothK(6, gdt))
    local np = V.madd(p, en.vel, gdt)
    for _, ob in ipairs(G.level.obstacles) do
        local cx = V.clamp(np[1], ob[1], ob[2])
        local cz = V.clamp(np[3], ob[3], ob[4])
        local dx, dz = np[1] - cx, np[3] - cz
        local d = math.sqrt(dx * dx + dz * dz)
        if d < 0.28 then
            if d > 1e-4 then np[1], np[3] = cx + dx / d * 0.28, cz + dz / d * 0.28 else np[1], np[3] = p[1], p[3] end
        end
    end
    local bd = G.level.bounds
    np[1] = V.clamp(np[1], bd[1] + 0.3, bd[2] - 0.3)
    np[3] = V.clamp(np[3], bd[3] + 0.3, bd[4] - 0.3)
    np[2] = 0
    en.pos = np
end

local function face(en, target, gdt, rate)
    local dx, dz = target[1] - en.pos[1], target[3] - en.pos[3]
    if dx * dx + dz * dz < 1e-4 then return end
    local want = math.atan(dx, dz) * V.DEG
    local diff = ((want - en.yaw + 540) % 360) - 180
    en.yaw = en.yaw + diff * V.smoothK(rate or 6, gdt)
end

---------------------------------------------------------------------------
-- IA
---------------------------------------------------------------------------
local function fireAt(en, target)
    local it = en.weapon
    local def = it.def
    local muzzle = V.poseApply(it.pos, it.B, def.muzzle)
    for _ = 1, def.pellets do
        local d = V.norm(V.sub(target, muzzle))
        local Bm = V.basis(d, { 0, 1, 0 })
        local dir = G.weapons.spreadDir(Bm, def.spread * 0.8 + 1.2)
        G.bullets.fire(muzzle, dir, def.speed * 0.8, "enemy", en)
    end
    G.fx.muzzle(muzzle, it.B, def.pellets > 1)
    G.sound3D(def.sound, muzzle, 0.9)
    it.recoil = 0.8
end

local function think(en, gdt)
    local head = G.rig.head
    local target = { head[1], 0, head[3] }
    local dist = V.distXZ(en.pos, target)
    local wt = en.weapon and en.weapon.type or "none"
    local ranged = RANGE[wt]

    if en.state == "stagger" then
        en.stagger = en.stagger - gdt
        en.vel = V.scale(en.vel, math.exp(-gdt * 6))
        if en.stagger <= 0 then en.state = "move" end
        return
    end

    if ranged then
        local toP = V.norm(V.sub(target, en.pos))
        en.strafeT = en.strafeT - gdt
        if en.strafeT <= 0 then en.strafe = -en.strafe; en.strafeT = 1.5 + math.random() * 2 end
        local side = { toP[3] * en.strafe, 0, -toP[1] * en.strafe }
        local eye = V.add(en.pos, { 0, 1.6, 0 })
        local los = G.level.lineClear(eye, head)
        local desired
        if dist > ranged[2] or not los then
            desired = V.scale(V.add(toP, V.scale(side, 0.3)), 1.3 * en.speedMult)
        elseif dist < ranged[1] then
            desired = V.scale(V.add(V.scale(toP, -1), V.scale(side, 0.4)), 1.1 * en.speedMult)
        else
            desired = V.scale(side, 0.6 * en.speedMult)
        end
        if en.aiming then desired = V.scale(desired, 0.1) end
        steer(en, desired, gdt)
        face(en, target, gdt, 6)
        if en.aiming then
            en.aimT = en.aimT + gdt
            en.aim = math.min(1, en.aimT / 0.55)
            if en.aimT >= 0.55 then
                local aimPoint = V.add(head, { (math.random() - 0.5) * 0.15, -0.12 + (math.random() - 0.5) * 0.2, (math.random() - 0.5) * 0.15 })
                fireAt(en, aimPoint)
                en.burst = (en.burst or 0) + 1
                if wt == "uzi" and en.burst < 3 then
                    en.aimT = 0.42
                else
                    en.aiming = false
                    en.burst = 0
                    en.cooldown = ranged[3] + math.random() * (ranged[4] - ranged[3])
                end
            end
        else
            en.aim = math.max(0, en.aim - gdt * 2)
            if en.cooldown <= 0 and los and dist <= ranged[2] + 1 then
                en.aiming = true
                en.aimT = 0
            end
        end
        return
    end

    -- corpo a corpo (katana ou mao vazia)
    if en.swinging then
        en.swingT = en.swingT + gdt
        en.vel = V.scale(en.vel, math.exp(-gdt * 8))
        face(en, target, gdt, 8)
        if en.swingT < 0.5 then
            en.swing = en.swingT / 0.5
        elseif not en.struck then
            en.struck = true
            en.swing = -0.4
            G.sound3D(wt == "katana" and "sounds/slash.wav" or "sounds/swing.wav", V.add(en.pos, { 0, 1.4, 0 }), 0.9)
            local reach = wt == "katana" and 1.45 or 1.05
            if dist < reach then G.player.die(V.norm(V.sub(target, en.pos))) end
        elseif en.swingT > 0.9 then
            en.swinging = false
            en.swing = 0
            en.cooldown = 0.5
        end
        return
    end
    local speed = (dist > 3 and 1.5 or 2.2) * en.speedMult
    local desired = { 0, 0, 0 }
    if dist > 0.8 then desired = V.scale(V.norm(V.sub(target, en.pos)), speed) end
    steer(en, desired, gdt)
    face(en, V.add(en.pos, V.add(en.vel, V.scale(V.sub(target, en.pos), 0.3))), gdt, 7)
    if dist < (wt == "katana" and 1.3 or 0.95) and en.cooldown <= 0 then
        en.swinging = true
        en.swingT = 0
        en.struck = false
    end
end

---------------------------------------------------------------------------
-- Animacao
---------------------------------------------------------------------------
local function animate(en, gdt)
    local n = en.nodes
    local sp = V.len(en.vel)
    en.phase = en.phase + gdt * (2 + sp * 3.4)
    local s = math.sin(en.phase)
    local amp = V.clamp(sp / 2, 0, 1)
    local st = en.state == "stagger" and math.min(1, en.stagger) or 0
    A.posXYZ(n.hips.obj, 0, 0.95 + math.abs(math.cos(en.phase)) * 0.035 * amp - st * 0.06, 0)
    setRot(n.hips, 0, s * 5 * amp, 0)
    setRot(n.spine, 8 * amp - st * 28 + (en.swing or 0) * 8, 0, 0)
    setRot(n.hipL, -32 * s * amp, 0, 0)
    setRot(n.hipR, 32 * s * amp, 0, 0)
    setRot(n.kneeL, 45 * math.max(0, -math.cos(en.phase)) * amp + st * 15, 0, 0)
    setRot(n.kneeR, 45 * math.max(0, math.cos(en.phase)) * amp + st * 15, 0, 0)
    local wt = en.weapon and en.weapon.type or "none"
    if RANGE[wt] then
        local aim = en.aim or 0
        setRot(n.shoulderR, -25 * s * amp * (1 - aim) - 88 * aim, 0, 6 * (1 - aim))
        setRot(n.elbowR, -12 * (1 - aim), 0, 0)
        setRot(n.shoulderL, 25 * s * amp, 0, -6)
        setRot(n.elbowL, -20, 0, 0)
    else
        local sw = en.swing or 0
        local raise = math.max(0, sw)
        local strike = math.max(0, -sw)
        setRot(n.shoulderR, -28 * s * amp * (1 - raise) - 150 * raise - 40 * strike, 0, 6 + 20 * strike)
        setRot(n.elbowR, -30 - 40 * raise, 0, 0)
        setRot(n.shoulderL, 28 * s * amp * (1 - raise) - (wt == "none" and 90 * raise or 0), 0, -6)
        setRot(n.elbowL, -30 - (wt == "none" and 50 * raise or 0), 0, 0)
    end
    local head = G.rig.head
    local want = math.atan(head[1] - en.pos[1], head[3] - en.pos[3]) * V.DEG
    local rel = V.clamp(((want - en.yaw + 540) % 360) - 180, -60, 60)
    setRot(n.neck, -8, rel, 0)
end

-- arma na mao do inimigo segue a mao (aponta pro jogador quando mira)
local function holdWeapon(en)
    local it = en.weapon
    if not it then return end
    shapes(en)
    local hb = en.handB
    local Bw
    if it.def.kind == "gun" then
        local toHead = V.norm(V.sub(G.rig.head, en.handPos))
        local f = V.norm(V.lerp(V.scale(hb.u, -1), toHead, en.aim or 0))
        Bw = V.basis(f, { 0, 1, 0 })
    else
        -- katana: lamina sai da mao para frente/cima
        Bw = V.basis(hb.f, V.scale(hb.u, -1))
    end
    local rPos, rB = G.weapons.recoilPose(it, en.handPos, Bw)
    it.pos, it.B = en.handPos, Bw
    it.recoil = (it.recoil or 0) * 0.9
    G.items.place(it, rPos, rB)
end

function E.update(gdt, dt)
    for _, en in ipairs(E.list) do
        if not en.dead then
            en.t = en.t + gdt
            en.cooldown = en.cooldown - gdt
            en.punchCd = (en.punchCd or 0) - dt
            if en.state == "spawn" then
                en.scale = math.min(1, en.t / 0.6)
                A.scale(en.rootObj, en.scale)
                if en.t >= 0.6 then en.state = "move"; en.scale = 1; A.scale(en.rootObj, 1) end
            elseif not en.passive and not G.player.dead then
                think(en, gdt)
            end
            if not en.dead then
                animate(en, gdt)
                en.B = V.basisFromEuler(0, en.yaw, 0)
                A.pos(en.rootObj, en.pos)
                A.rot(en.rootObj, 0, en.yaw, 0)
                en.shapeFrame = nil
                holdWeapon(en)
            end
        end
    end
    local i = 1
    while i <= #E.list do
        if E.list[i].dead then table.remove(E.list, i) else i = i + 1 end
    end
end

function E.alive()
    local n = 0
    for _, en in ipairs(E.list) do if not en.dead then n = n + 1 end end
    return n
end

function E.clear()
    for _, en in ipairs(E.list) do
        if not en.dead then
            en.dead = true
            if en.weapon then G.items.destroy(en.weapon) end
            A.destroy(en.rootObj)
        end
    end
    E.list = {}
end

-- jogador puxa a arma da mao do inimigo
function E.snatch(it)
    local en = it.enemy
    if not en then return end
    en.weapon = nil
    it.enemy = nil
    E.stagger(en, nil, 0.7)
end

function E.init(ctx) G = ctx end

return E
