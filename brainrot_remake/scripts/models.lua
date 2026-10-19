-- models.lua — modelos 3D dos brainrots montados com primitivas.
-- Cada receita desenha o bicho em "unidades" (altura ~1, pes em y=0, olhando para +Z);
-- o modelo final e escalado pela altura da raridade.
-- Mutacoes (ouro, diamante, doce, lava, halloween, arco-iris) recolorem as pecas.

local V = require("vec")
local A = require("api")

local M = {}

---------------------------------------------------------------------------
-- cores
---------------------------------------------------------------------------
local hexCache = {}
local function C(h)
    if type(h) == "table" then return h end
    local c = hexCache[h]
    if c then return c end
    local r = tonumber(h:sub(2, 3), 16) / 255
    local g = tonumber(h:sub(4, 5), 16) / 255
    local b = tonumber(h:sub(6, 7), 16) / 255
    c = { r, g, b }
    hexCache[h] = c
    return c
end
M.C = C

local WHITE, BLACK = "#ffffff", "#141414"
local SHARK, BELLY = "#5d82ab", "#eef2f5"
local NIKE, SOLE = "#2f8cff", "#f4f4f4"
local SKIN = "#f5c9a0"

---------------------------------------------------------------------------
-- construtor
---------------------------------------------------------------------------
local B = {}
B.__index = B

local function newBuilder(parent)
    local b = setmetatable({ parts = {}, stack = { parent }, cur = parent, glow = {} }, B)
    return b
end

function B:add(kind, x, y, z, sx, sy, sz, col, rx, ry, rz, opt)
    local o = A.prim(kind, {
        parent = self.cur, pos = { x, y, z }, scale = { sx, sy, sz },
        rot = (rx or ry or rz) and { rx or 0, ry or 0, rz or 0 } or nil,
        color = C(col),
    })
    local p = { o = o, c = C(col), kind = kind }
    if opt and opt.emit then
        p.emit = opt.emit
        A.material(o, { emit = opt.emit, smooth = 0.6 })
    elseif opt and opt.shiny then
        A.material(o, { smooth = 0.85, metal = opt.metal or 0.2 })
    end
    self.parts[#self.parts + 1] = p
    return o
end
function B:box(x, y, z, w, h, d, col, rx, ry, rz, opt) return self:add("cube", x, y, z, w, h, d, col, rx, ry, rz, opt) end
function B:ball(x, y, z, w, h, d, col, rx, ry, rz, opt) return self:add("sphere", x, y, z, w, h, d, col, rx, ry, rz, opt) end
-- cilindro/capsula: w, d = diametros; h = altura total
function B:cyl(x, y, z, w, h, d, col, rx, ry, rz, opt) return self:add("cylinder", x, y, z, w, h / 2, d, col, rx, ry, rz, opt) end
function B:cap(x, y, z, w, h, d, col, rx, ry, rz, opt) return self:add("capsule", x, y, z, w, h / 2, d, col, rx, ry, rz, opt) end

-- membro (capsula) entre dois pontos
function B:limb(a, b2, diam, col, kind)
    local d = V.sub(b2, a)
    local len = V.len(d)
    local m = V.mid(a, b2)
    local ex, ey, ez = V.eulerAlongY(d)
    if kind == "cyl" then return self:add("cylinder", m[1], m[2], m[3], diam, len / 2, diam, col, ex, ey, ez) end
    if kind == "box" then return self:add("cube", m[1], m[2], m[3], diam, len, diam, col, ex, ey, ez) end
    return self:add("capsule", m[1], m[2], m[3], diam, (len + diam) / 2, diam, col, ex, ey, ez)
end

-- grupo com transformacao propria
function B:push(x, y, z, rx, ry, rz, s)
    local n = A.empty("g", self.cur, { x, y, z }, { rx or 0, ry or 0, rz or 0 })
    if s then A.scale(n, s, s, s) end
    self.stack[#self.stack + 1] = n
    self.cur = n
    return n
end
function B:pop()
    self.stack[#self.stack] = nil
    self.cur = self.stack[#self.stack]
end

-- olhos virados para +Z
function B:eyes(x, y, z, s, gap, opt)
    opt = opt or {}
    local pup = opt.pupil or BLACK
    for _, sx in ipairs({ -1, 1 }) do
        self:ball(x + sx * gap, y, z, s, s * (opt.tall or 1), s * 0.6, opt.white or WHITE)
        self:ball(x + sx * gap + (opt.look or 0) * s * 0.15, y - s * 0.08, z + s * 0.26, s * 0.5, s * 0.55 * (opt.tall or 1), s * 0.25, pup)
    end
end

-- tenis estilo "Nike" (sola branca + cabedal colorido + risquinho branco)
function B:sneaker(x, y, z, s, upper, ry)
    self:push(x, y, z, 0, ry or 0, 0, s)
    self:box(0, 0.03, 0.02, 0.16, 0.06, 0.30, SOLE)
    self:box(0, 0.10, -0.01, 0.15, 0.10, 0.24, upper or NIKE)
    self:box(0, 0.08, 0.09, 0.14, 0.06, 0.10, upper or NIKE)
    self:box(0.078, 0.10, 0.0, 0.01, 0.03, 0.14, WHITE, 18, 0, 0)
    self:box(-0.078, 0.10, 0.0, 0.01, 0.03, 0.14, WHITE, 18, 0, 0)
    self:box(0, 0.165, -0.09, 0.13, 0.05, 0.06, WHITE)
    self:pop()
end

-- sandalia
function B:sandal(x, z, s, col)
    self:box(x, 0.015 * s, z + 0.02 * s, 0.14 * s, 0.03 * s, 0.24 * s, col or "#8a5a2b")
    self:box(x, 0.05 * s, z + 0.05 * s, 0.15 * s, 0.02 * s, 0.04 * s, col or "#6b3f1a")
end

-- perna humana simples (de y0 ate o chao) com sapato
function B:leg(x, z, top, diam, col, shoe)
    self:limb({ x, top, z }, { x, 0.07, z }, diam, col, "cyl")
    if shoe then self:box(x, 0.035, z + diam * 0.3, diam * 1.3, 0.07, diam * 2.0, shoe) end
end

-- raios de espinhos (cacto)
function B:spines(x, y, z, r, h, n, col)
    for i = 1, n do
        local a = (i / n) * math.pi * 2
        local yy = y + ((i % 3) - 1) * h * 0.3
        self:box(x + math.sin(a) * r, yy, z + math.cos(a) * r, 0.015, 0.015, 0.06, col or "#f3f0c0", 0, a * V.DEG, 0)
    end
end

-- cabeca de gato (orelhas + focinho + bigode)
function B:catHead(x, y, z, s, col, inner)
    self:ball(x, y, z, 0.42 * s, 0.36 * s, 0.38 * s, col)
    for _, sx in ipairs({ -1, 1 }) do
        self:box(x + sx * 0.12 * s, y + 0.18 * s, z, 0.1 * s, 0.12 * s, 0.05 * s, col, 0, 0, sx * -20)
        self:box(x + sx * 0.12 * s, y + 0.17 * s, z + 0.02 * s, 0.05 * s, 0.07 * s, 0.03 * s, inner or "#ffb3c6", 0, 0, sx * -20)
        self:box(x + sx * 0.14 * s, y - 0.03 * s, z + 0.19 * s, 0.14 * s, 0.006, 0.006, BLACK, 0, 0, sx * 8)
    end
    self:eyes(x, y + 0.04 * s, z + 0.15 * s, 0.1 * s, 0.08 * s, { white = "#d8f56a" })
    self:ball(x, y - 0.03 * s, z + 0.19 * s, 0.05 * s, 0.035 * s, 0.03 * s, "#ff8fa8")
end

-- tubarao (Tralalero): corpo horizontal + 3 pernas de tenis
function B:shark(x, z, s, shoe, bow)
    self:push(x, 0, z, 0, 0, 0, s)
    local y = 0.62
    self:cap(0, y, 0, 0.42, 1.05, 0.42, SHARK, 90, 0, 0)
    self:ball(0, y - 0.06, 0.05, 0.36, 0.26, 0.9, BELLY)
    self:ball(0, y - 0.02, 0.48, 0.34, 0.32, 0.30, SHARK)
    self:box(0, y - 0.09, 0.58, 0.20, 0.05, 0.06, WHITE)                 -- dentes
    self:box(0, y - 0.13, 0.55, 0.22, 0.02, 0.08, "#8a2030")
    self:eyes(0, y + 0.06, 0.55, 0.075, 0.12)
    self:box(0, y + 0.30, -0.02, 0.05, 0.26, 0.24, SHARK, -25, 0, 0)     -- barbatana
    self:box(0, y + 0.08, -0.60, 0.05, 0.40, 0.18, SHARK, 30, 0, 0)      -- cauda
    self:box(0, y - 0.12, -0.58, 0.05, 0.26, 0.14, SHARK, -40, 0, 0)
    for _, sx in ipairs({ -1, 1 }) do
        self:box(sx * 0.24, y - 0.10, 0.12, 0.22, 0.04, 0.12, SHARK, 0, sx * 20, sx * -25)
    end
    -- 3 pernas
    for _, p in ipairs({ { -0.11, 0.2 }, { 0.11, 0.2 }, { 0, -0.25 } }) do
        self:limb({ p[1], y - 0.12, p[2] }, { p[1], 0.14, p[2] }, 0.07, SKIN, "cyl")
        self:sneaker(p[1], 0, p[2], 0.85, shoe)
    end
    if bow then
        self:ball(-0.07, y + 0.24, 0.33, 0.1, 0.08, 0.05, bow)
        self:ball(0.07, y + 0.24, 0.33, 0.1, 0.08, 0.05, bow)
    end
    self:pop()
end

-- crocodilo cabeca
function B:crocHead(x, y, z, s, col)
    self:box(x, y, z, 0.30 * s, 0.18 * s, 0.30 * s, col)
    self:box(x, y - 0.03 * s, z + 0.28 * s, 0.24 * s, 0.10 * s, 0.34 * s, col)
    self:box(x, y - 0.075 * s, z + 0.26 * s, 0.22 * s, 0.03 * s, 0.32 * s, "#c7e39a")
    for i = 0, 3 do
        self:box(x + 0.1 * s, y - 0.06 * s, z + (0.14 + i * 0.07) * s, 0.02 * s, 0.03 * s, 0.02 * s, WHITE)
        self:box(x - 0.1 * s, y - 0.06 * s, z + (0.14 + i * 0.07) * s, 0.02 * s, 0.03 * s, 0.02 * s, WHITE)
    end
    for _, sx in ipairs({ -1, 1 }) do
        self:ball(x + sx * 0.08 * s, y + 0.11 * s, z + 0.06 * s, 0.09 * s, 0.09 * s, 0.09 * s, "#f4f08a")
        self:ball(x + sx * 0.08 * s, y + 0.12 * s, z + 0.1 * s, 0.03 * s, 0.06 * s, 0.03 * s, BLACK)
    end
end

-- macaco (cara)
function B:chimpHead(x, y, z, s)
    self:ball(x, y, z, 0.34 * s, 0.32 * s, 0.32 * s, "#5a3a22")
    self:ball(x, y - 0.03 * s, z + 0.11 * s, 0.24 * s, 0.22 * s, 0.14 * s, "#d9b48c")
    for _, sx in ipairs({ -1, 1 }) do
        self:ball(x + sx * 0.18 * s, y + 0.02 * s, z, 0.1 * s, 0.12 * s, 0.05 * s, "#d9b48c")
    end
    self:eyes(x, y + 0.04 * s, z + 0.16 * s, 0.07 * s, 0.05 * s)
    self:box(x, y - 0.09 * s, z + 0.18 * s, 0.1 * s, 0.015 * s, 0.02 * s, "#5a2a1a")
end

-- elefante (cabeca + tromba + orelhas)
function B:elephantHead(x, y, z, s, col)
    self:ball(x, y, z, 0.36 * s, 0.34 * s, 0.34 * s, col)
    for _, sx in ipairs({ -1, 1 }) do
        self:ball(x + sx * 0.22 * s, y, z - 0.02 * s, 0.26 * s, 0.30 * s, 0.05 * s, col, 0, sx * 25, 0)
        self:ball(x + sx * 0.22 * s, y, z - 0.005 * s, 0.18 * s, 0.22 * s, 0.03 * s, "#e7a9b5", 0, sx * 25, 0)
    end
    self:limb({ x, y - 0.04 * s, z + 0.15 * s }, { x, y - 0.22 * s, z + 0.22 * s }, 0.10 * s, col)
    self:limb({ x, y - 0.22 * s, z + 0.22 * s }, { x, y - 0.28 * s, z + 0.32 * s }, 0.08 * s, col)
    self:eyes(x, y + 0.06 * s, z + 0.15 * s, 0.07 * s, 0.09 * s)
end

-- melancia (corpo)
function B:watermelon(x, y, z, w, h, d)
    self:ball(x, y, z, w, h, d, "#2f8f3a")
    for i = 0, 5 do
        self:ball(x, y, z, w * 1.005, h * 1.005, d * 0.12, "#1d5e25", 0, i * 30, 0)
    end
end

---------------------------------------------------------------------------
-- RECEITAS
---------------------------------------------------------------------------
local R = {}

R.noobini = function(b)
    -- fatia de pizza com cabeca de noob
    b:leg(-0.1, 0, 0.32, 0.12, "#3fae3f", "#2e7d2e")
    b:leg(0.1, 0, 0.32, 0.12, "#3fae3f", "#2e7d2e")
    b:box(0, 0.5, 0, 0.42, 0.40, 0.14, "#f6c33b", 0, 0, 0)
    b:box(0, 0.73, 0, 0.48, 0.08, 0.17, "#c27a2c")
    for _, p in ipairs({ { -0.1, 0.55 }, { 0.09, 0.45 }, { 0.0, 0.36 }, { 0.13, 0.62 } }) do
        b:cyl(p[1], p[2], 0.075, 0.08, 0.02, 0.08, "#c0392b", 90, 0, 0)
    end
    for _, sx in ipairs({ -1, 1 }) do
        b:limb({ sx * 0.24, 0.62, 0 }, { sx * 0.33, 0.38, 0.06 }, 0.1, "#f2d23c", "box")
    end
    b:box(0, 0.92, 0, 0.30, 0.28, 0.28, "#f2d23c")
    b:box(-0.06, 0.95, 0.142, 0.04, 0.06, 0.01, BLACK)
    b:box(0.06, 0.95, 0.142, 0.04, 0.06, 0.01, BLACK)
    b:box(0, 0.86, 0.142, 0.14, 0.025, 0.01, BLACK)
end

R.lirili = function(b)
    b:sandal(-0.1, 0, 1)
    b:sandal(0.1, 0, 1)
    b:limb({ -0.1, 0.3, 0 }, { -0.1, 0.06, 0 }, 0.12, "#8f9196", "cyl")
    b:limb({ 0.1, 0.3, 0 }, { 0.1, 0.06, 0 }, 0.12, "#8f9196", "cyl")
    b:cap(0, 0.5, 0, 0.34, 0.6, 0.30, "#4f9a3a")
    b:cap(0, 0.5, 0.02, 0.24, 0.5, 0.28, "#5fb447")
    b:spines(0, 0.5, 0, 0.17, 0.4, 14)
    b:limb({ 0.17, 0.55, 0 }, { 0.3, 0.68, 0 }, 0.1, "#4f9a3a")
    b:limb({ 0.3, 0.68, 0 }, { 0.3, 0.8, 0 }, 0.1, "#4f9a3a")
    b:elephantHead(0, 0.86, 0.02, 1, "#9a9ca3")
end

R.timcheese = function(b)
    b:leg(-0.1, 0, 0.2, 0.07, "#f2c34a", "#d9a326")
    b:leg(0.1, 0, 0.2, 0.07, "#f2c34a", "#d9a326")
    b:box(0, 0.42, 0, 0.6, 0.48, 0.42, "#ffd24a", 0, 0, 0)
    b:box(0, 0.68, -0.05, 0.62, 0.06, 0.32, "#ffde70", 12, 0, 0)
    for _, p in ipairs({ { -0.18, 0.3 }, { 0.2, 0.52 }, { 0.05, 0.25 }, { -0.12, 0.55 } }) do
        b:cyl(p[1], p[2], 0.21, 0.09, 0.02, 0.09, "#d9a326", 90, 0, 0)
    end
    b:eyes(0, 0.48, 0.21, 0.1, 0.09)
    b:box(0, 0.38, 0.215, 0.12, 0.025, 0.01, "#7a4a12")
    b:ball(-0.2, 0.72, 0, 0.14, 0.14, 0.04, "#ffb3c6")
    b:ball(0.2, 0.72, 0, 0.14, 0.14, 0.04, "#ffb3c6")
    b:limb({ 0, 0.3, -0.21 }, { 0, 0.15, -0.45 }, 0.03, "#ffb3c6")
end

R.fluriflura = function(b)
    b:leg(-0.07, 0, 0.32, 0.03, "#f39c12", "#e67e22")
    b:leg(0.07, 0, 0.32, 0.03, "#f39c12", "#e67e22")
    b:ball(0, 0.5, 0, 0.44, 0.42, 0.42, "#ffb7d5")
    b:ball(0, 0.47, 0.08, 0.30, 0.30, 0.3, "#ffe3ef")
    b:ball(0, 0.78, 0.04, 0.3, 0.28, 0.28, "#ffb7d5")
    b:eyes(0, 0.8, 0.17, 0.08, 0.06)
    b:box(0, 0.74, 0.2, 0.06, 0.04, 0.1, "#f39c12")
    for i = 0, 4 do
        local a = i / 5 * math.pi * 2
        b:ball(math.sin(a) * 0.07, 0.96, math.cos(a) * 0.07, 0.09, 0.04, 0.09, "#ff5aa5")
    end
    b:ball(0, 0.97, 0, 0.06, 0.06, 0.06, "#ffe14a")
    b:ball(-0.24, 0.52, -0.02, 0.1, 0.24, 0.2, "#ff9cc6", 0, 0, 20)
    b:ball(0.24, 0.52, -0.02, 0.1, 0.24, 0.2, "#ff9cc6", 0, 0, -20)
end

R.talpa = function(b)
    b:ball(0, 0.38, 0, 0.5, 0.56, 0.5, "#6d717a", 0, 0, 0, { shiny = true, metal = 0.7 })
    b:ball(0, 0.32, 0.1, 0.32, 0.38, 0.32, "#8b9099", 0, 0, 0, { shiny = true, metal = 0.6 })
    -- broca no nariz
    for i = 0, 3 do
        b:cyl(0, 0.5, 0.26 + i * 0.06, 0.16 - i * 0.035, 0.06, 0.16 - i * 0.035, "#c9ccd2", 90, 0, 0, { shiny = true, metal = 0.9 })
    end
    b:box(0, 0.62, 0.22, 0.36, 0.06, 0.04, "#3a2a1a")
    b:ball(-0.09, 0.62, 0.24, 0.1, 0.1, 0.04, "#7fd4ff", 0, 0, 0, { shiny = true })
    b:ball(0.09, 0.62, 0.24, 0.1, 0.1, 0.04, "#7fd4ff", 0, 0, 0, { shiny = true })
    for _, sx in ipairs({ -1, 1 }) do
        b:box(sx * 0.24, 0.26, 0.16, 0.12, 0.05, 0.14, "#f1d3b0")
        b:box(sx * 0.14, 0.04, 0.05, 0.14, 0.08, 0.2, "#4a4d54")
    end
end

R.svinina = function(b)
    b:cap(0, 0.48, 0, 0.42, 0.9, 0.42, "#ffa3b8", 90, 0, 0)
    b:cyl(0, 0.5, 0.47, 0.18, 0.06, 0.16, "#ff8aa5", 90, 0, 0)
    b:box(-0.03, 0.5, 0.505, 0.03, 0.04, 0.01, "#a3485e")
    b:box(0.03, 0.5, 0.505, 0.03, 0.04, 0.01, "#a3485e")
    b:eyes(0, 0.62, 0.36, 0.07, 0.09)
    b:box(-0.12, 0.72, 0.28, 0.08, 0.1, 0.03, "#ff8aa5", -20, 0, 20)
    b:box(0.12, 0.72, 0.28, 0.08, 0.1, 0.03, "#ff8aa5", -20, 0, -20)
    b:box(0, 0.5, 0.05, 1.1, 0.04, 0.24, "#7d8691")                 -- asas
    b:box(0, 0.62, -0.42, 0.04, 0.24, 0.16, "#7d8691")
    b:box(0, 0.5, -0.42, 0.42, 0.03, 0.12, "#7d8691")
    b:cap(0, 0.25, 0.08, 0.1, 0.3, 0.1, "#3b3f45", 90, 0, 0)        -- bomba
    b:leg(-0.1, 0.12, 0.3, 0.08, "#ffa3b8", "#c9707f")
    b:leg(0.1, 0.12, 0.3, 0.08, "#ffa3b8", "#c9707f")
end

R.pipikiwi = function(b)
    b:leg(-0.07, 0, 0.3, 0.035, "#c48c4c", "#a06a2c")
    b:leg(0.07, 0, 0.3, 0.035, "#c48c4c", "#a06a2c")
    b:ball(0, 0.52, 0, 0.5, 0.48, 0.46, "#7a5532")
    b:ball(0, 0.52, 0.18, 0.40, 0.38, 0.12, "#8fc73e")
    b:ball(0, 0.52, 0.23, 0.18, 0.18, 0.04, "#f2f4d0")
    for i = 0, 7 do
        local a = i / 8 * math.pi * 2
        b:ball(math.sin(a) * 0.12, 0.52 + math.cos(a) * 0.12, 0.235, 0.025, 0.04, 0.01, BLACK)
    end
    b:eyes(0, 0.72, 0.17, 0.07, 0.08)
    b:limb({ 0, 0.68, 0.2 }, { 0, 0.6, 0.45 }, 0.035, "#d9b48c")
end

R.trippi = function(b)
    -- camarao com cabeca de gato
    for i = 0, 5 do
        local a = i / 5
        b:ball(0, 0.25 + a * 0.35, -0.25 + math.sin(a * 2.4) * 0.3, 0.32 - a * 0.1, 0.22, 0.22, i % 2 == 0 and "#ff8a4c" or "#ff7a3a")
    end
    b:box(0, 0.2, -0.38, 0.3, 0.04, 0.16, "#ff8a4c", -30, 0, 0)
    for i = 0, 2 do
        b:limb({ -0.1, 0.3, -0.1 + i * 0.1 }, { -0.16, 0.02, -0.08 + i * 0.12 }, 0.025, "#ff6a2a")
        b:limb({ 0.1, 0.3, -0.1 + i * 0.1 }, { 0.16, 0.02, -0.08 + i * 0.12 }, 0.025, "#ff6a2a")
    end
    b:catHead(0, 0.78, 0.12, 1.0, "#ffa65c")
    b:limb({ 0.06, 0.85, 0.28 }, { 0.12, 1.05, 0.42 }, 0.012, "#ff6a2a")
    b:limb({ -0.06, 0.85, 0.28 }, { -0.12, 1.05, 0.42 }, 0.012, "#ff6a2a")
end

R.footera = function(b)
    b:leg(-0.1, 0, 0.25, 0.08, "#222222", "#111111")
    b:leg(0.1, 0, 0.25, 0.08, "#222222", "#111111")
    b:ball(0, 0.52, 0, 0.56, 0.56, 0.56, WHITE)
    for _, p in ipairs({ { 0, 0.55, 0.27 }, { 0.22, 0.65, 0.12 }, { -0.22, 0.62, 0.14 }, { 0.12, 0.33, 0.22 }, { -0.14, 0.34, 0.2 }, { 0, 0.8, 0 } }) do
        local d = V.norm(V.sub(p, { 0, 0.52, 0 }))
        local ex, ey, ez = V.eulerAlongY(d)
        b:cyl(p[1], p[2], p[3], 0.13, 0.02, 0.13, BLACK, ex, ey, ez)
    end
    b:box(0, 0.62, 0.27, 0.34, 0.07, 0.04, "#101010", 0, 0, 0, { shiny = true })
    b:box(0, 0.4, 0.26, 0.2, 0.02, 0.02, "#5a1a1a")
    for i = 0, 6 do
        local a = (i / 6 - 0.5) * 2.2
        b:ball(math.sin(a) * 0.2, 0.3 - math.cos(a) * 0.04, math.cos(a) * 0.2, 0.04, 0.04, 0.04, "#ffd700", 0, 0, 0, { shiny = true, metal = 0.9 })
    end
    b:cyl(0, 0.84, 0, 0.36, 0.04, 0.36, "#1a1a1a")
    b:cyl(0, 0.92, 0, 0.24, 0.14, 0.24, "#1a1a1a")
    b:limb({ 0.27, 0.5, 0 }, { 0.36, 0.32, 0.1 }, 0.07, SKIN)
    b:limb({ -0.27, 0.5, 0 }, { -0.36, 0.32, 0.1 }, 0.07, SKIN)
end

R.bobritto = function(b)
    b:leg(-0.1, 0, 0.22, 0.09, "#6b4423", "#3d2510")
    b:leg(0.1, 0, 0.22, 0.09, "#6b4423", "#3d2510")
    b:ball(0, 0.45, 0, 0.42, 0.48, 0.38, "#8b5a2b")
    b:ball(0, 0.42, 0.1, 0.28, 0.32, 0.22, "#c99a6a")
    b:box(0, 0.12, -0.3, 0.26, 0.04, 0.34, "#5a3a1f", -15, 0, 0)
    b:ball(0, 0.78, 0.04, 0.32, 0.28, 0.3, "#8b5a2b")
    b:eyes(0, 0.82, 0.17, 0.07, 0.07)
    b:box(0, 0.7, 0.19, 0.09, 0.07, 0.02, WHITE)
    b:box(0, 0.75, 0.19, 0.24, 0.06, 0.04, "#d62828")              -- bandana
    b:cyl(0, 0.94, 0.02, 0.46, 0.03, 0.46, "#b07a3e")               -- chapeu
    b:cyl(0, 1.0, 0.02, 0.24, 0.12, 0.24, "#a06a32")
    b:cap(0.26, 0.45, 0.1, 0.1, 0.24, 0.1, "#f0e0b0", 0, 0, 30)     -- burrito
    b:limb({ 0.2, 0.55, 0 }, { 0.27, 0.42, 0.1 }, 0.07, "#8b5a2b")
end

R.cactohippo = function(b)
    b:sandal(-0.1, 0, 1, "#3a6ea5")
    b:sandal(0.1, 0, 1, "#3a6ea5")
    b:limb({ -0.1, 0.3, 0 }, { -0.1, 0.06, 0 }, 0.12, "#4f9a3a", "cyl")
    b:limb({ 0.1, 0.3, 0 }, { 0.1, 0.06, 0 }, 0.12, "#4f9a3a", "cyl")
    b:cap(0, 0.5, 0, 0.38, 0.55, 0.32, "#4f9a3a")
    b:spines(0, 0.5, 0, 0.19, 0.4, 14)
    b:ball(0, 0.86, 0.0, 0.4, 0.3, 0.34, "#9b86a6")
    b:ball(0, 0.8, 0.16, 0.34, 0.2, 0.22, "#b4a2be")
    b:box(-0.06, 0.82, 0.27, 0.03, 0.03, 0.01, BLACK)
    b:box(0.06, 0.82, 0.27, 0.03, 0.03, 0.01, BLACK)
    b:eyes(0, 0.98, 0.1, 0.07, 0.1)
    b:ball(-0.13, 1.02, -0.04, 0.07, 0.07, 0.04, "#9b86a6")
    b:ball(0.13, 1.02, -0.04, 0.07, 0.07, 0.04, "#9b86a6")
end

R.trictrac = function(b)
    b:leg(-0.12, 0, 0.25, 0.11, "#2e8b57", "#1f6b42")
    b:leg(0.12, 0, 0.25, 0.11, "#2e8b57", "#1f6b42")
    b:ball(0, 0.48, 0, 0.46, 0.5, 0.42, "#2e8b57")
    b:ball(0, 0.45, 0.1, 0.3, 0.34, 0.26, "#a8d08d")
    b:crocHead(0, 0.82, 0.05, 1.0, "#2e8b57")
    for i = 0, 2 do
        local x = (i - 1) * 0.14
        b:cyl(x, 0.62, -0.22, 0.08, 0.36, 0.08, "#e63946", 0, 0, (i - 1) * 12)
        b:limb({ x + (i - 1) * 0.04, 0.8, -0.22 }, { x + (i - 1) * 0.06, 0.9, -0.24 }, 0.012, "#555555")
        b:ball(x + (i - 1) * 0.06, 0.92, -0.24, 0.05, 0.05, 0.05, "#ffcc00", 0, 0, 0, { emit = { 2, 1.2, 0.2 } })
    end
end

R.cappuccino = function(b)
    b:leg(-0.08, 0, 0.3, 0.07, BLACK, "#000000")
    b:leg(0.08, 0, 0.3, 0.07, BLACK, "#000000")
    b:cyl(0, 0.52, 0, 0.42, 0.46, 0.42, WHITE, 0, 0, 0, { shiny = true })
    b:cyl(0, 0.755, 0, 0.38, 0.02, 0.38, "#8b5a2b")
    b:ball(0, 0.77, 0, 0.3, 0.04, 0.3, "#e8d2b0")
    b:cyl(0, 0.3, 0, 0.44, 0.03, 0.44, "#e8e8e8")
    b:box(0, 0.64, 0, 0.44, 0.07, 0.44, BLACK)                      -- faixa ninja
    b:box(0.04, 0.6, -0.26, 0.04, 0.16, 0.04, BLACK, 20, 0, 10)
    b:box(-0.04, 0.6, -0.26, 0.04, 0.16, 0.04, BLACK, 20, 0, -10)
    b:eyes(0, 0.56, 0.2, 0.07, 0.08, { tall = 0.6 })
    b:box(0, 0.62, 0.215, 0.24, 0.02, 0.01, "#d62828", 0, 0, 0)
    b:limb({ 0.22, 0.52, 0 }, { 0.34, 0.42, 0.12 }, 0.06, BLACK)
    b:limb({ -0.22, 0.52, 0 }, { -0.34, 0.42, 0.12 }, 0.06, BLACK)
    b:box(0.36, 0.55, 0.16, 0.02, 0.36, 0.05, "#dfe6ee", 30, 0, -20, { shiny = true, metal = 0.9 })
    b:box(-0.36, 0.55, 0.16, 0.02, 0.36, 0.05, "#dfe6ee", 30, 0, 20, { shiny = true, metal = 0.9 })
    b:box(0, 0.38, -0.22, 0.04, 0.6, 0.04, "#5a3a1f", 0, 0, 40)
end

R.patapim = function(b)
    for _, sx in ipairs({ -1, 1 }) do
        b:box(sx * 0.13, 0.05, 0.08, 0.2, 0.1, 0.38, "#d9a77a")
        b:limb({ sx * 0.11, 0.38, 0 }, { sx * 0.13, 0.08, 0.02 }, 0.1, "#7a5232", "cyl")
    end
    b:cyl(0, 0.52, 0, 0.32, 0.36, 0.3, "#7a5232")
    b:ball(0, 0.78, 0.02, 0.38, 0.36, 0.34, "#d9a77a")
    b:ball(0, 0.74, 0.18, 0.12, 0.16, 0.12, "#c48a5c")
    b:eyes(0, 0.86, 0.15, 0.07, 0.08)
    for i = 0, 6 do
        local a = i / 7 * math.pi * 2
        b:ball(math.sin(a) * 0.14, 1.0, math.cos(a) * 0.12 - 0.02, 0.18, 0.12, 0.16, "#3f8f2f")
    end
    b:limb({ 0.16, 0.62, 0 }, { 0.38, 0.38, 0.05 }, 0.06, "#7a5232")
    b:limb({ -0.16, 0.62, 0 }, { -0.38, 0.38, 0.05 }, 0.06, "#7a5232")
end

R.trulimero = function(b)
    b:leg(-0.08, 0, 0.32, 0.07, SKIN, "#3a6ea5")
    b:leg(0.08, 0, 0.32, 0.07, SKIN, "#3a6ea5")
    b:cap(0, 0.5, -0.05, 0.36, 0.8, 0.36, "#6a8fb5", 90, 0, 0)
    b:ball(0, 0.47, 0.0, 0.3, 0.24, 0.6, "#d6e3ee")
    b:box(0, 0.52, -0.5, 0.04, 0.32, 0.16, "#6a8fb5", 30, 0, 0)
    b:box(0, 0.72, -0.05, 0.04, 0.16, 0.2, "#6a8fb5", -20, 0, 0)
    b:catHead(0, 0.66, 0.36, 0.9, "#c9c9c9")
end

R.bambini = function(b)
    b:leg(-0.08, 0, 0.28, 0.08, SKIN, "#ffffff")
    b:leg(0.08, 0, 0.28, 0.08, SKIN, "#ffffff")
    b:box(0, 0.3, 0, 0.3, 0.12, 0.2, WHITE)                          -- fralda
    b:box(0, 0.6, 0, 0.5, 0.52, 0.12, "#e8b46a")
    b:box(0, 0.6, 0.0, 0.42, 0.44, 0.13, "#f6d79a")
    b:box(0, 0.88, 0, 0.52, 0.08, 0.13, "#c4863c")
    b:ball(-0.15, 0.88, 0, 0.18, 0.14, 0.13, "#c4863c")
    b:ball(0.15, 0.88, 0, 0.18, 0.14, 0.13, "#c4863c")
    b:eyes(0, 0.66, 0.07, 0.08, 0.08)
    b:ball(0, 0.55, 0.075, 0.06, 0.04, 0.02, "#ff9ab0")
    b:cyl(0, 0.48, 0.08, 0.05, 0.02, 0.05, "#ff7aa0", 90, 0, 0)       -- chupeta
end

R.bananita = function(b)
    b:cap(0, 0.48, 0, 0.42, 0.95, 0.42, "#ffe135", 70, 0, 0)
    for _, sx in ipairs({ -1, 1 }) do
        b:box(sx * 0.2, 0.62, 0.18, 0.04, 0.38, 0.16, "#ffe135", -20, 0, sx * -35)
    end
    b:cap(0, 0.6, 0.12, 0.3, 0.7, 0.3, "#8fb3c9", 70, 0, 0)
    b:ball(0, 0.68, 0.38, 0.14, 0.1, 0.24, "#8fb3c9")
    b:eyes(0, 0.74, 0.3, 0.06, 0.08)
    b:box(0, 0.86, 0.06, 0.03, 0.14, 0.12, "#8fb3c9", -30, 0, 0)
    b:leg(-0.1, -0.02, 0.2, 0.07, SKIN, "#2f8cff")
    b:leg(0.1, -0.02, 0.2, 0.07, SKIN, "#2f8cff")
end

R.perochello = function(b)
    b:leg(-0.08, 0, 0.25, 0.06, SKIN, "#e6c200")
    b:leg(0.08, 0, 0.25, 0.06, SKIN, "#e6c200")
    b:cyl(0, 0.45, 0, 0.34, 0.42, 0.34, "#f6e27a", 0, 0, 0, { shiny = true })
    b:cyl(0, 0.7, 0, 0.14, 0.12, 0.14, "#f6e27a", 0, 0, 0, { shiny = true })
    b:box(0, 0.45, 0.17, 0.2, 0.14, 0.01, "#2c7a3b")
    b:ball(0, 0.9, 0, 0.36, 0.3, 0.3, "#ffe600")
    b:ball(0, 0.9, 0.16, 0.08, 0.06, 0.04, "#ffe600")
    b:eyes(0, 0.94, 0.13, 0.07, 0.08)
    b:ball(0.06, 1.07, 0, 0.14, 0.04, 0.07, "#4caf50", 0, 0, 20)
end

R.bicus = function(b)
    b:leg(-0.06, 0, 0.25, 0.03, "#f39c12", "#e67e22")
    b:leg(0.06, 0, 0.25, 0.03, "#f39c12", "#e67e22")
    b:ball(0, 0.42, 0, 0.36, 0.38, 0.36, "#f28c28")
    b:ball(0, 0.4, 0.1, 0.24, 0.26, 0.2, "#ffd8a8")
    b:ball(0, 0.68, 0.04, 0.28, 0.26, 0.26, "#f28c28")
    b:eyes(0, 0.7, 0.15, 0.06, 0.06)
    b:box(0, 0.64, 0.2, 0.06, 0.05, 0.08, "#ffcc00")
    b:ball(0, 0.78, 0.02, 0.3, 0.16, 0.3, "#d4a017", 0, 0, 0, { shiny = true, metal = 0.8 })
    b:box(0, 0.9, 0.0, 0.04, 0.12, 0.3, "#c0392b")                    -- crista
    b:box(0.24, 0.45, 0.12, 0.02, 0.36, 0.04, "#cfd6de", 20, 0, -10, { shiny = true, metal = 0.9 })
    b:cyl(-0.22, 0.42, 0.08, 0.26, 0.03, 0.26, "#c0392b", 0, 0, 90)
    b:cyl(-0.235, 0.42, 0.08, 0.1, 0.01, 0.1, "#d4a017", 0, 0, 90)
end

R.avocadini = function(b)
    b:leg(-0.08, 0, 0.25, 0.04, "#f39c12", "#e67e22")
    b:leg(0.08, 0, 0.25, 0.04, "#f39c12", "#e67e22")
    b:ball(0, 0.55, 0, 0.5, 0.62, 0.42, "#2e6b2a")
    b:ball(0, 0.55, 0.06, 0.42, 0.54, 0.34, "#c8e07a")
    b:ball(0, 0.45, 0.2, 0.2, 0.22, 0.06, "#8b5a2b")
    b:eyes(0, 0.7, 0.18, 0.14, 0.1, { white = "#ffffcc", pupil = "#2a1a0a" })
    b:box(0, 0.6, 0.23, 0.05, 0.06, 0.06, "#e6a817", 45, 0, 0)
    b:box(-0.14, 0.88, 0, 0.08, 0.14, 0.05, "#2e6b2a", 0, 0, 20)
    b:box(0.14, 0.88, 0, 0.08, 0.14, 0.05, "#2e6b2a", 0, 0, -20)
end

R.salamino = function(b)
    b:box(-0.08, 0.03, 0.06, 0.12, 0.06, 0.18, "#f39c12")
    b:box(0.08, 0.03, 0.06, 0.12, 0.06, 0.18, "#f39c12")
    b:cap(0, 0.48, 0, 0.44, 0.84, 0.4, "#1d1d24")
    b:ball(0, 0.44, 0.1, 0.32, 0.56, 0.26, "#f2f2f2")
    for _, p in ipairs({ { 0, 0.5 }, { -0.07, 0.36 }, { 0.07, 0.3 }, { 0.06, 0.6 } }) do
        b:cyl(p[1], p[2], 0.22, 0.11, 0.02, 0.11, "#b5323b", 90, 0, 0)
        b:ball(p[1] + 0.02, p[2] + 0.02, 0.232, 0.025, 0.025, 0.01, "#f5e1e1")
    end
    b:eyes(0, 0.76, 0.16, 0.07, 0.07)
    b:box(0, 0.7, 0.22, 0.08, 0.05, 0.1, "#f39c12")
    b:box(-0.23, 0.48, 0, 0.05, 0.36, 0.14, "#1d1d24", 0, 0, 12)
    b:box(0.23, 0.48, 0, 0.05, 0.36, 0.14, "#1d1d24", 0, 0, -12)
end

R.burbaloni = function(b)
    b:ball(0, 0.36, 0, 0.66, 0.6, 0.62, "#6b4423")
    b:ball(0, 0.62, 0, 0.6, 0.12, 0.56, "#f5f0e1")
    b:ball(0, 0.78, 0.02, 0.4, 0.34, 0.42, "#a0703f")
    b:ball(0, 0.74, 0.2, 0.22, 0.18, 0.14, "#8a5c30")
    b:eyes(0, 0.84, 0.18, 0.06, 0.1)
    b:ball(-0.15, 0.95, -0.02, 0.07, 0.06, 0.05, "#8a5c30")
    b:ball(0.15, 0.95, -0.02, 0.07, 0.06, 0.05, "#8a5c30")
    b:box(-0.2, 0.42, 0.28, 0.06, 0.06, 0.02, "#3a2410")
    b:box(0.18, 0.3, 0.3, 0.06, 0.06, 0.02, "#3a2410")
end

R.chimpbanana = function(b)
    b:cap(0, 0.5, 0, 0.5, 1.0, 0.46, "#ffd93b")
    for i = 0, 3 do
        local a = i / 4 * math.pi * 2 + 0.4
        b:box(math.sin(a) * 0.22, 0.32, math.cos(a) * 0.22, 0.2, 0.42, 0.04, "#ffe56a", 15, a * V.DEG, 0)
    end
    b:chimpHead(0, 0.78, 0.12, 1.1)
    b:limb({ 0.2, 0.62, 0.12 }, { 0.36, 0.78, 0.18 }, 0.07, "#5a3a22")
    b:limb({ -0.2, 0.62, 0.12 }, { -0.36, 0.78, 0.18 }, 0.07, "#5a3a22")
    b:box(-0.08, 0.04, 0.06, 0.12, 0.08, 0.16, "#5a3a22")
    b:box(0.08, 0.04, 0.06, 0.12, 0.08, 0.16, "#5a3a22")
end

R.ballerina = function(b)
    b:leg(-0.05, 0, 0.42, 0.05, SKIN, "#ff8fb8")
    b:leg(0.05, 0, 0.42, 0.05, SKIN, "#ff8fb8")
    b:cyl(0, 0.44, 0, 0.62, 0.06, 0.62, "#ffb3d1")
    b:cyl(0, 0.47, 0, 0.5, 0.05, 0.5, "#ffc8de")
    b:cyl(0, 0.58, 0, 0.2, 0.22, 0.16, "#ff8fb8")
    b:limb({ 0.1, 0.66, 0 }, { 0.22, 0.88, 0.02 }, 0.045, SKIN)
    b:limb({ -0.1, 0.66, 0 }, { -0.22, 0.88, 0.02 }, 0.045, SKIN)
    b:limb({ 0.22, 0.88, 0.02 }, { 0.06, 1.02, 0.02 }, 0.04, SKIN)
    b:limb({ -0.22, 0.88, 0.02 }, { -0.06, 1.02, 0.02 }, 0.04, SKIN)
    b:cyl(0, 0.8, 0, 0.3, 0.24, 0.3, WHITE, 0, 0, 0, { shiny = true })
    b:cyl(0, 0.92, 0, 0.27, 0.02, 0.27, "#8b5a2b")
    b:ball(0, 0.93, 0, 0.22, 0.04, 0.22, "#ead7b6")
    b:limb({ 0.15, 0.82, 0 }, { 0.2, 0.78, 0 }, 0.04, WHITE)
    b:eyes(0, 0.8, 0.15, 0.06, 0.06)
end

R.chefcrab = function(b)
    for i = 0, 2 do
        for _, sx in ipairs({ -1, 1 }) do
            b:limb({ sx * 0.18, 0.3, -0.1 + i * 0.1 }, { sx * 0.32, 0.03, -0.12 + i * 0.12 }, 0.04, "#d63a2a")
        end
    end
    b:ball(0, 0.38, 0, 0.6, 0.32, 0.46, "#e2452f")
    b:eyes(0, 0.6, 0.12, 0.08, 0.08)
    b:limb({ -0.08, 0.5, 0.12 }, { -0.08, 0.58, 0.12 }, 0.03, "#e2452f")
    b:limb({ 0.08, 0.5, 0.12 }, { 0.08, 0.58, 0.12 }, 0.03, "#e2452f")
    for _, sx in ipairs({ -1, 1 }) do
        b:limb({ sx * 0.28, 0.4, 0.08 }, { sx * 0.36, 0.55, 0.22 }, 0.06, "#d63a2a")
        b:ball(sx * 0.37, 0.62, 0.24, 0.18, 0.12, 0.12, "#e2452f")
        b:box(sx * 0.37, 0.66, 0.3, 0.12, 0.03, 0.06, "#e2452f", 20, 0, 0)
    end
    b:cyl(0, 0.68, 0, 0.26, 0.18, 0.26, WHITE)
    b:ball(0, 0.82, 0, 0.36, 0.18, 0.36, WHITE)
    b:box(0.42, 0.75, 0.24, 0.02, 0.26, 0.02, "#2a1a3a", 0, 0, -15)
    b:ball(0.45, 0.88, 0.24, 0.04, 0.04, 0.04, "#fff5a0", 0, 0, 0, { emit = { 2, 2, 1 } })
end

R.lionel = function(b)
    b:sandal(-0.1, 0, 1)
    b:sandal(0.1, 0, 1)
    b:limb({ -0.1, 0.3, 0 }, { -0.1, 0.06, 0 }, 0.12, "#4f9a3a", "cyl")
    b:limb({ 0.1, 0.3, 0 }, { 0.1, 0.06, 0 }, 0.12, "#4f9a3a", "cyl")
    b:cap(0, 0.5, 0, 0.36, 0.55, 0.32, "#4f9a3a")
    b:spines(0, 0.5, 0, 0.18, 0.4, 14)
    for i = 0, 9 do
        local a = i / 10 * math.pi * 2
        b:ball(math.sin(a) * 0.17, 0.86 + math.cos(a) * 0.17, -0.02, 0.16, 0.16, 0.12, "#a0522d")
    end
    b:ball(0, 0.86, 0.04, 0.32, 0.3, 0.28, "#e8b04a")
    b:ball(0, 0.8, 0.16, 0.14, 0.1, 0.1, "#f5d79a")
    b:box(0, 0.82, 0.22, 0.05, 0.03, 0.02, BLACK)
    b:eyes(0, 0.92, 0.15, 0.06, 0.07)
end

R.glorbo = function(b)
    b:leg(-0.12, 0, 0.25, 0.1, "#3a8f3a", "#2a6a2a")
    b:leg(0.12, 0, 0.25, 0.1, "#3a8f3a", "#2a6a2a")
    b:watermelon(0, 0.5, 0, 0.56, 0.58, 0.52)
    b:ball(0, 0.5, 0.2, 0.42, 0.44, 0.14, "#e94b5b")
    for i = 0, 5 do b:ball(-0.1 + (i % 3) * 0.1, 0.42 + math.floor(i / 3) * 0.14, 0.27, 0.03, 0.04, 0.01, BLACK) end
    b:crocHead(0, 0.88, 0.05, 1.0, "#3a8f3a")
end

R.blueberry = function(b)
    for i = 0, 7 do
        local a = i / 8 * math.pi * 2
        b:limb({ math.sin(a) * 0.14, 0.32, math.cos(a) * 0.14 }, { math.sin(a) * 0.36, 0.04, math.cos(a) * 0.36 }, 0.07, "#3d5fc4")
        b:ball(math.sin(a) * 0.37, 0.03, math.cos(a) * 0.37, 0.07, 0.04, 0.07, "#5a7be0")
    end
    b:ball(0, 0.58, 0, 0.62, 0.6, 0.6, "#2c3e94")
    b:ball(0, 0.58, 0, 0.5, 0.48, 0.62, "#3b4fb0")
    for i = 0, 4 do
        local a = i / 5 * math.pi * 2
        b:box(math.sin(a) * 0.06, 0.9, math.cos(a) * 0.06, 0.06, 0.08, 0.02, "#1e2a66", 25, a * V.DEG, 0)
    end
    b:eyes(0, 0.64, 0.28, 0.1, 0.1)
    b:box(0, 0.5, 0.3, 0.1, 0.02, 0.01, "#1e2a66")
end

R.strawberry = function(b)
    b:leg(-0.07, 0, 0.46, 0.03, "#ff7aa8", "#ff5a90")
    b:leg(0.07, 0, 0.46, 0.03, "#ff7aa8", "#ff5a90")
    b:ball(0, 0.6, 0, 0.42, 0.36, 0.48, "#e3263f")
    for i = 0, 11 do
        local a = i * 2.4
        b:ball(math.sin(a) * 0.2, 0.55 + math.cos(a * 1.3) * 0.12, math.cos(a) * 0.23, 0.025, 0.035, 0.025, "#ffe27a")
    end
    for i = 0, 4 do
        local a = i / 5 * math.pi * 2
        b:box(math.sin(a) * 0.1, 0.78, math.cos(a) * 0.1 - 0.05, 0.08, 0.02, 0.12, "#2f9e44", 0, a * V.DEG, 0)
    end
    b:limb({ 0, 0.7, 0.18 }, { 0, 0.98, 0.2 }, 0.06, "#ff8db5")
    b:ball(0, 1.02, 0.24, 0.16, 0.14, 0.18, "#ff8db5")
    b:box(0, 0.98, 0.36, 0.05, 0.05, 0.1, BLACK, 30, 0, 0)
    b:eyes(0, 1.04, 0.28, 0.05, 0.06)
end

R.frigo = function(b)
    b:box(-0.11, 0.05, 0.04, 0.14, 0.1, 0.22, "#6b3f1a")
    b:box(0.11, 0.05, 0.04, 0.14, 0.1, 0.22, "#6b3f1a")
    b:box(0, 0.42, 0, 0.44, 0.66, 0.36, "#f2f4f7", 0, 0, 0, { shiny = true })
    b:box(0, 0.58, 0.181, 0.42, 0.01, 0.01, "#b8bec7")
    b:box(0.15, 0.48, 0.19, 0.03, 0.18, 0.03, "#9aa2ad", 0, 0, 0, { shiny = true, metal = 0.8 })
    b:limb({ 0, 0.72, 0.08 }, { 0, 0.98, 0.18 }, 0.1, "#c79a5c")
    b:ball(0, 1.02, 0.24, 0.16, 0.14, 0.22, "#c79a5c")
    b:eyes(0, 1.06, 0.26, 0.05, 0.06)
    b:ball(-0.06, 0.8, -0.05, 0.14, 0.14, 0.14, "#b8894d")
    b:ball(0.06, 0.8, -0.1, 0.12, 0.12, 0.12, "#b8894d")
end

R.orangutini = function(b)
    b:box(-0.1, 0.04, 0.05, 0.14, 0.08, 0.18, "#b5531e")
    b:box(0.1, 0.04, 0.05, 0.14, 0.08, 0.18, "#b5531e")
    b:ball(0, 0.42, 0, 0.5, 0.62, 0.46, "#f2b632")
    for i = 0, 11 do
        local a = i * 1.9
        b:box(math.sin(a) * 0.23, 0.3 + (i % 4) * 0.08, math.cos(a) * 0.21, 0.06, 0.06, 0.01, "#c58a1b", 0, a * V.DEG, 45)
    end
    for i = 0, 5 do
        local a = i / 6 * math.pi * 2
        b:box(math.sin(a) * 0.05, 1.0, math.cos(a) * 0.05, 0.05, 0.26, 0.02, "#3c9a3c", math.cos(a) * 25, 0, -math.sin(a) * 25)
    end
    b:ball(0, 0.8, 0.06, 0.36, 0.3, 0.3, "#c0581f")
    b:ball(0, 0.78, 0.17, 0.24, 0.18, 0.12, "#e8a774")
    b:eyes(0, 0.84, 0.2, 0.05, 0.06)
    b:limb({ 0.24, 0.55, 0 }, { 0.42, 0.2, 0.08 }, 0.08, "#c0581f")
    b:limb({ -0.24, 0.55, 0 }, { -0.42, 0.2, 0.08 }, 0.08, "#c0581f")
end

R.rhino = function(b)
    b:leg(-0.12, 0, 0.22, 0.12, "#8e9399", "#5c6066")
    b:leg(0.12, 0, 0.22, 0.12, "#8e9399", "#5c6066")
    b:box(0, 0.44, 0, 0.56, 0.44, 0.36, "#c9ced6", 0, 0, 0, { shiny = true, metal = 0.8 })
    b:box(-0.11, 0.68, 0, 0.08, 0.04, 0.26, "#2a2a2a")
    b:box(0.11, 0.68, 0, 0.08, 0.04, 0.26, "#2a2a2a")
    b:box(-0.11, 0.74, 0, 0.06, 0.14, 0.2, "#d79a4f")
    b:box(0.11, 0.74, 0, 0.06, 0.14, 0.2, "#d79a4f")
    b:box(0.3, 0.44, 0.08, 0.04, 0.06, 0.12, "#333333")
    b:ball(0, 0.5, 0.26, 0.34, 0.3, 0.3, "#8e9399")
    b:box(0, 0.6, 0.4, 0.06, 0.14, 0.06, "#ece5d0", -20, 0, 0)
    b:box(0, 0.52, 0.41, 0.07, 0.06, 0.05, "#ece5d0")
    b:eyes(0, 0.56, 0.37, 0.05, 0.1)
end

R.bombardiro = function(b)
    -- aviao bombardeiro com cabeca de crocodilo
    b:cap(0, 0.55, -0.05, 0.36, 1.1, 0.36, "#5d7a3a", 90, 0, 0)
    b:crocHead(0, 0.58, 0.48, 1.0, "#4f8a3a")
    b:box(0, 0.58, 0, 1.4, 0.05, 0.3, "#6d8a46")
    b:box(0, 0.72, -0.55, 0.04, 0.3, 0.2, "#6d8a46")
    b:box(0, 0.6, -0.55, 0.5, 0.04, 0.16, "#6d8a46")
    for _, sx in ipairs({ -1, 1 }) do
        b:cyl(sx * 0.42, 0.54, 0.06, 0.14, 0.26, 0.14, "#40542a", 90, 0, 0)
        b:box(sx * 0.42, 0.54, 0.2, 0.3, 0.03, 0.02, "#222222", 0, 0, 30)
        b:cap(sx * 0.3, 0.38, 0.04, 0.1, 0.26, 0.1, "#2f3338", 90, 0, 0)
    end
    b:box(0, 0.6, 0.15, 0.22, 0.03, 0.24, "#c8102e", 0, 0, 0)
    b:leg(-0.1, 0.05, 0.38, 0.05, "#3c3c3c", "#222222")
    b:leg(0.1, 0.05, 0.38, 0.05, "#3c3c3c", "#222222")
end

R.bombombini = function(b)
    b:box(-0.08, 0.04, 0.08, 0.16, 0.06, 0.2, "#ff9f1c")
    b:box(0.08, 0.04, 0.08, 0.16, 0.06, 0.2, "#ff9f1c")
    b:limb({ -0.08, 0.3, 0 }, { -0.08, 0.06, 0.04 }, 0.04, "#ff9f1c")
    b:limb({ 0.08, 0.3, 0 }, { 0.08, 0.06, 0.04 }, 0.04, "#ff9f1c")
    b:ball(0, 0.45, -0.02, 0.44, 0.38, 0.62, WHITE)
    b:limb({ 0, 0.55, 0.18 }, { 0, 0.88, 0.22 }, 0.12, WHITE)
    b:ball(0, 0.92, 0.25, 0.18, 0.16, 0.22, WHITE)
    b:box(0, 0.9, 0.38, 0.08, 0.05, 0.12, "#ff9f1c")
    b:eyes(0, 0.96, 0.3, 0.05, 0.07)
    for _, sx in ipairs({ -1, 1 }) do
        b:box(sx * 0.4, 0.5, 0, 0.5, 0.04, 0.24, "#9aa3ad", 0, 0, sx * -8)
        b:cyl(sx * 0.42, 0.44, 0.0, 0.14, 0.3, 0.14, "#5a6470", 90, 0, 0, { shiny = true, metal = 0.8 })
        b:cyl(sx * 0.42, 0.44, -0.16, 0.1, 0.02, 0.1, "#ff7b00", 90, 0, 0, { emit = { 2, 0.7, 0.1 } })
    end
end

R.spioniro = function(b)
    b:leg(-0.06, 0, 0.3, 0.03, "#e3866a", "#c0604a")
    b:leg(0.06, 0, 0.3, 0.03, "#e3866a", "#c0604a")
    b:ball(0, 0.5, 0, 0.42, 0.48, 0.46, "#8b8f99")
    b:box(0, 0.45, 0.05, 0.44, 0.36, 0.44, "#b08a5a")               -- sobretudo
    b:ball(0, 0.64, 0.14, 0.2, 0.18, 0.12, "#5aa58a")
    b:ball(0, 0.82, 0.06, 0.28, 0.26, 0.28, "#9aa0aa")
    b:box(0, 0.86, 0.19, 0.26, 0.05, 0.03, BLACK, 0, 0, 0, { shiny = true })
    b:box(0, 0.78, 0.22, 0.06, 0.04, 0.08, "#4a4a4a")
    b:cyl(0, 0.96, 0.04, 0.36, 0.02, 0.36, "#5a4632")
    b:cyl(0, 1.02, 0.04, 0.2, 0.1, 0.2, "#5a4632")
    b:box(0.22, 0.5, 0.18, 0.14, 0.1, 0.08, BLACK)
    b:cyl(0.22, 0.5, 0.23, 0.06, 0.04, 0.06, "#6fb7ff", 90, 0, 0, { shiny = true })
end

R.zibra = function(b)
    for _, p in ipairs({ { -0.14, 0.18 }, { 0.14, 0.18 }, { -0.14, -0.18 }, { 0.14, -0.18 } }) do
        b:limb({ p[1], 0.38, p[2] }, { p[1], 0.04, p[2] }, 0.08, WHITE, "cyl")
        b:box(p[1], 0.03, p[2], 0.09, 0.06, 0.09, BLACK)
    end
    b:box(0, 0.5, 0, 0.36, 0.28, 0.6, WHITE)
    for i = 0, 5 do b:box(0, 0.5, -0.25 + i * 0.1, 0.37, 0.29, 0.03, BLACK) end
    b:box(0, 0.74, 0.3, 0.14, 0.34, 0.14, WHITE, -25, 0, 0)
    b:box(0, 0.74, 0.3, 0.15, 0.04, 0.15, BLACK, -25, 0, 0)
    b:box(0, 0.9, 0.44, 0.16, 0.16, 0.28, WHITE)
    b:box(0, 0.86, 0.6, 0.15, 0.12, 0.06, "#333333")
    b:box(0, 1.0, 0.34, 0.03, 0.06, 0.24, BLACK)
    b:eyes(0, 0.95, 0.53, 0.05, 0.07)
    b:box(-0.05, 1.03, 0.38, 0.03, 0.08, 0.03, WHITE)
    b:box(0.05, 1.03, 0.38, 0.03, 0.08, 0.03, WHITE)
end

R.tigrilini = function(b)
    b:leg(-0.12, 0, 0.25, 0.1, "#f28c28", "#2a2a2a")
    b:leg(0.12, 0, 0.25, 0.1, "#f28c28", "#2a2a2a")
    b:watermelon(0, 0.48, 0, 0.56, 0.56, 0.52)
    b:ball(0, 0.86, 0.04, 0.38, 0.34, 0.34, "#f28c28")
    for i = 0, 3 do b:box(0, 0.92 + (i % 2) * 0.04, -0.06 + i * 0.05, 0.39, 0.03, 0.02, BLACK) end
    b:ball(0, 0.8, 0.17, 0.2, 0.14, 0.12, WHITE)
    b:box(0, 0.83, 0.23, 0.05, 0.03, 0.02, "#ff6f91")
    b:eyes(0, 0.9, 0.16, 0.06, 0.07, { white = "#d8f56a" })
    b:box(-0.13, 1.03, 0.02, 0.08, 0.08, 0.04, "#f28c28")
    b:box(0.13, 1.03, 0.02, 0.08, 0.08, 0.04, "#f28c28")
end

R.cavallo = function(b)
    b:leg(-0.08, 0, 0.42, 0.08, "#8b5a2b", "#3a2410")
    b:leg(0.08, 0, 0.42, 0.08, "#8b5a2b", "#3a2410")
    b:box(0, 0.6, 0, 0.32, 0.36, 0.22, "#1d1d1d")                     -- fraque
    b:box(0, 0.62, 0.11, 0.08, 0.3, 0.01, WHITE)
    b:box(0, 0.74, 0.115, 0.08, 0.03, 0.01, "#c0392b")
    b:limb({ 0, 0.78, 0.0 }, { 0, 0.94, 0.06 }, 0.12, "#8b5a2b")
    b:box(0, 0.98, 0.16, 0.16, 0.18, 0.36, "#8b5a2b", 20, 0, 0)
    b:box(0, 0.92, 0.32, 0.14, 0.1, 0.06, "#5e3b1c", 20, 0, 0)
    b:box(0, 1.08, 0.0, 0.04, 0.14, 0.2, "#2a1a0a")
    b:eyes(0, 1.04, 0.24, 0.05, 0.07)
    b:box(-0.06, 1.12, 0.06, 0.03, 0.08, 0.03, "#8b5a2b")
    b:box(0.06, 1.12, 0.06, 0.03, 0.08, 0.03, "#8b5a2b")
    -- violino
    b:ball(-0.2, 0.72, 0.18, 0.12, 0.16, 0.05, "#a0522d", 0, 0, 30, { shiny = true })
    b:box(-0.12, 0.84, 0.18, 0.025, 0.18, 0.02, "#2a1a0a", 0, 0, 30)
    b:box(0.06, 0.78, 0.22, 0.01, 0.01, 0.4, "#e8dcc0", 0, 50, 0)
    b:limb({ 0.16, 0.7, 0 }, { 0.1, 0.76, 0.2 }, 0.06, "#1d1d1d")
    b:limb({ -0.16, 0.7, 0 }, { -0.24, 0.78, 0.14 }, 0.06, "#1d1d1d")
end

R.cocofanto = function(b)
    b:leg(-0.14, 0, 0.3, 0.14, "#9a9ca3", "#6a6c73")
    b:leg(0.14, 0, 0.3, 0.14, "#9a9ca3", "#6a6c73")
    b:ball(0, 0.56, 0, 0.62, 0.58, 0.56, "#5a3a1e")
    b:ball(0, 0.56, 0.04, 0.56, 0.54, 0.54, "#6b4423")
    for i = 0, 2 do b:ball(-0.1 + i * 0.1, 0.72, 0.27, 0.04, 0.04, 0.02, "#2a1a0a") end
    b:elephantHead(0, 0.98, 0.06, 1.1, "#9a9ca3")
    b:limb({ 0.3, 0.62, 0 }, { 0.46, 0.4, 0.1 }, 0.13, "#9a9ca3")
    b:limb({ -0.3, 0.62, 0 }, { -0.46, 0.4, 0.1 }, 0.13, "#9a9ca3")
end

R.girafa = function(b)
    for _, p in ipairs({ { -0.12, 0.12 }, { 0.12, 0.12 }, { -0.12, -0.14 }, { 0.12, -0.14 } }) do
        b:limb({ p[1], 0.36, p[2] }, { p[1], 0.03, p[2] }, 0.06, "#7b6cff", "cyl")
    end
    b:box(0, 0.42, 0, 0.3, 0.2, 0.42, "#6b5cf0")
    b:limb({ 0, 0.48, 0.16 }, { 0, 0.98, 0.26 }, 0.1, "#6b5cf0")
    b:box(0, 1.02, 0.34, 0.14, 0.12, 0.24, "#6b5cf0")
    b:eyes(0, 1.06, 0.4, 0.05, 0.06)
    b:box(-0.04, 1.12, 0.26, 0.02, 0.08, 0.02, "#ffe066", 0, 0, 0, { emit = { 2, 1.8, 0.6 } })
    b:box(0.04, 1.12, 0.26, 0.02, 0.08, 0.02, "#ffe066", 0, 0, 0, { emit = { 2, 1.8, 0.6 } })
    for i = 0, 9 do
        local a = i * 2.1
        b:box(math.sin(a) * 0.16, 0.42 + (i % 3) * 0.2, math.cos(a) * 0.12 + (i % 3) * 0.08, 0.05, 0.05, 0.05, "#fff3a0", 45, a * V.DEG, 45, { emit = { 1.8, 1.7, 0.8 } })
    end
    b:ball(-0.2, 0.55, -0.08, 0.06, 0.24, 0.32, "#c7bfff", 0, 0, 30)
    b:ball(0.2, 0.55, -0.08, 0.06, 0.24, 0.32, "#c7bfff", 0, 0, -30)
end

R.gattatino = function(b)
    local neon = { 0.4, 1.6, 2.0 }
    b:leg(-0.08, 0, 0.3, 0.07, "#2a2a3a", "#ff3df2")
    b:leg(0.08, 0, 0.3, 0.07, "#2a2a3a", "#ff3df2")
    b:cap(0, 0.5, 0, 0.32, 0.5, 0.28, "#24243a")
    b:box(0, 0.5, 0.14, 0.04, 0.4, 0.01, "#4af2ff", 0, 0, 0, { emit = neon })
    b:box(-0.16, 0.5, 0, 0.01, 0.4, 0.04, "#ff3df2", 0, 0, 0, { emit = { 2, 0.3, 1.9 } })
    b:box(0.16, 0.5, 0, 0.01, 0.4, 0.04, "#ff3df2", 0, 0, 0, { emit = { 2, 0.3, 1.9 } })
    b:catHead(0, 0.88, 0.04, 1.0, "#2a2a44", "#4af2ff")
    b:limb({ 0, 0.36, -0.14 }, { 0, 0.7, -0.34 }, 0.04, "#4af2ff")
end

R.tralalero = function(b)
    b:shark(0, 0, 1.0)
end

R.matteo = function(b)
    b:leg(-0.07, 0, 0.5, 0.07, "#1f2a44", "#111111")
    b:leg(0.07, 0, 0.5, 0.07, "#1f2a44", "#111111")
    b:box(0, 0.7, 0, 0.3, 0.42, 0.16, "#f2f2f2")
    b:box(0, 0.7, 0.0, 0.32, 0.44, 0.15, "#d4a017")
    b:box(0, 0.7, 0.08, 0.1, 0.4, 0.01, "#f2f2f2")
    b:limb({ 0.17, 0.88, 0 }, { 0.26, 0.42, 0.04 }, 0.06, "#d4a017")
    b:limb({ -0.17, 0.88, 0 }, { -0.26, 0.42, 0.04 }, 0.06, "#d4a017")
    b:ball(0, 1.02, 0, 0.22, 0.26, 0.22, SKIN)
    b:eyes(0, 1.05, 0.1, 0.05, 0.05)
    b:box(0, 0.97, 0.11, 0.1, 0.02, 0.01, "#7a2a2a")
    b:cyl(0, 1.16, 0, 0.34, 0.02, 0.34, "#1d1d1d")
    b:cyl(0, 1.24, 0, 0.2, 0.16, 0.2, "#1d1d1d")
    b:cyl(0, 1.18, 0, 0.21, 0.03, 0.21, "#c0392b")
end

R.crocodillitos = function(b)
    for i, x in ipairs({ -0.3, 0, 0.3 }) do
        b:push(x, 0, (i == 2) and 0.1 or 0, 0, 0, 0, 0.8)
        b:leg(-0.08, 0, 0.22, 0.08, "#3f9b4a", "#2a2a2a")
        b:leg(0.08, 0, 0.22, 0.08, "#3f9b4a", "#2a2a2a")
        b:ball(0, 0.42, 0, 0.32, 0.38, 0.28, "#3f9b4a")
        b:ball(0, 0.4, 0.08, 0.2, 0.28, 0.16, "#c7e39a")
        b:crocHead(0, 0.74, 0.02, 0.8, "#3f9b4a")
        b:box(0, 0.8, 0.12, 0.26, 0.05, 0.02, BLACK, 0, 0, 0, { shiny = true })
        b:pop()
    end
end

R.odin = function(b)
    b:leg(-0.1, 0, 0.36, 0.1, "#5a4632", "#3a2a1a")
    b:leg(0.1, 0, 0.36, 0.1, "#5a4632", "#3a2a1a")
    b:box(0, 0.6, 0, 0.42, 0.44, 0.26, "#2c4a7a")
    b:box(0, 0.42, 0, 0.44, 0.06, 0.27, "#8b5a2b")
    b:box(0, 0.6, -0.13, 0.5, 0.5, 0.03, "#8a1c1c")                   -- capa
    b:limb({ 0.24, 0.76, 0 }, { 0.34, 0.5, 0.1 }, 0.1, SKIN)
    b:limb({ -0.24, 0.76, 0 }, { -0.34, 0.5, 0.1 }, 0.1, SKIN)
    b:ball(0, 0.96, 0, 0.28, 0.28, 0.28, SKIN)
    b:ball(0, 0.86, 0.08, 0.3, 0.3, 0.2, "#e8e8e8")
    b:eyes(0, 0.99, 0.12, 0.05, 0.06)
    b:ball(0, 1.06, 0, 0.32, 0.2, 0.32, "#9aa2ad", 0, 0, 0, { shiny = true, metal = 0.8 })
    b:cap(-0.2, 1.12, 0, 0.06, 0.22, 0.06, "#f5f0e1", 0, 0, 40)
    b:cap(0.2, 1.12, 0, 0.06, 0.22, 0.06, "#f5f0e1", 0, 0, -40)
    b:box(0.36, 0.7, 0.12, 0.03, 0.9, 0.03, "#5a3a1f")
    b:box(0.36, 1.17, 0.12, 0.06, 0.08, 0.06, "#ffd700", 0, 0, 0, { emit = { 2, 1.6, 0.2 } })
end

R.orcalero = function(b)
    b:push(0, 0, 0, 0, 0, 0, 1.0)
    local y = 0.62
    b:cap(0, y, 0, 0.46, 1.05, 0.46, "#15151a", 90, 0, 0)
    b:ball(0, y - 0.08, 0.08, 0.38, 0.26, 0.86, WHITE)
    b:ball(-0.12, y + 0.1, 0.36, 0.1, 0.07, 0.16, WHITE)
    b:ball(0.12, y + 0.1, 0.36, 0.1, 0.07, 0.16, WHITE)
    b:eyes(0, y + 0.06, 0.48, 0.06, 0.12)
    b:box(0, y + 0.34, -0.05, 0.05, 0.36, 0.18, "#15151a", -15, 0, 0)
    b:box(0, y + 0.02, -0.6, 0.5, 0.05, 0.16, "#15151a")
    for _, p in ipairs({ { -0.11, 0.2 }, { 0.11, 0.2 }, { 0, -0.25 } }) do
        b:limb({ p[1], y - 0.12, p[2] }, { p[1], 0.14, p[2] }, 0.07, SKIN, "cyl")
        b:sneaker(p[1], 0, p[2], 0.85, "#ff3b3b")
    end
    b:pop()
end

R.espresso = function(b)
    b:leg(-0.06, 0, 0.42, 0.05, SKIN, "#c0392b")
    b:leg(0.06, 0, 0.42, 0.05, SKIN, "#c0392b")
    b:cyl(0, 0.46, 0, 0.44, 0.2, 0.44, "#c0392b")
    b:cyl(0, 0.6, 0, 0.26, 0.2, 0.2, "#c0392b")
    b:limb({ 0.14, 0.66, 0 }, { 0.26, 0.48, 0.1 }, 0.045, SKIN)
    b:limb({ -0.14, 0.66, 0 }, { -0.24, 0.5, 0.12 }, 0.045, SKIN)
    b:cyl(0, 0.86, 0, 0.26, 0.22, 0.26, WHITE, 0, 0, 0, { shiny = true })
    b:cyl(0, 0.97, 0, 0.23, 0.02, 0.23, "#3b1f0e")
    b:limb({ 0.13, 0.9, 0 }, { 0.19, 0.84, 0 }, 0.035, WHITE)
    b:cyl(0, 0.75, 0, 0.36, 0.02, 0.36, WHITE)
    b:eyes(0, 0.88, 0.13, 0.06, 0.06, { pupil = "#2a7a3a" })
    b:box(0, 0.82, 0.135, 0.06, 0.02, 0.01, "#d62850")
    b:ball(-0.14, 0.86, 0, 0.03, 0.05, 0.03, "#ffd700", 0, 0, 0, { shiny = true, metal = 0.9 })
    b:ball(0.14, 0.86, 0, 0.03, 0.05, 0.03, "#ffd700", 0, 0, 0, { shiny = true, metal = 0.9 })
end

R.treno = function(b)
    b:box(0, 0.32, -0.05, 0.4, 0.34, 0.8, "#c0392b", 0, 0, 0, { shiny = true })
    b:cyl(0, 0.42, 0.28, 0.36, 0.44, 0.36, "#2a2a2a", 90, 0, 0, { shiny = true, metal = 0.6 })
    b:cyl(0, 0.66, 0.38, 0.1, 0.18, 0.1, "#2a2a2a")
    b:ball(0, 0.78, 0.38, 0.14, 0.1, 0.14, "#dddddd")
    b:box(0, 0.62, -0.3, 0.42, 0.26, 0.3, "#a52a2a")
    for _, z in ipairs({ -0.3, 0.0, 0.3 }) do
        for _, sx in ipairs({ -1, 1 }) do
            b:cyl(sx * 0.22, 0.13, z, 0.24, 0.05, 0.24, "#ffd700", 0, 0, 90, { shiny = true, metal = 0.9 })
        end
    end
    b:limb({ 0, 0.74, -0.3 }, { 0, 1.08, -0.2 }, 0.07, "#f2d0c0")
    b:ball(0, 1.12, -0.16, 0.14, 0.14, 0.16, "#3a3a3a")
    b:box(0, 1.1, -0.04, 0.05, 0.04, 0.1, "#f39c12")
    b:eyes(0, 1.15, -0.1, 0.04, 0.05)
    for i = 0, 3 do b:ball((i - 1.5) * 0.08, 0.84, -0.42, 0.1, 0.12, 0.1, "#2a2a2a") end
end

R.vacca = function(b)
    for _, p in ipairs({ { -0.14, 0.16 }, { 0.14, 0.16 }, { -0.14, -0.16 }, { 0.14, -0.16 } }) do
        b:limb({ p[1], 0.34, p[2] }, { p[1], 0.04, p[2] }, 0.09, WHITE, "cyl")
        b:box(p[1], 0.03, p[2], 0.1, 0.06, 0.1, "#3a2a1a")
    end
    b:ball(0, 0.56, 0, 0.6, 0.5, 0.6, "#f2f2f2")
    for i = 0, 6 do
        local a = i * 2.3
        b:ball(math.sin(a) * 0.24, 0.56 + math.cos(a * 1.7) * 0.12, math.cos(a) * 0.24, 0.14, 0.12, 0.05, "#1c1c1c", 0, a * V.DEG, 0)
    end
    b:cyl(0, 0.56, 0, 1.05, 0.02, 1.05, "#d9b36a", 12, 0, 8, { emit = { 0.9, 0.7, 0.3 } })
    b:cyl(0, 0.56, 0, 0.9, 0.025, 0.9, "#8a6a3a", 12, 0, 8)
    b:ball(0, 0.78, 0.32, 0.3, 0.26, 0.26, "#f2f2f2")
    b:ball(0, 0.72, 0.43, 0.22, 0.14, 0.1, "#ffb3c6")
    b:eyes(0, 0.84, 0.42, 0.05, 0.08)
    b:cap(-0.14, 0.95, 0.3, 0.04, 0.12, 0.04, "#f5f0e1", 0, 0, 30)
    b:cap(0.14, 0.95, 0.3, 0.04, 0.12, 0.04, "#f5f0e1", 0, 0, -30)
end

R.spiderini = function(b)
    for i = 0, 3 do
        for _, sx in ipairs({ -1, 1 }) do
            local z = -0.15 + i * 0.1
            b:limb({ sx * 0.16, 0.42, z }, { sx * 0.36, 0.5, z * 1.6 }, 0.04, "#2a2a2a")
            b:limb({ sx * 0.36, 0.5, z * 1.6 }, { sx * 0.46, 0.02, z * 2.0 }, 0.035, "#2a2a2a")
        end
    end
    b:ball(0, 0.42, -0.12, 0.42, 0.34, 0.46, "#c0392b")
    b:ball(0, 0.42, -0.12, 0.43, 0.06, 0.47, "#1f4fa8")
    b:ball(0, 0.62, 0.12, 0.34, 0.32, 0.3, "#c0392b")
    b:chimpHead(0, 0.82, 0.2, 1.0)
end

R.tralaleritos = function(b)
    b:shark(-0.36, -0.05, 0.62)
    b:shark(0.36, -0.05, 0.62)
    b:shark(0, 0.1, 0.72)
end

R.tralaleritas = function(b)
    b:shark(-0.36, -0.05, 0.62, "#ff6eb4", "#ff3d9a")
    b:shark(0.36, -0.05, 0.62, "#ff6eb4", "#ff3d9a")
    b:shark(0, 0.1, 0.72, "#ff6eb4", "#ff3d9a")
end

R.graipuss = function(b)
    for i = 0, 7 do
        local a = i / 8 * math.pi * 2
        local x, z = math.sin(a) * 0.16, math.cos(a) * 0.16
        b:limb({ x, 0.5, z }, { x * 1.6, 0.22, z * 1.6 }, 0.06, "#c792ea")
        b:limb({ x * 1.6, 0.22, z * 1.6 }, { x * 1.3, 0.03, z * 1.3 }, 0.05, "#c792ea", nil)
    end
    for i = 0, 11 do
        local a = i * 2.4
        local r = 0.12 + (i % 3) * 0.06
        b:ball(math.sin(a) * r, 0.62 + (i % 4) * 0.1, math.cos(a) * r, 0.2, 0.2, 0.2, "#7b2fbf", 0, 0, 0, { shiny = true })
    end
    b:box(0, 1.04, 0, 0.03, 0.12, 0.03, "#5a3a1f")
    b:ball(0.06, 1.08, 0, 0.12, 0.03, 0.06, "#4caf50", 0, 0, 20)
    b:eyes(0, 0.74, 0.25, 0.1, 0.1, { pupil = "#5a0080" })
end

R.combinasion = function(b)
    -- montanha de brainrots
    b:push(0, 0, 0, 0, 0, 0, 0.62)
    R.bombardiro(b)
    b:pop()
    b:push(-0.4, 0, 0.1, 0, 25, 0, 0.55)
    b:shark(0, 0, 1.0)
    b:pop()
    b:push(0.42, 0, 0.1, 0, -25, 0, 0.55)
    R.cappuccino(b)
    b:pop()
    b:push(0, 0.48, -0.05, 0, 0, 0, 0.5)
    R.patapim(b)
    b:pop()
    b:push(0, 0.92, -0.05, 0, 0, 0, 0.36)
    R.ballerina(b)
    b:pop()
end

R.nuclearo = function(b)
    local glow = { 0.4, 2.2, 0.4 }
    b:leg(-0.12, -0.04, 0.3, 0.13, "#3f8f3f", "#2a5a2a")
    b:leg(0.12, -0.04, 0.3, 0.13, "#3f8f3f", "#2a5a2a")
    b:ball(0, 0.52, -0.05, 0.42, 0.5, 0.5, "#3f8f3f")
    b:limb({ 0, 0.4, -0.2 }, { 0, 0.14, -0.6 }, 0.14, "#3f8f3f")
    b:box(0, 0.84, 0.16, 0.34, 0.26, 0.42, "#3f8f3f")
    b:box(0, 0.74, 0.3, 0.3, 0.06, 0.2, "#2f6f2f")
    for i = 0, 4 do b:box(-0.12 + i * 0.06, 0.76, 0.4, 0.025, 0.04, 0.02, WHITE) end
    b:eyes(0, 0.92, 0.32, 0.06, 0.1, { white = "#d8ff6a", pupil = "#ff3b3b" })
    b:limb({ 0.18, 0.6, 0.1 }, { 0.24, 0.5, 0.22 }, 0.05, "#3f8f3f")
    b:limb({ -0.18, 0.6, 0.1 }, { -0.24, 0.5, 0.22 }, 0.05, "#3f8f3f")
    for i = 0, 4 do
        b:box(0, 0.66 + i * 0.08, -0.22 - i * 0.02, 0.04, 0.1, 0.1, "#9cff57", 45, 0, 0, { emit = glow })
    end
    b:cyl(0, 0.56, 0.2, 0.2, 0.01, 0.2, "#ffd60a", 90, 0, 0, { emit = { 2, 1.8, 0.1 } })
    for k = 0, 2 do
        b:box(math.sin(k * 2.09) * 0.05, 0.56 + math.cos(k * 2.09) * 0.05, 0.207, 0.05, 0.06, 0.01, BLACK, 0, 0, -k * 120)
    end
end

R.dragon = function(b)
    local cream = "#f1deb0"
    for _, sx in ipairs({ -1, 1 }) do
        b:limb({ sx * 0.14, 0.3, 0 }, { sx * 0.16, 0.04, 0.04 }, 0.1, cream, "cyl")
        b:box(sx * 0.16, 0.03, 0.08, 0.14, 0.06, 0.18, "#d9c08a")
    end
    for i = 0, 4 do
        b:cyl(0, 0.42 + i * 0.08, -0.05 + i * 0.05, 0.36 - i * 0.03, 0.12, 0.36 - i * 0.03, cream, 70, 0, 0)
        b:cyl(0, 0.42 + i * 0.08, -0.05 + i * 0.05, 0.37 - i * 0.03, 0.03, 0.37 - i * 0.03, "#d62828", 70, 0, 0)
    end
    b:cyl(0, 0.86, 0.32, 0.2, 0.36, 0.2, cream, 70, 0, 0)
    b:cyl(0, 0.8, 0.5, 0.17, 0.02, 0.17, "#d62828", 70, 0, 0)
    b:eyes(0, 0.96, 0.4, 0.06, 0.08, { white = "#ffe066", pupil = "#d62828" })
    b:cap(-0.07, 1.06, 0.26, 0.04, 0.16, 0.04, "#d9c08a", -30, 0, 15)
    b:cap(0.07, 1.06, 0.26, 0.04, 0.16, 0.04, "#d9c08a", -30, 0, -15)
    for _, sx in ipairs({ -1, 1 }) do
        b:box(sx * 0.36, 0.86, -0.12, 0.5, 0.03, 0.34, "#d62828", 0, sx * 15, sx * 25)
        b:box(sx * 0.32, 0.88, -0.12, 0.4, 0.035, 0.08, cream, 0, sx * 15, sx * 25)
    end
    b:limb({ 0, 0.4, -0.18 }, { 0, 0.18, -0.55 }, 0.1, cream)
    b:ball(0, 0.94, 0.56, 0.08, 0.08, 0.1, "#ff7b00", 0, 0, 0, { emit = { 2.5, 0.9, 0.1 } })
end

M.recipes = R

---------------------------------------------------------------------------
-- Mutacoes
---------------------------------------------------------------------------
local function lerpC(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function lum(c) return c[1] * 0.3 + c[2] * 0.59 + c[3] * 0.11 end

local function hsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end
M.hsv = hsv

function M.applyMutation(inst, mut)
    inst.mut = mut
    for i, p in ipairs(inst.parts) do
        local c = p.c
        local nc, mat = c, nil
        if mut == "gold" then
            nc = lerpC(c, { 1.0, 0.78, 0.18 }, 0.7); mat = { metal = 0.85, smooth = 0.8 }
        elseif mut == "diamond" then
            nc = lerpC(c, { 0.55, 0.92, 1.0 }, 0.7); mat = { metal = 0.3, smooth = 0.97, emit = { 0.05, 0.18, 0.25 } }
        elseif mut == "halloween" then
            if lum(c) > 0.45 then nc = lerpC(c, { 1.0, 0.45, 0.05 }, 0.65) else nc = lerpC(c, { 0.2, 0.06, 0.25 }, 0.6) end
            mat = { emit = { 0.25, 0.08, 0.0 } }
        elseif mut == "candy" then
            nc = lerpC(c, (i % 2 == 0) and { 1.0, 0.45, 0.75 } or { 0.65, 1.0, 0.85 }, 0.6)
            mat = { smooth = 0.9 }
        elseif mut == "lava" then
            if i % 3 == 0 then nc = { 1.0, 0.4, 0.05 }; mat = { emit = { 2.2, 0.6, 0.05 } }
            else nc = lerpC(c, { 0.18, 0.07, 0.04 }, 0.7); mat = { emit = { 0.25, 0.04, 0.0 } } end
        elseif mut == "rainbow" then
            local r, g, b = hsv((i * 0.13) % 1, 0.7, 1)
            nc = { r, g, b }; mat = { emit = { r * 0.3, g * 0.3, b * 0.3 } }
        end
        if nc ~= c then A.color(p.o, nc) end
        if mat then A.material(p.o, mat) end
    end
end

---------------------------------------------------------------------------
-- Construcao / animacao
---------------------------------------------------------------------------
-- Cria o modelo. Retorna inst { root, body, parts, size, def }.
-- root: ponto no chao; body: no animado (pulo/balanco).
function M.build(def, parent, mut)
    local root = A.empty("br_" .. def.id, parent)
    local body = A.empty("body", root)
    local size = def.rar.size
    A.scale(body, size, size, size)
    local b = newBuilder(body)
    local recipe = R[def.id]
    if recipe then recipe(b) else b:ball(0, 0.5, 0, 0.6, 1, 0.6, "#ff00ff") end
    local inst = { root = root, body = body, parts = b.parts, size = size, def = def, phase = math.random() * 6.28, extras = {} }
    -- enfeites de raridade
    if def.rarity == "god" then
        local halo = A.prim("cylinder", { parent = body, pos = { 0, 1.32, 0 }, scale = { 0.42, 0.012, 0.42 }, color = { 1, 0.85, 0.3 } })
        A.material(halo, { emit = { 2.2, 1.7, 0.5 } })
        inst.halo = halo
    elseif def.rarity == "secret" then
        inst.sparkles = {}
        for i = 1, 6 do
            local s = A.prim("cube", { parent = root, scale = { 0.05, 0.05, 0.05 }, rot = { 45, 0, 45 }, color = { 1, 1, 1 } })
            A.material(s, { emit = { 2.5, 2.5, 2.5 }, noShadow = true })
            inst.sparkles[i] = s
        end
    end
    if mut and mut ~= "none" then M.applyMutation(inst, mut) end
    return inst
end

-- anim: "idle" | "walk" | "carried"
function M.animate(inst, t, anim)
    local ph = inst.phase + t
    if anim == "walk" then
        local s = math.sin(ph * 9)
        A.posXYZ(inst.body, 0, math.abs(s) * 0.06, 0)
        A.rot(inst.body, 0, 0, s * 7)
    elseif anim == "carried" then
        A.posXYZ(inst.body, 0, math.sin(ph * 5) * 0.03, 0)
        A.rot(inst.body, math.sin(ph * 3) * 6, 0, math.sin(ph * 4) * 8)
    else
        local s = math.sin(ph * 2.2)
        A.posXYZ(inst.body, 0, (s * 0.5 + 0.5) * 0.04, 0)
        A.rot(inst.body, 0, math.sin(ph * 0.9) * 10, s * 2)
    end
    if inst.halo then A.rot(inst.halo, 0, ph * 60, 0) end
    if inst.sparkles then
        for i, s in ipairs(inst.sparkles) do
            local a = ph * 1.3 + i * 1.047
            local y = inst.size * (0.3 + 0.5 * ((math.sin(ph * 0.8 + i) + 1) / 2))
            A.posXYZ(s, math.sin(a) * inst.size * 0.62, y, math.cos(a) * inst.size * 0.62)
            A.rot(s, ph * 90 + i * 20, ph * 120, 45)
        end
    end
    if inst.mut == "rainbow" and inst.parts[1] then
        -- arco-iris anda devagar (atualiza poucas pecas por frame)
        inst.rbi = ((inst.rbi or 0) % #inst.parts) + 1
        for k = 0, 2 do
            local idx = ((inst.rbi + k * 7 - 1) % #inst.parts) + 1
            local p = inst.parts[idx]
            local r, g, bb = hsv((idx * 0.13 + t * 0.2) % 1, 0.7, 1)
            A.colorRGB(p.o, r, g, bb)
        end
    end
end

function M.destroy(inst)
    if inst and inst.root then A.destroy(inst.root) end
end

return M
