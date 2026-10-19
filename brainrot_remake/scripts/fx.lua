-- fx.lua — efeitos: brilhos, confete, "+$" flutuando, poeira, estrelinhas de atordoado.
-- Tudo em pools (os objetos sao criados uma vez e reaproveitados).

local V = require("vec")
local A = require("api")
local Tx = require("text3d")

local F = {}

local parts = {}       -- particulas ativas
local pool = {}
local texts = {}
local G

local function getPart()
    local p = table.remove(pool)
    if p then
        A.setVisible(p.o, true, p.s, p.s, p.s)
        return p
    end
    local o = A.prim("cube", { parent = F.root, scale = { 0.06, 0.06, 0.06 } })
    A.material(o, { noShadow = true, emit = { 0.6, 0.6, 0.6 } })
    return { o = o }
end

local function release(p)
    A.setVisible(p.o, false)
    pool[#pool + 1] = p
end

function F.init(ctx, root)
    G = ctx
    F.root = A.empty("fx", root)
    for i = 1, 6 do
        local t = Tx.new({ parent = F.root, h = 0.2 })
        A.setVisible(t.root, false)
        texts[i] = { t = t, life = 0 }
    end
end

-- opt: pos, vel, color, size, life, grav, spin
function F.emit(opt)
    if #parts > 160 then return end
    local p = getPart()
    p.pos = V.copy(opt.pos)
    p.vel = opt.vel or { 0, 0, 0 }
    p.life = opt.life or 1
    p.max = p.life
    p.grav = opt.grav or 0
    p.s = opt.size or 0.06
    p.spin = opt.spin or 0
    p.rot = math.random() * 360
    p.shrink = opt.shrink ~= false
    A.color(p.o, opt.color or { 1, 1, 1 })
    A.scale(p.o, p.s, p.s, p.s)
    A.pos(p.o, p.pos)
    parts[#parts + 1] = p
end

function F.sparkle(pos, color, n)
    for _ = 1, n or 14 do
        local a = math.random() * 6.283
        local up = 0.8 + math.random() * 1.6
        F.emit({ pos = pos, vel = { math.cos(a) * 1.2, up, math.sin(a) * 1.2 }, color = color or { 1, 0.9, 0.3 }, size = 0.05 + math.random() * 0.05, life = 0.8, grav = 3, spin = 400 })
    end
end

function F.confetti(pos, n)
    local cols = { { 1, 0.3, 0.3 }, { 0.3, 0.6, 1 }, { 1, 0.9, 0.2 }, { 0.4, 1, 0.4 }, { 1, 0.4, 0.9 } }
    for k = 1, n or 30 do
        local a = math.random() * 6.283
        F.emit({ pos = pos, vel = { math.cos(a) * 2.2, 2 + math.random() * 3, math.sin(a) * 2.2 }, color = cols[k % 5 + 1], size = 0.06, life = 1.6, grav = 5, spin = 600 })
    end
end

function F.dust(pos, n)
    for _ = 1, n or 6 do
        local a = math.random() * 6.283
        F.emit({ pos = V.add(pos, { 0, 0.05, 0 }), vel = { math.cos(a) * 0.8, 0.4, math.sin(a) * 0.8 }, color = { 0.85, 0.82, 0.75 }, size = 0.1, life = 0.5 })
    end
end

function F.hit(pos)
    for _ = 1, 12 do
        local a = math.random() * 6.283
        F.emit({ pos = pos, vel = { math.cos(a) * 2.5, 1 + math.random() * 2, math.sin(a) * 2.5 }, color = { 1, 1, 0.6 }, size = 0.07, life = 0.45, grav = 4, spin = 800 })
    end
end

-- texto "+$123" subindo
function F.popText(pos, str, color)
    local best = texts[1]
    for _, e in ipairs(texts) do if e.life < best.life then best = e end end
    best.life = 1.4
    best.pos = V.copy(pos)
    Tx.set(best.t, str, color or { 0.4, 1, 0.45 })
    A.setVisible(best.t.root, true)
    A.pos(best.t.root, pos)
end

function F.update(dt, viewer)
    local n = #parts
    local i = 1
    while i <= n do
        local p = parts[i]
        p.life = p.life - dt
        if p.life <= 0 then
            release(p)
            parts[i] = parts[n]
            parts[n] = nil
            n = n - 1
        else
            p.vel[2] = p.vel[2] - p.grav * dt
            p.pos = V.madd(p.pos, p.vel, dt)
            if p.pos[2] < 0.03 then p.pos[2] = 0.03; p.vel[2] = 0; p.vel[1] = p.vel[1] * 0.8; p.vel[3] = p.vel[3] * 0.8 end
            A.pos(p.o, p.pos)
            p.rot = p.rot + p.spin * dt
            A.rot(p.o, p.rot, p.rot * 0.7, 0)
            if p.shrink then
                local k = math.min(1, p.life / p.max * 2)
                A.scale(p.o, p.s * k, p.s * k, p.s * k)
            end
            i = i + 1
        end
    end
    for _, e in ipairs(texts) do
        if e.life > 0 then
            e.life = e.life - dt
            e.pos[2] = e.pos[2] + dt * 0.45
            A.pos(e.t.root, e.pos)
            local d = { e.pos[1] - viewer[1], 0, e.pos[3] - viewer[3] }
            A.rot(e.t.root, 0, math.atan(d[1], d[3]) * V.DEG, 0)
            if e.life <= 0 then A.setVisible(e.t.root, false) end
        end
    end
end

return F
