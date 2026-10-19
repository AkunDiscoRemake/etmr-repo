-- bots.lua — inimigos com IA.
--   GRUNT    "Null Body": corre ate voce e bate (corpo a corpo)
--   ATIRADOR "Omni": mantem distancia, mira e dispara bolas de plasma (da pra desviar e abater)
--   CRAB     "Crablet": pequeno e rapido, PULA NO SEU ROSTO. Arranque ele com a mao ou soque!
--   BONECO   alvo de treino parado
--
-- Corpo hierarquico (articulacoes rotacionadas por animacao procedural) + cinematica direta
-- em Lua para acertar cada parte (cabeca = headshot). Ao morrer vira ragdoll fisico.

local V = require("vec")
local A = require("api")

local B = {}
local G

B.list = {}
B.projectiles = {}
B.debris = {}
B.maxAlive = 9

local TYPES = {
    grunt = { hp = 100, speed = 1.25, run = 2.3, score = 100, accent = { 1, 0.45, 0.08 }, visor = { 1, 0.15, 0.05 }, body = { 0.82, 0.83, 0.86 } },
    gunner = { hp = 75, speed = 1.4, run = 1.9, score = 150, accent = { 0.15, 0.75, 1 }, visor = { 0.2, 0.9, 1 }, body = { 0.3, 0.32, 0.36 } },
    dummy = { hp = 150, speed = 0, run = 0, score = 10, accent = { 1, 0.85, 0.1 }, visor = { 1, 0.85, 0.1 }, body = { 0.9, 0.88, 0.8 } },
    crab = { hp = 28, speed = 2.6, run = 3.2, score = 120, accent = { 0.6, 1, 0.2 }, visor = { 0.7, 1, 0.1 }, body = { 0.2, 0.22, 0.2 } },
}
B.TYPES = TYPES

local PART_MULT = { head = 2.6, torso = 1.0, pelvis = 0.9, arm = 0.55, leg = 0.65, crab = 1.0 }

---------------------------------------------------------------------------
-- Construcao (no = articulacao com filhos; malha = primitivo visivel)
---------------------------------------------------------------------------
local function node(bot, name, parent, pos)
    local o = A.empty(name, parent and parent.obj or bot.rootObj, pos)
    local n = { name = name, obj = o, parent = parent, pos = V.copy(pos), rot = { 0, 0, 0 }, lastRot = { 0, 0, 0 } }
    bot.nodes[name] = n
    return n
end

local function mesh(bot, nd, kind, pos, scale, color, mat, rot, tex, zone)
    local o = A.prim(kind, { parent = nd.obj, pos = pos, scale = scale, color = color, mat = mat, rot = rot, tex = tex })
    local m = { obj = o, node = nd, pos = pos, rot = rot or { 0, 0, 0 }, scale = scale, kind = kind, zone = zone, color = color }
    bot.meshes[#bot.meshes + 1] = m
    return m
end

local function buildHumanoid(bot)
    local T = bot.T
    local body, acc, dark = T.body, T.accent, { 0.12, 0.12, 0.14 }
    local mBody = { metal = 0.35, smooth = 0.6 }
    local mDark = { metal = 0.7, smooth = 0.5 }
    local mAcc = { metal = 0.4, smooth = 0.6, emit = { acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6 } }

    local hips = node(bot, "hips", nil, { 0, 0.95, 0 })
    mesh(bot, hips, "cube", { 0, 0, 0 }, { 0.32, 0.15, 0.2 }, dark, mDark, nil, nil, "pelvis")
    local spine = node(bot, "spine", hips, { 0, 0.08, 0 })
    mesh(bot, spine, "cube", { 0, 0.25, 0 }, { 0.38, 0.46, 0.22 }, body, mBody, nil, "images/bot_torso.png", "torso")
    mesh(bot, spine, "cube", { 0, 0.31, 0.116 }, { 0.3, 0.24, 0.02 }, acc, mAcc, nil, nil, "torso")
    bot.core = mesh(bot, spine, "sphere", { 0, 0.16, 0.115 }, { 0.07, 0.07, 0.03 }, T.visor, { emit = { T.visor[1] * 2, T.visor[2] * 2, T.visor[3] * 2 } }, nil, nil, "torso")
    mesh(bot, spine, "cube", { 0, 0.06, 0 }, { 0.26, 0.1, 0.18 }, dark, mDark, nil, nil, "torso")
    local neck = node(bot, "neck", spine, { 0, 0.5, 0 })
    mesh(bot, neck, "cylinder", { 0, 0.03, 0 }, { 0.09, 0.04, 0.09 }, dark, mDark, nil, nil, "head")
    mesh(bot, neck, "sphere", { 0, 0.15, 0 }, { 0.24, 0.27, 0.25 }, body, mBody, nil, nil, "head")
    bot.visor = mesh(bot, neck, "cube", { 0, 0.17, 0.103 }, { 0.19, 0.06, 0.05 }, T.visor, { emit = { T.visor[1] * 2.5, T.visor[2] * 2.5, T.visor[3] * 2.5 } }, nil, nil, "head")
    mesh(bot, neck, "cube", { 0, 0.27, 0 }, { 0.05, 0.05, 0.16 }, acc, mAcc, nil, nil, "head")

    for _, s in ipairs({ { "L", -1 }, { "R", 1 } }) do
        local k, sx = s[1], s[2]
        local sh = node(bot, "shoulder" .. k, spine, { 0.25 * sx, 0.42, 0 })
        mesh(bot, sh, "sphere", { 0, 0, 0 }, { 0.13, 0.13, 0.13 }, acc, mAcc, nil, nil, "arm")
        mesh(bot, sh, "capsule", { 0, -0.15, 0 }, { 0.1, 0.17, 0.1 }, body, mBody, nil, nil, "arm")
        local el = node(bot, "elbow" .. k, sh, { 0, -0.3, 0 })
        mesh(bot, el, "capsule", { 0, -0.14, 0 }, { 0.085, 0.16, 0.085 }, dark, mDark, nil, nil, "arm")
        local handM = mesh(bot, el, "sphere", { 0, -0.3, 0 }, { 0.095, 0.095, 0.095 }, body, mBody, nil, nil, "arm")
        if k == "R" then bot.handR = handM end
        if k == "R" and bot.type == "gunner" then
            -- canhao de plasma no antebraco
            mesh(bot, el, "cylinder", { 0, -0.2, 0.05 }, { 0.08, 0.12, 0.08 }, dark, mDark, nil, nil, "arm")
            bot.cannon = mesh(bot, el, "sphere", { 0, -0.33, 0.05 }, { 0.07, 0.07, 0.07 }, T.visor, { emit = { 0.2, 1, 1.4 } }, nil, nil, "arm")
        end
        local hp = node(bot, "hip" .. k, hips, { 0.11 * sx, -0.05, 0 })
        mesh(bot, hp, "capsule", { 0, -0.22, 0 }, { 0.13, 0.24, 0.13 }, body, mBody, nil, nil, "leg")
        local kn = node(bot, "knee" .. k, hp, { 0, -0.44, 0 })
        mesh(bot, kn, "sphere", { 0, 0, 0 }, { 0.11, 0.11, 0.11 }, acc, mAcc, nil, nil, "leg")
        mesh(bot, kn, "capsule", { 0, -0.22, 0 }, { 0.11, 0.23, 0.11 }, dark, mDark, nil, nil, "leg")
        mesh(bot, kn, "cube", { 0, -0.44, 0.05 }, { 0.11, 0.06, 0.22 }, dark, mDark, nil, nil, "leg")
    end

    -- formas de colisao para tiros: { zone, nodeA, offA, nodeB, offB, raio }
    bot.shapes = {
        { "head", "neck", { 0, 0.15, 0 }, nil, nil, 0.145 },
        { "torso", "spine", { 0, 0.07, 0 }, "spine", { 0, 0.43, 0 }, 0.2 },
        { "pelvis", "hips", { 0, 0, 0 }, nil, nil, 0.16 },
        { "arm", "shoulderL", { 0, 0, 0 }, "elbowL", { 0, 0, 0 }, 0.065 },
        { "arm", "elbowL", { 0, 0, 0 }, "elbowL", { 0, -0.3, 0 }, 0.06 },
        { "arm", "shoulderR", { 0, 0, 0 }, "elbowR", { 0, 0, 0 }, 0.065 },
        { "arm", "elbowR", { 0, 0, 0 }, "elbowR", { 0, -0.3, 0 }, 0.06 },
        { "leg", "hipL", { 0, 0, 0 }, "kneeL", { 0, 0, 0 }, 0.08 },
        { "leg", "kneeL", { 0, 0, 0 }, "kneeL", { 0, -0.44, 0 }, 0.07 },
        { "leg", "hipR", { 0, 0, 0 }, "kneeR", { 0, 0, 0 }, 0.08 },
        { "leg", "kneeR", { 0, 0, 0 }, "kneeR", { 0, -0.44, 0 }, 0.07 },
    }
    bot.boundY, bot.boundR = 0.95, 1.05

    if bot.type == "dummy" then
        -- base do boneco de treino
        local base = node(bot, "base", nil, { 0, 0, 0 })
        mesh(bot, base, "cylinder", { 0, 0.03, 0 }, { 0.6, 0.03, 0.6 }, dark, mDark)
        mesh(bot, base, "cylinder", { 0, 0.05, 0 }, { 0.64, 0.01, 0.64 }, acc, mAcc)
    end
end

local function buildCrab(bot)
    local T = bot.T
    local dark, acc = T.body, T.accent
    local mAcc = { metal = 0.4, smooth = 0.6, emit = { acc[1] * 0.5, acc[2] * 0.5, acc[3] * 0.5 } }
    local body = node(bot, "body", nil, { 0, 0.16, 0 })
    mesh(bot, body, "sphere", { 0, 0.02, 0 }, { 0.3, 0.14, 0.34 }, dark, { metal = 0.6, smooth = 0.7 }, nil, "images/crab_shell.png", "crab")
    mesh(bot, body, "cube", { 0, -0.02, 0 }, { 0.26, 0.06, 0.28 }, { 0.1, 0.1, 0.1 }, { metal = 0.6, smooth = 0.4 }, nil, nil, "crab")
    bot.visor = mesh(bot, body, "cube", { 0, 0.03, 0.155 }, { 0.16, 0.035, 0.04 }, T.visor, { emit = { 1.2, 2.2, 0.2 } }, nil, nil, "crab")
    mesh(bot, body, "cube", { -0.06, -0.01, 0.19 }, { 0.03, 0.02, 0.08 }, acc, mAcc, { 0, -20, 0 }, nil, "crab")
    mesh(bot, body, "cube", { 0.06, -0.01, 0.19 }, { 0.03, 0.02, 0.08 }, acc, mAcc, { 0, 20, 0 }, nil, "crab")
    bot.legs = {}
    for i, l in ipairs({ { -1, 0.09 }, { -1, 0 }, { -1, -0.09 }, { 1, 0.09 }, { 1, 0 }, { 1, -0.09 } }) do
        local sx, z = l[1], l[2]
        local lg = node(bot, "leg" .. i, body, { 0.13 * sx, -0.01, z })
        mesh(bot, lg, "cube", { 0.07 * sx, 0.02, 0 }, { 0.14, 0.022, 0.022 }, acc, mAcc, { 0, 0, -25 * sx }, nil, "crab")
        mesh(bot, lg, "cube", { 0.15 * sx, -0.07, 0 }, { 0.02, 0.16, 0.02 }, dark, { metal = 0.7, smooth = 0.6 }, { 0, 0, 15 * sx }, nil, "crab")
        bot.legs[i] = { node = lg, side = sx, phase = (i % 2) * math.pi }
    end
    bot.shapes = { { "crab", "body", { 0, 0.02, 0 }, nil, nil, 0.17 } }
    bot.boundY, bot.boundR = 0.16, 0.35
end

---------------------------------------------------------------------------
-- Cinematica direta (Lua) para tiros/ragdoll
---------------------------------------------------------------------------
local function nodeWorld(bot, n, cache)
    local c = cache[n]
    if c then return c end
    local pB = V.basisFromEuler(n.rot[1], n.rot[2], n.rot[3])
    local pos, Bm
    if n.parent then
        local par = nodeWorld(bot, n.parent, cache)
        pos = V.poseApply(par.pos, par.B, V.scale(n.pos, bot.scale))
        Bm = V.mulMM(par.B, pB)
    else
        pos = V.poseApply(bot.pos, bot.B, V.scale(n.pos, bot.scale))
        Bm = V.mulMM(bot.B, pB)
    end
    c = { pos = pos, B = Bm }
    cache[n] = c
    return c
end

local function shapes(bot)
    if bot.shapeFrame == G.frame then return bot.shapeCache end
    local cache = {}
    local out = {}
    for _, s in ipairs(bot.shapes) do
        local na = nodeWorld(bot, bot.nodes[s[2]], cache)
        local a = V.poseApply(na.pos, na.B, V.scale(s[3], bot.scale))
        local b = nil
        if s[4] then
            local nb = nodeWorld(bot, bot.nodes[s[4]], cache)
            b = V.poseApply(nb.pos, nb.B, V.scale(s[5], bot.scale))
        end
        out[#out + 1] = { zone = s[1], a = a, b = b, r = s[6] * bot.scale }
    end
    bot.shapeFrame = G.frame
    bot.shapeCache = out
    bot.fkCache = cache
    return out
end

local function setRot(n, x, y, z)
    n.rot[1], n.rot[2], n.rot[3] = x, y, z
    local l = n.lastRot
    if math.abs(l[1] - x) + math.abs(l[2] - y) + math.abs(l[3] - z) > 0.4 then
        l[1], l[2], l[3] = x, y, z
        A.rot(n.obj, x, y, z)
    end
end

local function setNodePos(n, x, y, z)
    n.pos[1], n.pos[2], n.pos[3] = x, y, z
    A.posXYZ(n.obj, x, y, z)
end

---------------------------------------------------------------------------
-- Spawn
---------------------------------------------------------------------------
function B.spawn(type, pos, opt)
    opt = opt or {}
    local alive = 0
    for _, b in ipairs(B.list) do if not b.dead then alive = alive + 1 end end
    if alive >= B.maxAlive and not opt.force then return nil end
    local T = TYPES[type]
    local bot = {
        type = type, T = T, hp = T.hp * (opt.hpMult or 1), maxHp = T.hp * (opt.hpMult or 1),
        pos = { pos[1], 0, pos[3] }, yaw = opt.yaw or 0, vel = { 0, 0, 0 },
        nodes = {}, meshes = {}, state = "spawn", t = 0, phase = math.random() * 6,
        scale = 0.01, attackT = 0, cooldown = 1 + math.random(), stagger = 0, flash = 0,
        strafe = math.random() < 0.5 and -1 or 1, strafeT = 0, passive = opt.passive or type == "dummy",
        hitCooldown = 0, speedMult = opt.speedMult or 1,
    }
    bot.B = V.basisFromEuler(0, bot.yaw, 0)
    bot.rootObj = A.empty("bot_" .. type, G.rig.world, bot.pos)
    A.rot(bot.rootObj, 0, bot.yaw, 0)
    A.scale(bot.rootObj, 0.01)
    if type == "crab" then buildCrab(bot) else buildHumanoid(bot) end
    B.list[#B.list + 1] = bot
    G.fx.ring(bot.pos, T.accent)
    A.sound3D("sounds/spawn.wav", V.add(bot.pos, { 0, 1, 0 }), 0.9)
    return bot
end

---------------------------------------------------------------------------
-- Ragdoll
---------------------------------------------------------------------------
local function ragdoll(bot, dir, force, hitZone)
    local cache = {}
    shapes(bot)
    for _, m in ipairs(bot.meshes) do
        local nw = nodeWorld(bot, m.node, cache)
        local mp = V.poseApply(nw.pos, nw.B, V.scale(m.pos, bot.scale))
        local mB = V.mulMM(nw.B, V.basisFromEuler(m.rot[1], m.rot[2], m.rot[3]))
        A.parent(m.obj, G.rig.world)
        A.pos(m.obj, mp)
        A.rotBasis(m.obj, mB)
        A.scale(m.obj, m.scale[1] * bot.scale, m.scale[2] * bot.scale, m.scale[3] * bot.scale)
        A.sphereCollider(m.obj, 0.35)
        local mass = (m.kind == "sphere" and 0.6 or 1.2)
        local rb = A.addBody(m.obj, mass, true)
        local boost = (m.zone == hitZone) and 1.8 or 1
        local v = V.add(V.scale(dir, force * boost * (0.6 + math.random() * 0.6)), { (math.random() - 0.5) * 1.5, 0.8 + math.random() * 1.6, (math.random() - 0.5) * 1.5 })
        local vw = G.rig.dirToWorld(v)
        local okVel = rb and A.setVelocity(rb, vw[1], vw[2], vw[3])
        if rb then A.setAngular(rb, (math.random() - 0.5) * 12, (math.random() - 0.5) * 12, (math.random() - 0.5) * 12) end
        if m == bot.visor or m == bot.core or m == bot.cannon then A.material(m.obj, { emit = { 0.05, 0.05, 0.05 } }); A.color(m.obj, { 0.15, 0.15, 0.15 }) end
        B.debris[#B.debris + 1] = {
            obj = m.obj, t = 0, life = 9 + math.random() * 2, scale = V.scale(m.scale, bot.scale),
            lua = (rb == nil or not okVel) and { p = mp, v = v } or nil, hasRb = rb ~= nil,
        }
    end
    A.destroy(bot.rootObj)
    -- limita o numero de pecas de ragdoll
    while #B.debris > 120 do
        local d = table.remove(B.debris, 1)
        A.destroy(d.obj)
    end
end

local function updateDebris(dt)
    local i = 1
    while i <= #B.debris do
        local d = B.debris[i]
        d.t = d.t + dt
        if d.lua and not d.hasRb then
            d.lua.v[2] = d.lua.v[2] - 9.8 * dt
            d.lua.p = V.madd(d.lua.p, d.lua.v, dt)
            if d.lua.p[2] < 0.05 then d.lua.p[2] = 0.05; d.lua.v = V.scale(d.lua.v, 0.3); d.lua.v[2] = math.abs(d.lua.v[2]) end
            A.pos(d.obj, d.lua.p)
        end
        if d.t > d.life then
            A.destroy(d.obj)
            table.remove(B.debris, i)
        else
            if d.t > d.life - 0.6 then
                local k = math.max(0.01, (d.life - d.t) / 0.6)
                A.scale(d.obj, d.scale[1] * k, d.scale[2] * k, d.scale[3] * k)
            end
            i = i + 1
        end
    end
end

---------------------------------------------------------------------------
-- Dano
---------------------------------------------------------------------------
local function flash(bot)
    bot.flash = 0.09
    for _, m in ipairs(bot.meshes) do
        if m ~= bot.visor and m ~= bot.core then A.colorRGB(m.obj, 1, 1, 1) end
    end
end

local function unflash(bot)
    for _, m in ipairs(bot.meshes) do
        if m ~= bot.visor and m ~= bot.core then A.color(m.obj, m.color) end
    end
end

function B.kill(bot, dir, force, zone)
    if bot.dead then return end
    bot.dead = true
    if bot.latched then G.player.crabOff() end
    bot.latched = false
    local center = V.add(bot.pos, { 0, bot.boundY, 0 })
    A.sound3D(bot.type == "crab" and "sounds/crab_die.wav" or "sounds/bot_die.wav", center, 1)
    G.fx.sparks(center, 10, { 0, 1, 0 }, bot.T.accent, 3)
    ragdoll(bot, dir or { 0, 0, 0 }, force or 2, zone)
    if G.game then G.game.onKill(bot, zone) end
end

-- dmg ja com multiplicador aplicado pelo chamador? Nao: aqui aplicamos por zona.
function B.damage(bot, zone, dmg, dir, point, kind)
    if bot.dead or bot.state == "spawn" and bot.t < 0.3 then return end
    local mult = PART_MULT[zone] or 1
    local d = dmg * mult
    bot.hp = bot.hp - d
    bot.lastHitZone = zone
    flash(bot)
    if zone == "head" then
        A.sound3D("sounds/headshot.wav", point or bot.pos, 1)
        if G.game then G.game.onHeadshot() end
    else
        A.sound3D("sounds/hit_bot.wav", point or bot.pos, 0.9, 0.9 + math.random() * 0.2)
    end
    if point then G.fx.sparks(point, kind == "bullet" and 5 or 8, V.scale(dir or { 0, 1, 0 }, -1), bot.T.accent, 2) end
    -- reacao ao golpe
    if d > 12 and bot.type ~= "dummy" then
        bot.stagger = math.min(0.6, bot.stagger + d / 80)
        if dir then
            local push = V.scale({ dir[1], 0, dir[3] }, math.min(0.35, d / 120))
            bot.pos = V.add(bot.pos, push)
        end
        if bot.latched then B.detachCrab(bot, V.scale(dir or { 0, 0, -1 }, 2)) end
    end
    if bot.passive and bot.type ~= "dummy" then bot.passive = false end
    if bot.hp <= 0 then
        if bot.type == "dummy" then
            -- boneco de treino: cai e volta
            B.kill(bot, dir, 2.5, zone)
            local p, yaw, gen = bot.pos, bot.yaw, G.modeGen
            EMRAPI.Timer:Delay(3, function()
                if G.modeGen == gen and (G.mode == "hub" or G.mode == "sandbox") then
                    B.spawn("dummy", p, { yaw = yaw, force = true })
                end
            end)
        else
            B.kill(bot, dir, (kind == "explosion" and 7 or (kind == "melee" and 5 or 3.2)) + d / 25, zone)
        end
    end
end

---------------------------------------------------------------------------
-- Consultas para armas/combate
---------------------------------------------------------------------------
function B.raycast(o, d, maxT)
    local best, bBot, bZone = maxT or 1e9, nil, nil
    for _, bot in ipairs(B.list) do
        if not bot.dead and bot.scale > 0.3 then
            local c = V.add(bot.pos, { 0, bot.boundY * bot.scale, 0 })
            if bot.latched or bot.grabbed or bot.flying then c = bot.pos end
            local tb = V.raySphere(o, d, c, bot.boundR * bot.scale + 0.1)
            if tb and tb < best then
                for _, s in ipairs(shapes(bot)) do
                    local t
                    if s.b then t = V.rayCapsule(o, d, s.a, s.b, s.r) else t = V.raySphere(o, d, s.a, s.r) end
                    if t and t < best then best, bBot, bZone = t, bot, s.zone end
                end
            end
        end
    end
    if bBot then return best, bBot, bZone end
    return nil
end

-- direcao corrigida para o alvo mais proximo do cone (cabeca tem prioridade)
function B.aimAssist(o, d, maxDeg)
    local bestAng, bestDir = maxDeg * V.RAD, nil
    for _, bot in ipairs(B.list) do
        if not bot.dead and bot.scale > 0.5 then
            for _, s in ipairs(shapes(bot)) do
                if s.zone == "head" or s.zone == "torso" or s.zone == "crab" then
                    local p = s.b and V.mid(s.a, s.b) or s.a
                    local v = V.sub(p, o)
                    local dist = V.len(v)
                    if dist > 0.3 and dist < 40 then
                        local ang = math.acos(V.clamp(V.dot(V.scale(v, 1 / dist), d), -1, 1))
                        local bias = s.zone == "head" and 0.9 or 1
                        if ang * bias < bestAng and G.level.lineClear(o, p) then
                            bestAng = ang * bias
                            bestDir = V.scale(v, 1 / dist)
                        end
                    end
                end
            end
        end
    end
    if bestDir then
        -- puxa so parte do caminho (mais natural)
        return V.norm(V.lerp(d, bestDir, 0.75))
    end
    return nil
end

local function segSegDist(a1, b1, a2, b2)
    -- aproximacao: amostra 5 pontos do primeiro segmento
    local best = 1e9
    for i = 0, 4 do
        local p = V.lerp(a1, b1, i / 4)
        local d
        if b2 then d = V.pointSegDist(p, a2, b2) else d = V.dist(p, a2) end
        if d < best then best = d end
    end
    return best
end

function B.meleeSweep(a, b, r, vel, dmg, src)
    for _, bot in ipairs(B.list) do
        if not bot.dead and (bot.hitCooldown or 0) <= 0 then
            local c = V.add(bot.pos, { 0, bot.boundY, 0 })
            if bot.latched or bot.grabbed then c = bot.pos end
            if V.pointSegDist(c, a, b) < bot.boundR + r + 0.2 then
                for _, s in ipairs(shapes(bot)) do
                    if segSegDist(a, b, s.a, s.b) < r + s.r then
                        bot.hitCooldown = 0.35
                        local dir = V.norm(vel)
                        A.sound3D("sounds/bat_hit.wav", s.a, 1, 0.9 + math.random() * 0.2)
                        B.damage(bot, s.zone, dmg, dir, s.a, "melee")
                        if not bot.dead then
                            bot.pos = V.add(bot.pos, V.scale({ dir[1], 0, dir[3] }, 0.25))
                        end
                        break
                    end
                end
            end
        end
    end
    -- rebater projeteis com o taco
    for _, p in ipairs(B.projectiles) do
        if not p.dead and V.pointSegDist(p.pos, a, b) < r + 0.12 then
            B.popProjectile(p, true)
        end
    end
end

-- soco com a mao (palma) — estilo Bonelab
function B.punch(p, vel, side)
    local sp = V.len(vel)
    if sp < 2.6 then return end
    for _, bot in ipairs(B.list) do
        if not bot.dead and (bot.hitCooldown or 0) <= 0 then
            for _, s in ipairs(shapes(bot)) do
                local d = s.b and V.pointSegDist(p, s.a, s.b) or V.dist(p, s.a)
                if d < s.r + 0.06 then
                    bot.hitCooldown = 0.3
                    local dir = V.norm(vel)
                    A.sound3D("sounds/punch.wav", p, 1, 0.9 + math.random() * 0.2)
                    B.damage(bot, s.zone, 8 + sp * 4, dir, p, "melee")
                    if bot.latched then B.detachCrab(bot, V.scale(dir, sp * 0.8)) end
                    return true
                end
            end
        end
    end
    for _, pr in ipairs(B.projectiles) do
        if not pr.dead and V.dist(pr.pos, p) < 0.15 then B.popProjectile(pr, true) end
    end
    return false
end

function B.noise(p, radius)
    for _, bot in ipairs(B.list) do
        if not bot.dead and bot.passive and bot.type ~= "dummy" and V.dist(bot.pos, p) < radius then bot.passive = false end
    end
end

---------------------------------------------------------------------------
-- Projeteis (plasma do atirador)
---------------------------------------------------------------------------
local projPool = {}

local function projObj()
    local o = table.remove(projPool)
    if o then A.setVisible(o, true); return o end
    o = A.prim("sphere", { parent = G.rig.world, scale = { 0.13, 0.13, 0.13 }, color = { 0.3, 0.9, 1 }, mat = { emit = { 0.6, 2.5, 3.5 }, noShadow = true } })
    return o
end

function B.fireProjectile(from, to, speed)
    local dir = V.norm(V.sub(to, from))
    local p = { pos = V.copy(from), vel = V.scale(dir, speed), t = 0, obj = projObj() }
    A.pos(p.obj, p.pos)
    B.projectiles[#B.projectiles + 1] = p
    A.sound3D("sounds/plasma.wav", from, 0.9)
end

function B.popProjectile(p, byPlayer)
    if p.dead then return end
    p.dead = true
    G.fx.sparks(p.pos, 8, nil, { 0.3, 0.9, 1 }, 2.5)
    A.sound3D("sounds/plasma_pop.wav", p.pos, 0.8)
    A.setVisible(p.obj, false)
    projPool[#projPool + 1] = p.obj
    if byPlayer and G.game then G.game.addScore(25, "abateu plasma") end
end

local function updateProjectiles(dt)
    local i = 1
    while i <= #B.projectiles do
        local p = B.projectiles[i]
        if not p.dead then
            p.t = p.t + dt
            local step = V.scale(p.vel, dt)
            local len = V.len(step)
            local hitStatic = G.level.raycast(p.pos, V.scale(step, 1 / math.max(len, 1e-6)), len + 0.06)
            p.pos = V.add(p.pos, step)
            A.pos(p.obj, p.pos)
            local s = 0.12 + math.sin(p.t * 40) * 0.015
            A.scale(p.obj, s, s, s)
            if G.player.hitTest(p.pos, 0.07) then
                G.player.damage(12, p.pos)
                B.popProjectile(p, false)
            elseif hitStatic or p.t > 5 then
                B.popProjectile(p, false)
            end
        end
        if p.dead then table.remove(B.projectiles, i) else i = i + 1 end
    end
end

-- consulta de raycast nos projeteis (para atirar neles)
function B.raycastProjectiles(o, d, maxT)
    local best, bp = maxT, nil
    for _, p in ipairs(B.projectiles) do
        if not p.dead then
            local t = V.raySphere(o, d, p.pos, 0.11)
            if t and t < best then best, bp = t, p end
        end
    end
    if bp then return best, bp end
end

---------------------------------------------------------------------------
-- Crab: agarrar, arrancar do rosto
---------------------------------------------------------------------------
function B.tryGrabCrab(side, palm)
    for _, bot in ipairs(B.list) do
        if not bot.dead and bot.type == "crab" and not bot.grabbed then
            local c = bot.pos
            if not bot.latched then c = V.add(bot.pos, { 0, bot.boundY, 0 }) end
            if V.dist(c, palm) < 0.2 then
                if bot.latched then
                    bot.latched = false
                    G.player.crabOff()
                end
                bot.grabbed = side
                bot.state = "grabbed"
                A.sound3D("sounds/crab_screech.wav", c, 0.9, 1.2)
                return bot
            end
        end
    end
    return nil
end

function B.releaseCrab(bot, vel)
    bot.grabbed = nil
    bot.state = "flying"
    bot.vel = V.scale(vel, 1.2)
    bot.flying = true
end

function B.detachCrab(bot, vel)
    if not bot.latched then return end
    bot.latched = false
    G.player.crabOff()
    bot.state = "flying"
    bot.flying = true
    bot.vel = V.add(vel, { 0, 1, 0 })
    bot.pos = V.madd(G.rig.head, G.rig.headB.f, 0.25)
end

---------------------------------------------------------------------------
-- Navegacao
---------------------------------------------------------------------------
local function steer(bot, desired, dt)
    local p = bot.pos
    local av = { 0, 0, 0 }
    local nearObstacle = false
    -- obstaculos (caixas do nivel)
    for _, ob in ipairs(G.rig.obstacles) do
        local bx = ob.box
        if bx then
            local cx = V.clamp(p[1], bx[1], bx[2])
            local cz = V.clamp(p[3], bx[3], bx[4])
            local dx, dz = p[1] - cx, p[3] - cz
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 1.0 and d > 1e-4 then
                nearObstacle = true
                local w = (1.0 - d) * 2.5
                av[1] = av[1] + dx / d * w
                av[3] = av[3] + dz / d * w
                -- contorna: tangente. O lado e escolhido uma vez (pela borda mais
                -- perto) e mantido, senao o bot fica indeciso e trava na quina.
                local tx, tz = -dz / d, dx / d
                if not bot.avoidSign then
                    local midX, midZ = (bx[1] + bx[2]) * 0.5, (bx[3] + bx[4]) * 0.5
                    local side = tx * (p[1] - midX) + tz * (p[3] - midZ)
                    bot.avoidSign = side >= 0 and 1 or -1
                end
                tx, tz = tx * bot.avoidSign, tz * bot.avoidSign
                av[1] = av[1] + tx * w * 1.2
                av[3] = av[3] + tz * w * 1.2
            end
        end
    end
    if nearObstacle then
        bot.avoidT = 1.2
    else
        bot.avoidT = (bot.avoidT or 0) - dt
        if bot.avoidT <= 0 then bot.avoidSign = nil end
    end
    -- separacao entre bots
    for _, o in ipairs(B.list) do
        if o ~= bot and not o.dead and not o.latched then
            local dx, dz = p[1] - o.pos[1], p[3] - o.pos[3]
            local d = math.sqrt(dx * dx + dz * dz)
            local minD = (bot.type == "crab" or o.type == "crab") and 0.45 or 0.75
            if d < minD and d > 1e-4 then
                av[1] = av[1] + dx / d * (minD - d) * 6
                av[3] = av[3] + dz / d * (minD - d) * 6
            end
        end
    end
    local v = V.add(desired, av)
    v[2] = 0
    local sp = V.len(desired)
    if V.len(v) > sp and sp > 0 then v = V.scale(V.norm(v), sp) end
    bot.vel = V.lerp(bot.vel, v, V.smoothK(6, dt))
    local np = V.madd(p, bot.vel, dt)
    -- empurra pra fora das caixas
    for _, ob in ipairs(G.rig.obstacles) do
        local bx = ob.box
        if bx then
            local r = bot.type == "crab" and 0.2 or 0.3
            local cx = V.clamp(np[1], bx[1], bx[2])
            local cz = V.clamp(np[3], bx[3], bx[4])
            local dx, dz = np[1] - cx, np[3] - cz
            local d = math.sqrt(dx * dx + dz * dz)
            if d < r then
                if d > 1e-4 then
                    np[1], np[3] = cx + dx / d * r, cz + dz / d * r
                else
                    np[1], np[3] = p[1], p[3]
                end
            end
        end
    end
    local bnd = G.rig.bounds
    np[1] = V.clamp(np[1], bnd[1] + 0.4, bnd[2] - 0.4)
    np[3] = V.clamp(np[3], bnd[3] + 0.4, bnd[4] - 0.4)
    np[2] = 0
    bot.pos = np
end

local function faceTowards(bot, target, dt, rate)
    local dx, dz = target[1] - bot.pos[1], target[3] - bot.pos[3]
    if dx * dx + dz * dz < 1e-4 then return 0 end
    local want = math.atan(dx, dz) * V.DEG
    local diff = ((want - bot.yaw + 540) % 360) - 180
    bot.yaw = bot.yaw + diff * V.smoothK(rate or 6, dt)
    return diff
end

---------------------------------------------------------------------------
-- Animacao do humanoide
---------------------------------------------------------------------------
local function animHumanoid(bot, dt, moveSpeed)
    local n = bot.nodes
    local sp = V.len(bot.vel)
    bot.phase = bot.phase + dt * (2.2 + sp * 3.2)
    local s = math.sin(bot.phase)
    local amp = V.clamp(sp / 2.2, 0, 1)
    local bob = math.abs(math.cos(bot.phase)) * 0.035 * amp
    local st = bot.stagger
    setNodePos(n.hips, 0, 0.95 + bob - st * 0.08, 0)
    setRot(n.hips, 0, s * 6 * amp, 0)
    local lean = 8 * amp - st * 30
    local atk = bot.attackPose or 0

    -- pernas
    setRot(n.hipL, -32 * s * amp, 0, 0)
    setRot(n.hipR, 32 * s * amp, 0, 0)
    setRot(n.kneeL, 45 * math.max(0, -math.cos(bot.phase)) * amp + st * 20, 0, 0)
    setRot(n.kneeR, 45 * math.max(0, math.cos(bot.phase)) * amp + st * 20, 0, 0)

    if bot.type == "gunner" then
        local aim = bot.aimPose or 0
        setRot(n.spine, lean, 0, 0)
        setRot(n.shoulderL, 25 * s * amp, 0, -8)
        setRot(n.elbowL, -20, 0, 0)
        setRot(n.shoulderR, -25 * s * amp * (1 - aim) - 88 * aim, 0, 8 * (1 - aim))
        setRot(n.elbowR, -15 * (1 - aim), 0, 0)
    elseif bot.type == "dummy" then
        setRot(n.spine, -st * 30, 0, 0)
        setRot(n.shoulderL, 0, 0, -75)
        setRot(n.shoulderR, 0, 0, 75)
        setRot(n.elbowL, 0, 0, 0)
        setRot(n.elbowR, 0, 0, 0)
        setRot(n.hipL, 0, 0, 0)
        setRot(n.hipR, 0, 0, 0)
    else
        -- grunt: bracos balancam; no ataque sobem e descem
        local raise = atk
        setRot(n.spine, lean + raise * 10, 0, 0)
        setRot(n.shoulderL, 28 * s * amp * (1 - raise) - 150 * raise, 0, -6)
        setRot(n.shoulderR, -28 * s * amp * (1 - raise) - 150 * raise, 0, 6)
        setRot(n.elbowL, -25 - 30 * raise, 0, 0)
        setRot(n.elbowR, -25 - 30 * raise, 0, 0)
    end
    -- cabeca olha para o jogador
    local head = G.rig.head
    local dx, dz = head[1] - bot.pos[1], head[3] - bot.pos[3]
    local want = math.atan(dx, dz) * V.DEG
    local rel = ((want - bot.yaw + 540) % 360) - 180
    rel = V.clamp(rel, -65, 65)
    local dist = math.sqrt(dx * dx + dz * dz)
    local pitch = -math.atan(head[2] - 1.65, math.max(0.3, dist)) * V.DEG
    setRot(n.neck, V.clamp(pitch, -30, 30), rel, 0)
end

local function animCrab(bot, dt)
    local sp = V.len(bot.vel)
    bot.phase = bot.phase + dt * (6 + sp * 10)
    for _, l in ipairs(bot.legs) do
        local a = math.sin(bot.phase + l.phase)
        local wiggle = (bot.latched or bot.grabbed) and 30 or 18
        setRot(l.node, 0, a * wiggle, (bot.latched or bot.grabbed) and a * 25 or 0)
    end
end

---------------------------------------------------------------------------
-- IA por tipo
---------------------------------------------------------------------------
local function thinkGrunt(bot, dt)
    local head = G.rig.head
    local target = { head[1], 0, head[3] }
    local dist = V.distXZ(bot.pos, target)
    local T = bot.T
    if bot.state == "attack" then
        bot.attackT = bot.attackT + dt
        bot.vel = V.scale(bot.vel, math.exp(-dt * 8))
        faceTowards(bot, target, dt, 8)
        if bot.attackT < 0.45 then
            bot.attackPose = bot.attackT / 0.45
        elseif not bot.struck then
            bot.struck = true
            bot.attackPose = 0.2
            A.sound3D("sounds/swing.wav", V.add(bot.pos, { 0, 1.4, 0 }), 0.9)
            if dist < 1.15 then
                G.player.damage(14, V.add(bot.pos, { 0, 1.4, 0 }))
            end
        elseif bot.attackT > 0.95 then
            bot.state = "chase"
            bot.cooldown = 0.5 + math.random() * 0.6
            bot.attackPose = 0
        else
            bot.attackPose = math.max(0, (bot.attackPose or 0) - dt * 3)
        end
        return
    end
    bot.state = "chase"
    local spd = (dist > 4 and T.speed or T.run) * bot.speedMult
    if bot.stagger > 0.05 then spd = spd * 0.2 end
    local desired = { 0, 0, 0 }
    if dist > 0.85 then desired = V.scale(V.norm(V.sub(target, bot.pos)), spd) end
    steer(bot, desired, dt)
    faceTowards(bot, V.add(bot.pos, bot.vel), dt, 7)
    if dist < 1.0 and bot.cooldown <= 0 and bot.stagger < 0.1 then
        bot.state = "attack"
        bot.attackT = 0
        bot.struck = false
    end
end

local function thinkGunner(bot, dt)
    local head = G.rig.head
    local target = { head[1], 0, head[3] }
    local dist = V.distXZ(bot.pos, target)
    local T = bot.T
    local toP = V.norm(V.sub(target, bot.pos))
    local desired
    bot.strafeT = bot.strafeT - dt
    if bot.strafeT <= 0 then bot.strafe = -bot.strafe; bot.strafeT = 1.5 + math.random() * 2 end
    local side = { toP[3] * bot.strafe, 0, -toP[1] * bot.strafe }
    local eye = V.add(bot.pos, { 0, 1.65, 0 })
    local los = G.level.lineClear(eye, head)
    if dist > 9 or not los then
        desired = V.scale(V.add(toP, V.scale(side, 0.4)), T.speed * bot.speedMult)
    elseif dist < 4.5 then
        desired = V.scale(V.add(V.scale(toP, -1), V.scale(side, 0.5)), T.speed * bot.speedMult)
    else
        desired = V.scale(side, T.speed * 0.7 * bot.speedMult)
    end
    if bot.charging then desired = V.scale(desired, 0.15) end
    steer(bot, desired, dt)
    faceTowards(bot, target, dt, 5)
    bot.aimPose = V.clamp((bot.aimPose or 0) + (los and dt * 2 or -dt * 2), 0, 1)

    if bot.charging then
        bot.chargeT = bot.chargeT + dt
        local k = bot.chargeT / 0.7
        if bot.cannon then A.scale(bot.cannon.obj, 0.07 + 0.05 * k, 0.07 + 0.05 * k, 0.07 + 0.05 * k) end
        if bot.chargeT >= 0.7 then
            bot.charging = false
            if bot.cannon then A.scale(bot.cannon.obj, 0.07, 0.07, 0.07) end
            if los and bot.stagger < 0.2 then
                local s = shapes(bot)
                local from = s[7] and s[7].b or eye
                local aimAt = V.add(head, { (math.random() - 0.5) * 0.25, -0.15 + (math.random() - 0.5) * 0.2, (math.random() - 0.5) * 0.25 })
                B.fireProjectile(from, aimAt, 6.5)
            end
            bot.cooldown = 1.8 + math.random() * 1.2
        end
    elseif bot.cooldown <= 0 and los and dist < 14 and bot.aimPose > 0.8 then
        bot.charging = true
        bot.chargeT = 0
        A.sound3D("sounds/charge.wav", eye, 0.7)
    end
end

local function thinkCrab(bot, dt)
    local head = G.rig.head
    local hb = G.rig.headB
    if bot.state == "latched" then
        -- grudado no rosto: na frente dos olhos, olhando para o jogador
        bot.pos = V.add(V.madd(head, hb.f, 0.16), V.scale(hb.u, -0.03))
        -- costas do crab para fora (u = frente da cabeca), patas no rosto
        bot.B = V.basis(hb.u, hb.f)
        bot.biteT = (bot.biteT or 0) + dt
        if bot.biteT > 0.5 then
            bot.biteT = 0
            G.player.damage(5, bot.pos, true)
        end
        return
    elseif bot.state == "grabbed" then
        local h = G.controls.hands[bot.grabbed]
        bot.pos = V.copy(h.palm)
        bot.B = V.basis(h.basis.f, V.scale(h.basis.r, -1))
        return
    elseif bot.state == "flying" or bot.state == "leap" then
        bot.vel[2] = bot.vel[2] - 9.81 * dt
        local np = V.madd(bot.pos, bot.vel, dt)
        -- alcancou o rosto?
        if bot.state == "leap" and V.dist(np, head) < 0.35 then
            bot.state = "latched"
            bot.latched = true
            bot.flying = false
            G.player.crabOn(bot)
            A.sound3D("sounds/crab_screech.wav", head, 1)
            return
        end
        local sp = V.len(bot.vel)
        local dir = V.scale(bot.vel, 1 / math.max(sp, 1e-5))
        local t, n = G.level.raycast(bot.pos, dir, sp * dt + 0.12)
        -- bater em outros bots quando arremessado
        if bot.state == "flying" and sp > 3 then
            for _, o in ipairs(B.list) do
                if o ~= bot and not o.dead and o.type ~= "crab" then
                    if V.dist(np, V.add(o.pos, { 0, 1.1, 0 })) < 0.5 then
                        B.damage(o, "torso", sp * 6, dir, np, "melee")
                        B.damage(bot, "crab", sp * 4, dir, np, "melee")
                        bot.vel = V.scale(bot.vel, -0.3)
                    end
                end
            end
        end
        if t or np[2] < 0.1 then
            if sp > 5 then B.damage(bot, "crab", (sp - 4) * 5, dir, np, "melee") end
            if t then np = V.madd(bot.pos, dir, math.max(0, t - 0.12)) end
            np[2] = 0
            bot.state = "chase"
            bot.flying = false
            bot.vel = { 0, 0, 0 }
            bot.cooldown = 1.2
        end
        bot.pos = np
        bot.B = V.basisFromEuler(0, bot.yaw, 0)
        return
    end
    -- no chao: corre ate o jogador e pula
    local target = { head[1], 0, head[3] }
    local dist = V.distXZ(bot.pos, target)
    local desired = V.scale(V.norm(V.sub(target, bot.pos)), (dist > 4 and bot.T.speed or bot.T.run) * bot.speedMult)
    if bot.stagger > 0.05 then desired = V.scale(desired, 0.2) end
    steer(bot, desired, dt)
    faceTowards(bot, target, dt, 10)
    bot.B = V.basisFromEuler(0, bot.yaw, 0)
    if dist < 2.4 and bot.cooldown <= 0 and G.level.lineClear(V.add(bot.pos, { 0, 0.3, 0 }), head) then
        -- salto balistico ate a cabeca (de perto o pulo e mais curto)
        local start = V.add(bot.pos, { 0, 0.2, 0 })
        local tFlight = 0.38 + 0.08 * dist
        local d = V.sub(head, start)
        bot.vel = { d[1] / tFlight, (d[2] + 0.5 * 9.81 * tFlight * tFlight) / tFlight, d[3] / tFlight }
        bot.pos = start
        bot.state = "leap"
        bot.flying = true
        A.sound3D("sounds/crab_screech.wav", start, 0.9)
    end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function B.update(dt)
    for _, bot in ipairs(B.list) do
        if not bot.dead then
            bot.t = bot.t + dt
            bot.cooldown = bot.cooldown - dt
            bot.hitCooldown = (bot.hitCooldown or 0) - dt
            bot.stagger = math.max(0, bot.stagger - dt * 1.5)
            if bot.flash > 0 then
                bot.flash = bot.flash - dt
                if bot.flash <= 0 then unflash(bot) end
            end

            if bot.state == "spawn" then
                bot.scale = math.min(1, bot.t / 0.7)
                local fl = (math.floor(bot.t * 20) % 2 == 0) and 1 or 0.85
                A.scale(bot.rootObj, bot.scale * fl)
                if bot.t >= 0.7 then
                    A.scale(bot.rootObj, 1)
                    bot.scale = 1
                    bot.state = bot.type == "crab" and "chase" or "chase"
                end
            elseif bot.type == "dummy" or bot.passive then
                bot.vel = { 0, 0, 0 }
            elseif bot.type == "grunt" then
                thinkGrunt(bot, dt)
            elseif bot.type == "gunner" then
                thinkGunner(bot, dt)
            elseif bot.type == "crab" then
                thinkCrab(bot, dt)
            end

            if not bot.dead then
                if bot.type == "crab" then
                    animCrab(bot, dt)
                    if bot.state ~= "latched" and bot.state ~= "grabbed" and not bot.flying then
                        bot.B = V.basisFromEuler(0, bot.yaw, 0)
                    end
                    A.pos(bot.rootObj, bot.pos)
                    A.rotBasis(bot.rootObj, bot.B)
                else
                    animHumanoid(bot, dt)
                    bot.B = V.basisFromEuler(0, bot.yaw, 0)
                    A.pos(bot.rootObj, bot.pos)
                    A.rot(bot.rootObj, 0, bot.yaw, 0)
                end
            end
        end
    end
    -- remove mortos da lista
    local i = 1
    while i <= #B.list do
        if B.list[i].dead then table.remove(B.list, i) else i = i + 1 end
    end
    updateProjectiles(dt)
    updateDebris(dt)
end

function B.aliveCount(includeDummy)
    local n = 0
    for _, b in ipairs(B.list) do
        if not b.dead and (includeDummy or b.type ~= "dummy") then n = n + 1 end
    end
    return n
end

function B.clear(includeDummy)
    for _, b in ipairs(B.list) do
        if not b.dead and (includeDummy or b.type ~= "dummy") then
            if b.latched then G.player.crabOff() end
            b.dead = true
            A.destroy(b.rootObj)
        end
    end
    for _, p in ipairs(B.projectiles) do B.popProjectile(p, false) end
end

function B.init(ctx)
    G = ctx
end

return B
