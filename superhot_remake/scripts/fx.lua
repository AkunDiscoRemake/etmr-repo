-- fx.lua — efeitos do SUPERHOT, todos no TEMPO DO JOGO (congelam quando voce para):
-- estilhacos de cristal vermelho, cacos de vidro, flash do cano, faiscas, marcas, surgimento.

local V = require("vec")
local A = require("api")

local F = {}

local pools = {}
local active = {}

F.RED = { 1.0, 0.08, 0.05 }
F.RED_EMIT = { 1.6, 0.06, 0.03 }

local function pool(name, n, make)
    local p = { free = {} }
    for i = 1, n do
        local o = make(i)
        A.setVisible(o, false)
        p.free[#p.free + 1] = o
    end
    pools[name] = p
end

local function take(name)
    local o = table.remove(pools[name].free)
    if not o then
        for i, e in ipairs(active) do
            if e.pool == name then o = e.obj; table.remove(active, i); break end
        end
    end
    if o then A.setVisible(o, true) end
    return o
end

local function release(e)
    A.setVisible(e.obj, false)
    local p = pools[e.pool]
    p.free[#p.free + 1] = e.obj
end

F.statics = nil      -- funcao de raycast do nivel (definida pelo jogo)

function F.init(world)
    pool("shard", 170, function()
        return A.prim("cube", { parent = world, color = F.RED, mat = { emit = F.RED_EMIT, smooth = 0.95, metal = 0.1 } })
    end)
    pool("glass", 40, function()
        return A.prim("cube", { parent = world, color = { 0.85, 0.9, 0.95 }, mat = { smooth = 0.98, metal = 0.2 } })
    end)
    pool("flash", 8, function()
        return A.prim("sphere", { parent = world, color = { 1, 0.95, 0.85 }, mat = { emit = { 4, 3.6, 3 }, noShadow = true } })
    end)
    pool("flashx", 8, function()
        return A.prim("cube", { parent = world, color = { 1, 0.95, 0.9 }, mat = { emit = { 4, 3.6, 3 }, noShadow = true } })
    end)
    pool("spark", 60, function()
        return A.prim("cube", { parent = world, color = { 1, 1, 1 }, mat = { emit = { 2.5, 2.5, 2.5 }, noShadow = true } })
    end)
    pool("hole", 40, function()
        return A.prim("quad", { parent = world, color = { 0.12, 0.12, 0.13 }, tex = "images/bullethole.png" })
    end)
    pool("spawn", 8, function()
        return A.prim("cylinder", { parent = world, color = F.RED, mat = { emit = F.RED_EMIT, noShadow = true } })
    end)
end

-- Estilhacar: pontos de origem (partes do corpo), direcao do impacto
function F.shatter(points, dir, force, count, kind)
    kind = kind or "shard"
    count = count or 24
    for i = 1, count do
        local o = take(kind)
        if not o then return end
        local p = points[((i - 1) % #points) + 1]
        local jitter = { (math.random() - 0.5) * 0.18, (math.random() - 0.5) * 0.18, (math.random() - 0.5) * 0.18 }
        local pos = V.add(p, jitter)
        local spread = V.norm({ math.random() - 0.5, math.random() * 0.8 - 0.1, math.random() - 0.5 })
        local v = V.add(V.scale(dir, force * (0.4 + math.random() * 0.9)), V.scale(spread, 1.2 + math.random() * 2.2))
        local s = (kind == "shard") and (0.035 + math.random() * 0.08) or (0.015 + math.random() * 0.03)
        local sx, sy, sz = s * (0.6 + math.random()), s * (0.3 + math.random() * 0.7), s * (0.6 + math.random())
        A.scale(o, sx, sy, sz)
        A.pos(o, pos)
        active[#active + 1] = {
            obj = o, pool = kind, t = 0, life = 3.5 + math.random() * 2, kind = "shard",
            p = pos, v = v, axis = V.norm({ math.random() - 0.5, math.random() - 0.5, math.random() - 0.5 }),
            spin = 200 + math.random() * 600, B = V.identity(), s = { sx, sy, sz }, rest = false,
        }
    end
end

function F.muzzle(p, B, big)
    local s = big and 1.7 or 1
    local o = take("flash")
    if o then
        A.pos(o, V.madd(p, B.f, 0.02))
        A.scale(o, 0.06 * s, 0.06 * s, 0.11 * s)
        A.rotBasis(o, B)
        active[#active + 1] = { obj = o, pool = "flash", t = 0, life = 0.06, kind = "fade" }
    end
    local x = take("flashx")
    if x then
        A.pos(x, V.madd(p, B.f, 0.04 * s))
        A.rotBasis(x, V.mulMM(B, V.axisAngle({ 0, 0, 1 }, math.random() * 90)))
        A.scale(x, 0.14 * s, 0.012, 0.012)
        active[#active + 1] = { obj = x, pool = "flashx", t = 0, life = 0.05, kind = "fade" }
    end
end

function F.sparks(p, n, normal, color, speed)
    speed = speed or 2
    for _ = 1, n do
        local o = take("spark")
        if not o then return end
        if color then A.color(o, color) else A.colorRGB(o, 1, 1, 1) end
        local dir = V.norm({
            (normal and normal[1] or 0) + (math.random() - 0.5) * 1.6,
            (normal and normal[2] or 0.3) + (math.random() - 0.2) * 1.2,
            (normal and normal[3] or 0) + (math.random() - 0.5) * 1.6,
        })
        local s = 0.006 + math.random() * 0.01
        A.scale(o, s, s, s * 2.5)
        A.pos(o, p)
        active[#active + 1] = { obj = o, pool = "spark", t = 0, life = 0.3 + math.random() * 0.4, kind = "spark",
            p = V.copy(p), v = V.scale(dir, speed * (0.5 + math.random())), s = s }
    end
end

function F.hole(p, n)
    local o = take("hole")
    if not o then return end
    A.pos(o, V.madd(p, n, 0.004))
    A.rotBasis(o, V.basis(V.scale(n, -1), math.abs(n[2]) > 0.9 and { 0, 0, 1 } or { 0, 1, 0 }))
    local s = 0.03 + math.random() * 0.015
    A.scale(o, s, s, 1)
    active[#active + 1] = { obj = o, pool = "hole", t = 0, life = 60, kind = "hole" }
end

-- surgimento de inimigo: coluna vermelha que encolhe
function F.spawn(p)
    local o = take("spawn")
    if not o then return end
    A.pos(o, { p[1], p[2] + 0.95, p[3] })
    A.scale(o, 0.7, 0.95, 0.7)
    active[#active + 1] = { obj = o, pool = "spawn", t = 0, life = 0.6, kind = "spawn" }
end

local floorRay = nil
function F.setRaycast(fn) floorRay = fn end

function F.update(gdt, dt)
    local i = 1
    while i <= #active do
        local e = active[i]
        -- flashes usam tempo real (senao ficariam 10 s na tela com o tempo parado)
        local step = (e.kind == "fade" or e.kind == "spawn") and dt or gdt
        e.t = e.t + step
        if e.t >= e.life then
            release(e)
            table.remove(active, i)
        else
            local o = e.obj
            if e.kind == "shard" then
                -- com o tempo quase parado, acumula e so move quando faz diferenca visivel
                e.acc = (e.acc or 0) + gdt
                if not e.rest and e.acc >= 0.004 then
                    local gdt = e.acc
                    e.acc = 0
                    e.v[2] = e.v[2] - 9.81 * gdt
                    local np = V.madd(e.p, e.v, gdt)
                    if np[2] < 0.01 then
                        np[2] = 0.01
                        e.v = V.scale(e.v, 0.35)
                        e.v[2] = math.abs(e.v[2]) * 0.5
                        e.spin = e.spin * 0.5
                        if V.len(e.v) < 0.15 then e.rest = true end
                    elseif floorRay then
                        local d = V.sub(np, e.p)
                        local l = V.len(d)
                        if l > 1e-5 then
                            local t, n = floorRay(e.p, V.scale(d, 1 / l), l)
                            if t then
                                np = V.madd(e.p, V.scale(d, 1 / l), math.max(0, t - 0.01))
                                local vn = V.dot(e.v, n)
                                e.v = V.scale(V.madd(e.v, n, -2 * vn), 0.4)
                            end
                        end
                    end
                    e.p = np
                    e.B = V.mulMM(V.axisAngle(e.axis, e.spin * gdt), e.B)
                    A.pos(o, e.p)
                    A.rotBasis(o, e.B)
                end
                local k = e.life - e.t
                if k < 0.5 then
                    local f = math.max(0.01, k / 0.5)
                    A.scale(o, e.s[1] * f, e.s[2] * f, e.s[3] * f)
                end
            elseif e.kind == "spark" then
                e.v[2] = e.v[2] - 9.8 * gdt
                e.p = V.madd(e.p, e.v, gdt)
                A.pos(o, e.p)
                local s = e.s * (1 - e.t / e.life)
                A.scale(o, s, s, s * 2.5)
            elseif e.kind == "spawn" then
                local k = e.t / e.life
                A.scale(o, 0.7 * (1 - k), 0.95 + k * 0.3, 0.7 * (1 - k))
            end
            i = i + 1
        end
    end
end

function F.clear()
    for _, e in ipairs(active) do release(e) end
    active = {}
end

return F
