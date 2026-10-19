-- fx.lua — efeitos visuais com pool de objetos (nada e criado/destruido durante o tiroteio):
-- tracos de bala, flash do cano, faiscas, marcas de tiro, explosoes, anel de spawn.

local V = require("vec")
local A = require("api")

local F = {}

local pools = {}
local active = {}

local function pool(name, n, make)
    local p = { free = {}, name = name }
    for i = 1, n do
        local o = make(i)
        A.setVisible(o, false)
        p.free[#p.free + 1] = o
    end
    pools[name] = p
    return p
end

local function take(name)
    local p = pools[name]
    local o = table.remove(p.free)
    if not o then
        -- recicla o mais antigo desse tipo
        for i, e in ipairs(active) do
            if e.pool == name then
                o = e.obj
                table.remove(active, i)
                break
            end
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

function F.init(world)
    F.world = world
    pool("tracer", 24, function()
        return A.prim("cube", { parent = world, color = { 1, 0.85, 0.45 }, mat = { emit = { 3, 2.2, 1.0 }, noShadow = true } })
    end)
    pool("flash", 8, function()
        return A.prim("sphere", { parent = world, color = { 1, 0.75, 0.3 }, mat = { emit = { 4, 2.5, 0.8 }, noShadow = true } })
    end)
    pool("flashx", 8, function()
        return A.prim("cube", { parent = world, color = { 1, 0.9, 0.5 }, mat = { emit = { 4, 3, 1 }, noShadow = true } })
    end)
    pool("spark", 60, function()
        return A.prim("cube", { parent = world, color = { 1, 0.7, 0.2 }, mat = { emit = { 2.5, 1.2, 0.2 }, noShadow = true } })
    end)
    pool("hole", 40, function()
        return A.prim("quad", { parent = world, color = { 0.05, 0.05, 0.05 }, tex = "images/bullethole.png" })
    end)
    pool("boom", 4, function()
        return A.prim("sphere", { parent = world, color = { 1, 0.55, 0.1 }, mat = { emit = { 5, 2, 0.3 }, noShadow = true } })
    end)
    pool("ring", 6, function()
        return A.prim("cylinder", { parent = world, color = { 0.2, 0.8, 1 }, mat = { emit = { 0.5, 2, 3 }, noShadow = true } })
    end)
    pool("shell", 16, function()
        return A.prim("cylinder", { parent = world, color = { 0.85, 0.65, 0.2 }, mat = { metal = 0.9, smooth = 0.8 } })
    end)
end

-- Traco da bala entre a ponta do cano e o ponto atingido
function F.tracer(a, b)
    local o = take("tracer")
    if not o then return end
    local d = V.sub(b, a)
    local len = V.len(d)
    -- desenha so um "risco" de ate 3 m que corre rumo ao alvo
    local seg = math.min(len, 3)
    local m = V.madd(a, V.norm(d), seg * 0.5)
    A.pos(o, m)
    A.rotBasis(o, V.basis(d, { 0, 1, 0 }))
    A.scale(o, 0.006, 0.006, seg)
    active[#active + 1] = { obj = o, pool = "tracer", t = 0, life = 0.06, kind = "tracer", a = a, dir = V.norm(d), len = len, seg = seg }
end

function F.muzzle(p, B, big)
    local s = big and 1.6 or 1
    local o = take("flash")
    if o then
        A.pos(o, p)
        local r = (0.05 + math.random() * 0.03) * s
        A.scale(o, r, r, r * 1.8)
        A.rotBasis(o, B)
        active[#active + 1] = { obj = o, pool = "flash", t = 0, life = 0.05, kind = "fade" }
    end
    local x = take("flashx")
    if x then
        A.pos(x, V.madd(p, B.f, 0.03 * s))
        local rb = V.mulMM(B, V.axisAngle({ 0, 0, 1 }, math.random() * 90))
        A.rotBasis(x, rb)
        A.scale(x, 0.12 * s, 0.012, 0.012)
        active[#active + 1] = { obj = x, pool = "flashx", t = 0, life = 0.04, kind = "fade" }
    end
end

-- Faiscas: count particulas com velocidade simulada em Lua
function F.sparks(p, n, normal, color, speed)
    speed = speed or 2.5
    for i = 1, n do
        local o = take("spark")
        if not o then return end
        if color then A.color(o, color) else A.colorRGB(o, 1, 0.7, 0.2) end
        local dir = V.norm({
            (normal and normal[1] or 0) + (math.random() - 0.5) * 1.6,
            (normal and normal[2] or 0.3) + (math.random() - 0.2) * 1.2,
            (normal and normal[3] or 0) + (math.random() - 0.5) * 1.6,
        })
        local s = 0.008 + math.random() * 0.012
        A.scale(o, s, s, s * 2.5)
        A.pos(o, p)
        active[#active + 1] = {
            obj = o, pool = "spark", t = 0, life = 0.25 + math.random() * 0.35, kind = "spark",
            p = V.copy(p), v = V.scale(dir, speed * (0.5 + math.random())), s = s,
        }
    end
end

-- Marca de tiro na parede (quad alinhado com a normal)
function F.hole(p, n)
    local o = take("hole")
    if not o then return end
    A.pos(o, V.madd(p, n, 0.004))
    -- o quad da Unity olha para -Z, entao f = -normal
    A.rotBasis(o, V.basis(V.scale(n, -1), math.abs(n[2]) > 0.9 and { 0, 0, 1 } or { 0, 1, 0 }))
    local s = 0.035 + math.random() * 0.02
    A.scale(o, s, s, 1)
    active[#active + 1] = { obj = o, pool = "hole", t = 0, life = 25, kind = "hole" }
end

function F.explosion(p, radius)
    local o = take("boom")
    if o then
        A.pos(o, p)
        A.scale(o, 0.2, 0.2, 0.2)
        active[#active + 1] = { obj = o, pool = "boom", t = 0, life = 0.45, kind = "boom", r = radius }
    end
    F.sparks(p, 18, { 0, 1, 0 }, { 1, 0.6, 0.15 }, 6)
end

-- Anel de teleporte (spawn de bot)
function F.ring(p, color)
    local o = take("ring")
    if not o then return end
    A.pos(o, { p[1], p[2] + 0.02, p[3] })
    if color then A.color(o, color) end
    A.scale(o, 0.1, 0.01, 0.1)
    active[#active + 1] = { obj = o, pool = "ring", t = 0, life = 1.2, kind = "ring" }
end

-- Capsula ejetada
function F.shell(p, vel)
    local o = take("shell")
    if not o then return end
    A.scale(o, 0.009, 0.01, 0.009)
    A.pos(o, p)
    active[#active + 1] = {
        obj = o, pool = "shell", t = 0, life = 1.2, kind = "shell",
        p = V.copy(p), v = vel, rx = math.random() * 360, spin = 700 + math.random() * 600,
    }
end

function F.update(dt)
    local i = 1
    while i <= #active do
        local e = active[i]
        e.t = e.t + dt
        local k = e.t / e.life
        if k >= 1 then
            release(e)
            table.remove(active, i)
        else
            local o = e.obj
            if e.kind == "spark" then
                e.v[2] = e.v[2] - 9.8 * dt
                e.p = V.madd(e.p, e.v, dt)
                if e.p[2] < 0.01 then e.p[2] = 0.01; e.v[2] = -e.v[2] * 0.4; e.v[1] = e.v[1] * 0.6; e.v[3] = e.v[3] * 0.6 end
                A.pos(o, e.p)
                local s = e.s * (1 - k)
                A.scale(o, s, s, s * 2.5)
            elseif e.kind == "shell" then
                e.v[2] = e.v[2] - 9.8 * dt
                e.p = V.madd(e.p, e.v, dt)
                if e.p[2] < 0.01 then e.p[2] = 0.01; e.v[2] = -e.v[2] * 0.35; e.v[1] = e.v[1] * 0.5; e.v[3] = e.v[3] * 0.5; e.spin = e.spin * 0.5 end
                e.rx = e.rx + e.spin * dt
                A.pos(o, e.p)
                A.rot(o, e.rx, e.rx * 0.7, 90)
            elseif e.kind == "tracer" then
                -- o risco corre ate o alvo
                local travel = math.min(e.len - e.seg * 0.5, e.len * k + e.seg * 0.5)
                A.pos(o, V.madd(e.a, e.dir, travel))
            elseif e.kind == "fade" then
                -- encolhe rapido
            elseif e.kind == "boom" then
                local r = e.r * 2 * (0.3 + 0.7 * math.sqrt(k))
                A.scale(o, r, r, r)
                local c = 1 - k
                A.colorRGB(o, 1, 0.3 + 0.5 * c, 0.1 * c)
            elseif e.kind == "ring" then
                local r = 0.1 + 1.1 * math.min(1, k * 2)
                local h = 0.01 + 1.6 * math.sin(k * math.pi)
                A.scale(o, r, h, r)
            end
            i = i + 1
        end
    end
end

return F
