-- level.lua — monta as salas brancas do SUPERHOT a partir de dados (levels.lua).
-- Guarda caixas estaticas (raycast das balas/objetos) e obstaculos (jogador e inimigos).

local V = require("vec")
local A = require("api")

local L = {}

L.statics = {}
L.obstacles = {}       -- { minX, maxX, minZ, maxZ }
L.bounds = { -5, 5, -5, 5 }
L.root = nil

local WHITE = { 0.95, 0.95, 0.97 }
local W_EMIT = { 0.3, 0.3, 0.32 }
local M_WALL = { smooth = 0.35, emit = W_EMIT }
local M_FLOOR = { smooth = 0.75, emit = { 0.16, 0.16, 0.17 } }
local M_BLOCK = { smooth = 0.5, emit = { 0.24, 0.24, 0.25 } }
local GREY = { 0.72, 0.73, 0.76 }

local rig

local function prim(kind, pos, scale, color, mat, tex, rot)
    return A.prim(kind, { parent = L.root, pos = pos, scale = scale, color = color, mat = mat, tex = tex, rot = rot })
end

local function static(c, s, obstacle)
    local h = V.scale(s, 0.5)
    L.statics[#L.statics + 1] = { mn = V.sub(c, h), mx = V.add(c, h) }
    if obstacle then
        L.obstacles[#L.obstacles + 1] = { c[1] - h[1], c[1] + h[1], c[3] - h[3], c[3] + h[3] }
    end
end

local function block(c, s, color, mat, tex, obstacle)
    local o = prim("cube", c, s, color or WHITE, mat or M_BLOCK, tex)
    static(c, s, obstacle ~= false)
    return o
end

-- pecas de cenario
local K = {}

function K.block(b)
    local h = b.h or 1
    block({ b.x, (b.y0 or 0) + h / 2, b.z }, { b.w, h, b.d }, b.col)
end

function K.pillar(b)
    local h = L.height
    block({ b.x, h / 2, b.z }, { b.w, h, b.d or b.w }, WHITE, M_WALL, "images/wall_white.png")
end

function K.table(b)
    local h = b.h or 0.76
    prim("cube", { b.x, h - 0.025, b.z }, { b.w, 0.05, b.d }, WHITE, M_BLOCK)
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            prim("cube", { b.x + sx * (b.w / 2 - 0.05), (h - 0.05) / 2, b.z + sz * (b.d / 2 - 0.05) }, { 0.04, h - 0.05, 0.04 }, GREY, M_BLOCK)
        end
    end
    static({ b.x, h - 0.025, b.z }, { b.w, 0.05, b.d }, false)
    L.obstacles[#L.obstacles + 1] = { b.x - b.w / 2, b.x + b.w / 2, b.z - b.d / 2, b.z + b.d / 2 }
end

function K.counter(b)
    local h = b.h or 1.05
    block({ b.x, h / 2 - 0.02, b.z }, { b.w, h - 0.04, b.d }, WHITE, M_BLOCK, "images/panel_white.png")
    prim("cube", { b.x, h - 0.015, b.z }, { b.w + 0.06, 0.03, b.d + 0.06 }, GREY, { smooth = 0.9, metal = 0.3 })
    static({ b.x, h - 0.015, b.z }, { b.w + 0.06, 0.03, b.d + 0.06 }, false)
end

function K.stool(b)
    prim("cylinder", { b.x, 0.35, b.z }, { 0.05, 0.35, 0.05 }, GREY, M_BLOCK)
    prim("cylinder", { b.x, 0.72, b.z }, { 0.36, 0.03, 0.36 }, WHITE, M_BLOCK)
    static({ b.x, 0.72, b.z }, { 0.36, 0.06, 0.36 }, false)
end

function K.bench(b)
    local h = b.h or 0.45
    block({ b.x, h / 2, b.z }, { b.w, h, b.d }, WHITE, M_BLOCK)
    block({ b.x + (b.back or 0), h + 0.3, b.z + (b.backz or 0) }, { b.bw or b.w, 0.6, b.bd or 0.08 }, WHITE, M_BLOCK, nil, false)
end

function K.pole(b)
    prim("cylinder", { b.x, L.height / 2, b.z }, { 0.05, L.height / 2, 0.05 }, GREY, { smooth = 0.95, metal = 0.6 })
    static({ b.x, L.height / 2, b.z }, { 0.05, L.height, 0.05 }, false)
end

function K.rack(b)
    local h = b.h or 2.1
    block({ b.x, h / 2, b.z }, { b.w, h, b.d }, { 0.88, 0.89, 0.92 }, M_BLOCK, "images/rack.png")
end

function K.car(b)
    local yaw = b.yaw or 0
    local along = yaw == 90 and { 1, 0, 0 } or { 0, 0, 1 }
    local w, l = 1.8, 4.2
    local sx, sz = w, l
    if yaw == 90 then sx, sz = l, w end
    block({ b.x, 0.45, b.z }, { sx, 0.6, sz }, WHITE, M_BLOCK)
    local cab = { b.x - along[1] * 0.2, 1.0, b.z - along[3] * 0.2 }
    block(cab, { yaw == 90 and 2.2 or 1.6, 0.5, yaw == 90 and 1.6 or 2.2 }, { 0.9, 0.91, 0.94 }, M_BLOCK, nil, false)
    -- vidros escuros
    prim("cube", { cab[1], 1.02, cab[3] }, { (yaw == 90 and 2.24 or 1.5), 0.36, (yaw == 90 and 1.5 or 2.24) }, { 0.2, 0.21, 0.24 }, { smooth = 1, metal = 0.5 })
    for _, s in ipairs({ -1, 1 }) do
        for _, t in ipairs({ -1, 1 }) do
            local wx = yaw == 90 and t * 1.35 or s * 0.92
            local wz = yaw == 90 and s * 0.92 or t * 1.35
            prim("cylinder", { b.x + wx, 0.3, b.z + wz }, { 0.6, 0.12, 0.6 }, { 0.15, 0.15, 0.17 }, M_BLOCK, nil, { 0, 0, 90 })
        end
    end
end

function K.stand(b)
    -- suporte da katana / pedestal
    block({ b.x, 0.45, b.z }, { 0.5, 0.9, 0.5 }, WHITE, M_BLOCK)
end

-- porta: moldura + vao escuro numa parede
local function door(d)
    local S = L.size
    local x, z, rotY
    if d.wall == "n" then x, z, rotY = d.at, S[2] - 0.02, 0
    elseif d.wall == "s" then x, z, rotY = d.at, -S[2] + 0.02, 180
    elseif d.wall == "e" then x, z, rotY = S[1] - 0.02, d.at, 90
    else x, z, rotY = -S[1] + 0.02, d.at, -90 end
    local Bd = V.basisFromEuler(0, rotY, 0)
    local o = prim("quad", { x, 1.05, z }, { 1.1, 2.1, 1 }, { 0.08, 0.08, 0.1 }, { smooth = 0.2 }, nil, { 0, rotY, 0 })
    local fr = { 0.8, 0.81, 0.84 }
    for _, side in ipairs({ -1, 1 }) do
        local p = V.add({ x, 1.1, z }, V.add(V.scale(Bd.r, side * 0.6), V.scale(Bd.f, -0.03)))
        local f = prim("cube", p, { 0.1, 2.2, 0.08 }, fr, M_BLOCK)
        A.rotBasis(f, Bd)
    end
    local top = prim("cube", V.add({ x, 2.22, z }, V.scale(Bd.f, -0.03)), { 1.3, 0.1, 0.08 }, fr, M_BLOCK)
    A.rotBasis(top, Bd)
    return o
end

function L.build(def, world, rigRef)
    rig = rigRef
    L.unload()
    L.root = A.empty("level", world)
    L.statics, L.obstacles = {}, {}
    L.size = def.size
    L.height = def.height or 3.4
    local S, H = def.size, L.height

    -- piso, teto, paredes
    block({ 0, -0.1, 0 }, { S[1] * 2, 0.2, S[2] * 2 }, { 0.86, 0.87, 0.9 }, M_FLOOR, "images/floor_white.png", false)
    block({ 0, H + 0.1, 0 }, { S[1] * 2 + 0.4, 0.2, S[2] * 2 + 0.4 }, WHITE, M_WALL, "images/ceiling_white.png", false)
    local wt = "images/wall_white.png"
    block({ 0, H / 2, S[2] + 0.1 }, { S[1] * 2 + 0.4, H, 0.2 }, WHITE, M_WALL, wt, false)
    block({ 0, H / 2, -S[2] - 0.1 }, { S[1] * 2 + 0.4, H, 0.2 }, WHITE, M_WALL, wt, false)
    block({ S[1] + 0.1, H / 2, 0 }, { 0.2, H, S[2] * 2 + 0.4 }, WHITE, M_WALL, wt, false)
    block({ -S[1] - 0.1, H / 2, 0 }, { 0.2, H, S[2] * 2 + 0.4 }, WHITE, M_WALL, wt, false)
    -- rodape cinza e luzes no teto
    for _, z in ipairs({ S[2] - 0.01, -S[2] + 0.01 }) do prim("cube", { 0, 0.05, z }, { S[1] * 2, 0.1, 0.02 }, GREY, M_BLOCK) end
    for _, x in ipairs({ S[1] - 0.01, -S[1] + 0.01 }) do prim("cube", { x, 0.05, 0 }, { 0.02, 0.1, S[2] * 2 }, GREY, M_BLOCK) end
    local nl = math.max(1, math.floor(S[2] / 2))
    for i = -nl, nl do
        prim("cube", { 0, H - 0.01, i * (S[2] * 2 / (2 * nl + 1)) }, { math.min(S[1] * 1.4, 4), 0.02, 0.5 }, { 1, 1, 1 }, { emit = { 1.4, 1.4, 1.45 }, noShadow = true })
    end

    for _, b in ipairs(def.boxes or {}) do
        local f = K[b.k or "block"]
        f(b)
    end
    L.doors = {}
    for _, d in ipairs(def.doors or {}) do L.doors[#L.doors + 1] = door(d) end

    L.bounds = { -S[1] + 0.05, S[1] - 0.05, -S[2] + 0.05, S[2] - 0.05 }
    -- jogador colide com os mesmos obstaculos
    rig.obstacles = {}
    for _, ob in ipairs(L.obstacles) do rig.obstacles[#rig.obstacles + 1] = { box = ob } end
    rig.bounds = L.bounds
end

function L.unload()
    if L.root then A.destroy(L.root) end
    L.root = nil
    L.statics, L.obstacles = {}, {}
end

function L.raycast(o, d, maxDist)
    local best, bn = maxDist or 1e9, nil
    for _, s in ipairs(L.statics) do
        local t, n = V.rayAABB(o, d, s.mn, s.mx)
        if t and t < best and t > 0.0001 then best, bn = t, n end
    end
    if bn then return best, bn end
    return nil
end

function L.lineClear(a, b)
    local d = V.sub(b, a)
    local len = V.len(d)
    if len < 1e-4 then return true end
    return L.raycast(a, V.scale(d, 1 / len), len) == nil
end

return L
