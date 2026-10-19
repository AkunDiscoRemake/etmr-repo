-- world.lua — monta o mapa: ceu, chao, esteira vermelha, 8 bases, loja, altar, decoracao.
-- Guarda referencias das partes dinamicas (lasers, placas, botoes) em W.bases[i].

local V = require("vec")
local A = require("api")
local Lt = require("layout")
local Tx = require("text3d")
local L10 = require("i18n")

local W = {}

W.root = nil
W.obstacles = {}     -- para o rig: { box = {minX,maxX,minZ,maxZ} } ou { x, z, r }
W.bases = {}
W.lamps = {}
W.clouds = {}
W.sky = {}

W.BASE_COLORS = {
    { 0.92, 0.26, 0.24 }, { 0.22, 0.52, 0.95 }, { 0.28, 0.78, 0.35 }, { 0.98, 0.78, 0.18 },
    { 0.62, 0.36, 0.92 }, { 0.98, 0.55, 0.15 }, { 0.20, 0.80, 0.85 }, { 0.98, 0.45, 0.72 },
}

local function prim(kind, pos, scale, color, tex, rot, mat, parent)
    return A.prim(kind, { parent = parent or W.root, pos = pos, scale = scale, color = color, tex = tex, rot = rot, mat = mat })
end

local function boxObstacle(mn, mx)
    W.obstacles[#W.obstacles + 1] = { box = { mn[1], mx[1], mn[3], mx[3] } }
end

-- caixa no espaco da base (u, v = centro; w = largura em u; d = profundidade em v)
local function baseBox(i, u, v, y, w, h, d, color, tex, obstacle, parent, mat)
    local b = Lt.bases[i]
    local c = Lt.basePoint(i, u, v, y)
    local o = prim("cube", c, { w, h, d }, color, tex, { 0, b.yaw, 0 }, mat, parent)
    if obstacle then
        local p1 = Lt.basePoint(i, u - w / 2, v - d / 2)
        local p2 = Lt.basePoint(i, u + w / 2, v + d / 2)
        boxObstacle({ math.min(p1[1], p2[1]), 0, math.min(p1[3], p2[3]) }, { math.max(p1[1], p2[1]), 0, math.max(p1[3], p2[3]) })
    end
    return o
end

---------------------------------------------------------------------------
-- Ceu
---------------------------------------------------------------------------
local SKY_R = 150
local function buildSky()
    local root = A.empty("sky", W.root)
    W.sky.root = root
    W.sky.sides = {}
    -- 4 lados (quads olhando para dentro) + topo
    local sides = { { 0, 0, SKY_R, 0 }, { 0, 0, -SKY_R, 180 }, { SKY_R, 0, 0, 90 }, { -SKY_R, 0, 0, -90 } }
    for _, s in ipairs(sides) do
        local q = prim("quad", { s[1], 40, s[3] }, { SKY_R * 2.02, 140, 1 }, { 1, 1, 1 }, "images/sky_day.png", { 0, s[4], 0 }, nil, root)
        W.sky.unlit = A.unlit(q)
        W.sky.sides[#W.sky.sides + 1] = q
    end
    W.sky.top = prim("quad", { 0, 109, 0 }, { SKY_R * 2.05, SKY_R * 2.05, 1 }, { 0.36, 0.62, 1.0 }, nil, { -90, 0, 0 }, nil, root)
    A.unlit(W.sky.top)
    -- sol e lua
    W.sky.sun = prim("sphere", { 60, 70, 90 }, { 12, 12, 12 }, { 1, 0.95, 0.7 }, nil, nil, { emit = { 2.2, 2.0, 1.2 }, noShadow = true }, root)
    W.sky.moon = prim("sphere", { -60, 60, 90 }, { 9, 9, 9 }, { 0.9, 0.92, 1.0 }, nil, nil, { emit = { 1.2, 1.25, 1.4 }, noShadow = true }, root)
    A.setVisible(W.sky.moon, false, 9, 9, 9)
    -- nuvens blocadas
    for i = 1, 14 do
        local a = i / 14 * math.pi * 2
        local r = 70 + (i % 3) * 18
        local c = A.empty("cloud", root, { math.sin(a) * r, 34 + (i % 4) * 5, math.cos(a) * r })
        for k = 1, 3 + i % 3 do
            prim("cube", { (k - 2) * 4.5, (k % 2) * 1.5, (k % 3 - 1) * 2.5 }, { 7 + (k % 2) * 3, 3, 5 + (k % 3) * 2 }, { 1, 1, 1 }, nil, nil,
                { emit = { 0.55, 0.55, 0.6 }, noShadow = true }, c)
        end
        W.clouds[#W.clouds + 1] = { o = c, a = a, r = r, y = 34 + (i % 4) * 5, spd = 0.004 + (i % 5) * 0.001 }
    end
end

-- kind: "day" | "night" | "lava" | "candy"
function W.setSky(kind)
    if W.sky.kind == kind then return end
    W.sky.kind = kind
    local tex = "images/sky_" .. kind .. ".png"
    for _, q in ipairs(W.sky.sides) do A.texture(q, tex) end
    local top = ({ day = { 0.36, 0.62, 1.0 }, night = { 0.04, 0.03, 0.12 }, lava = { 0.35, 0.05, 0.02 }, candy = { 1.0, 0.62, 0.85 } })[kind]
    A.color(W.sky.top, top)
    if not W.sky.unlit then
        A.material(W.sky.top, { emit = V.scale(top, 0.9) })
        for _, q in ipairs(W.sky.sides) do
            A.material(q, { emit = ({ day = { 0.8, 0.8, 0.85 }, night = { 0.5, 0.5, 0.6 }, lava = { 0.9, 0.6, 0.5 }, candy = { 0.9, 0.8, 0.85 } })[kind] })
        end
    end
    local night = kind == "night"
    A.setVisible(W.sky.sun, not night, 12, 12, 12)
    A.setVisible(W.sky.moon, night, 9, 9, 9)
    for _, c in ipairs(W.clouds) do A.setVisible(c.o, not night) end
    for _, l in ipairs(W.lamps) do
        A.material(l, { emit = night and { 3.0, 2.4, 1.2 } or { 0.4, 0.35, 0.2 } })
    end
end

---------------------------------------------------------------------------
-- Chao, esteira, caminhos
---------------------------------------------------------------------------
local function buildGround()
    local B = Lt.BOUNDS
    local w, d = (B[2] - B[1]) + 60, (B[4] - B[3]) + 60
    local g = prim("plane", { 0, 0, 0 }, { w / 10, 1, d / 10 }, { 1, 1, 1 }, "images/grass.png", nil, { smooth = 0.1 })
    A.tiling(g, w / 2, d / 2)
    -- calcada de pedra em volta da esteira
    local cz = (Lt.CARPET.z1 - Lt.CARPET.z0)
    local side = prim("cube", { 0, 0.01, 0 }, { 5.6, 0.02, cz + 6 }, { 1, 1, 1 }, "images/path.png", nil, { smooth = 0.3 })
    A.tiling(side, 5.6, cz + 6)
    -- caminhos das bases ate a calcada
    for i = 1, 8 do
        local b = Lt.bases[i]
        local p = Lt.basePoint(i, 0, 6.6, 0.012)
        local o = prim("cube", p, { 4.8, 0.024, 3.8 }, { 1, 1, 1 }, "images/path.png", { 0, b.yaw, 0 }, { smooth = 0.3 })
        A.tiling(o, 4.8, 3.8)
    end
end

local function buildCarpet()
    local C = Lt.CARPET
    local len = C.z1 - C.z0
    local c = prim("cube", { 0, 0.03, (C.z0 + C.z1) / 2 }, { C.halfW * 2, 0.06, len }, { 1, 1, 1 }, "images/carpet.png", nil, { smooth = 0.2 })
    A.tiling(c, 1, len / 6)
    W.carpet = c
    -- bordas douradas
    for _, sx in ipairs({ -1, 1 }) do
        prim("cube", { sx * (C.halfW + 0.06), 0.07, (C.z0 + C.z1) / 2 }, { 0.12, 0.12, len }, { 1.0, 0.8, 0.25 }, nil, nil, { metal = 0.8, smooth = 0.8 })
    end
    -- setas que andam na esteira (dao a sensacao de esteira rolante)
    W.arrows = {}
    for i = 0, 16 do
        local a = prim("quad", { 0, 0.065, C.z0 + i * 4 }, { 0.9, 0.9, 1 }, { 1, 0.85, 0.4 }, "images/arrow.png", { 90, 0, 0 }, { noShadow = true, emit = { 0.4, 0.3, 0.1 } })
        W.arrows[#W.arrows + 1] = { o = a, z = C.z0 + i * 4 }
    end
    -- arcos de entrada e saida
    for _, z in ipairs({ C.z0, C.z1 }) do
        for _, sx in ipairs({ -1, 1 }) do
            prim("cube", { sx * 2.3, 1.8, z }, { 0.5, 3.6, 0.5 }, { 0.95, 0.95, 0.98 }, "images/wall_base.png")
            boxObstacle({ sx * 2.3 - 0.25, 0, z - 0.25 }, { sx * 2.3 + 0.25, 0, z + 0.25 })
        end
        prim("cube", { 0, 3.75, z }, { 5.1, 0.5, 0.6 }, { 0.95, 0.25, 0.25 }, nil, nil, { smooth = 0.6 })
        local s = prim("quad", { 0, 3.75, z + (z < 0 and -0.31 or 0.31) }, { 4.6, 0.46, 1 }, { 1, 1, 1 }, nil, { 0, z < 0 and 0 or 180, 0 })
        A.uiQuad(s)
        A.texture(s, "images/logo_strip.png")
        local s2 = prim("quad", { 0, 3.75, z + (z < 0 and 0.31 or -0.31) }, { 4.6, 0.46, 1 }, { 1, 1, 1 }, nil, { 0, z < 0 and 180 or 0, 0 })
        A.uiQuad(s2)
        A.texture(s2, "images/logo_strip.png")
        -- tunel escuro de onde saem/entram os brainrots
        prim("cube", { 0, 1.5, z + (z < 0 and -1.2 or 1.2) }, { 4.1, 3.0, 2.0 }, { 0.12, 0.1, 0.16 }, nil, nil, { smooth = 0.2 })
    end
    -- postes de luz ao longo da esteira
    for z = C.z0 + 6, C.z1 - 2, 8 do
        for _, sx in ipairs({ -1, 1 }) do
            local x = sx * 2.65
            prim("cylinder", { x, 1.4, z }, { 0.1, 1.4, 0.1 }, { 0.15, 0.15, 0.18 }, nil, nil, { metal = 0.7, smooth = 0.6 })
            prim("cube", { x - sx * 0.25, 2.75, z }, { 0.6, 0.06, 0.06 }, { 0.15, 0.15, 0.18 })
            local l = prim("sphere", { x - sx * 0.5, 2.62, z }, { 0.28, 0.28, 0.28 }, { 1.0, 0.92, 0.7 }, nil, nil, { emit = { 0.4, 0.35, 0.2 }, noShadow = true })
            W.lamps[#W.lamps + 1] = l
            W.obstacles[#W.obstacles + 1] = { x = x, z = z, r = 0.15 }
        end
    end
end

---------------------------------------------------------------------------
-- Bases
---------------------------------------------------------------------------
local function buildBase(i)
    local b = Lt.bases[i]
    local col = W.BASE_COLORS[i]
    local D, Wd, H = Lt.BASE_DEPTH, Lt.BASE_WIDTH, Lt.WALL_H
    local root = A.empty("base" .. i, W.root)
    local wallC = { 0.93, 0.93, 0.95 }
    local trim = col
    local base = { index = i, root = root, color = col, pads = {}, podiums = {} }

    -- piso
    local fl = baseBox(i, 0, 0, 0.1, Wd, 0.2, D, V.lerp(col, { 1, 1, 1 }, 0.55), "images/floor_base.png", false, root, { smooth = 0.5 })
    A.tiling(fl, Wd / 1.1, D / 1.1)
    -- paredes: fundo e lados
    local wt = "images/wall_base.png"
    local wb = baseBox(i, 0, -D / 2 - 0.15, H / 2, Wd + 0.6, H, 0.3, wallC, wt, true, root)
    A.tiling(wb, (Wd + 0.6) / 1.5, H / 1.5)
    for _, su in ipairs({ -1, 1 }) do
        local ws = baseBox(i, su * (Wd / 2 + 0.15), 0, H / 2, 0.3, H, D, wallC, wt, true, root)
        A.tiling(ws, D / 1.5, H / 1.5)
        -- faixa colorida no topo
        baseBox(i, su * (Wd / 2 + 0.15), 0, H + 0.1, 0.36, 0.2, D + 0.3, trim, nil, false, root, { smooth = 0.6 })
        -- frente: tocos de parede dos lados da porta
        local stub = (Wd / 2 - Lt.DOOR_HALF)
        local wf = baseBox(i, su * (Lt.DOOR_HALF + stub / 2), D / 2 + 0.15, H / 2, stub, H, 0.3, wallC, wt, true, root)
        A.tiling(wf, stub / 1.5, H / 1.5)
        -- pilar da porta (emissor dos lasers)
        baseBox(i, su * Lt.DOOR_HALF, D / 2 + 0.15, H / 2, 0.36, H + 0.2, 0.4, { 0.2, 0.2, 0.24 }, nil, false, root, { metal = 0.6, smooth = 0.7 })
    end
    baseBox(i, 0, -D / 2 - 0.15, H + 0.1, Wd + 0.9, 0.2, 0.36, trim, nil, false, root, { smooth = 0.6 })
    -- viga sobre a porta com a placa do dono
    baseBox(i, 0, D / 2 + 0.15, H - 0.15, Lt.DOOR_HALF * 2 + 0.4, 0.5, 0.4, trim, nil, false, root, { smooth = 0.6 })
    local signPos = Lt.basePoint(i, 0, D / 2 + 0.37, H - 0.15)
    base.sign = Tx.new({ parent = root, pos = signPos, h = 0.3, color = { 1, 1, 1 } })
    A.rot(base.sign.root, 0, b.yaw + 180, 0)
    base.signInner = Tx.new({ parent = root, pos = Lt.basePoint(i, 0, D / 2 - 0.07, H - 0.15), h = 0.26, color = { 1, 1, 1 } })
    A.rot(base.signInner.root, 0, b.yaw, 0)

    -- lasers da porta (so aparecem com a base trancada)
    base.lasers = A.empty("lasers", root)
    for k = 0, 5 do
        local y = 0.25 + k * 0.42
        baseBox(i, 0, D / 2 + 0.15, y, Lt.DOOR_HALF * 2, 0.045, 0.045, { 1, 0.1, 0.1 }, nil, false, base.lasers, { emit = { 3, 0.2, 0.2 }, noShadow = true })
    end
    A.setVisible(base.lasers, false)
    base.laserBox = (function()
        local p1 = Lt.basePoint(i, -Lt.DOOR_HALF, D / 2 - 0.1)
        local p2 = Lt.basePoint(i, Lt.DOOR_HALF, D / 2 + 0.4)
        return { math.min(p1[1], p2[1]), math.max(p1[1], p2[1]), math.min(p1[3], p2[3]), math.max(p1[3], p2[3]) }
    end)()

    -- vagas: pedestal + placa de coletar dinheiro
    for s = 1, Lt.SLOTS do
        local q = Lt.slotUV[s]
        local pod = baseBox(i, q.u, q.v, 0.25, 1.3, 0.3, 1.4, { 0.96, 0.96, 0.98 }, nil, false, root, { smooth = 0.6 })
        baseBox(i, q.u, q.v, 0.405, 1.36, 0.03, 1.46, trim, nil, false, root, { smooth = 0.7 })
        base.podiums[s] = pod
        local pp = Lt.padPos(i, s)
        local pad = prim("cube", { pp[1], 0.23, pp[3] }, { 0.9, 0.06, 0.9 }, { 0.25, 0.85, 0.35 }, "images/pad.png", { 0, b.yaw, 0 }, { smooth = 0.6 }, root)
        local txt = Tx.new({ parent = root, pos = { pp[1], 0.75, pp[3] }, h = 0.16, color = { 0.4, 1, 0.45 } })
        base.pads[s] = { o = pad, text = txt, pos = pp }
    end

    -- botao de trancar (no fundo)
    local lp = Lt.lockPos(i)
    prim("cylinder", { lp[1], 0.32, lp[3] }, { 1.1, 0.12, 1.1 }, { 0.25, 0.25, 0.3 }, nil, nil, { metal = 0.5, smooth = 0.6 }, root)
    base.lockBtn = prim("cylinder", { lp[1], 0.42, lp[3] }, { 0.85, 0.08, 0.85 }, { 0.95, 0.2, 0.2 }, nil, nil, { emit = { 0.5, 0.05, 0.05 }, smooth = 0.8 }, root)
    base.lockText = Tx.new({ parent = root, pos = { lp[1], 1.25, lp[3] }, h = 0.22, color = { 1, 0.4, 0.4 } })
    local lockSign = prim("quad", Lt.basePoint(i, 0, -D / 2 + 0.02, 1.9), { 1.6, 0.4, 1 }, { 1, 1, 1 }, nil, { 0, b.yaw + 180, 0 }, nil, root)
    A.uiQuad(lockSign)
    L10.bindTex(lockSign, "lbl_lock")
    base.lockPos = lp
    W.bases[i] = base
end

---------------------------------------------------------------------------
-- Loja e altar de renascer
---------------------------------------------------------------------------
local function buildShop()
    local S = Lt.SHOP
    local root = A.empty("shop", W.root)
    W.shop = { root = root, stands = {} }
    prim("cube", { S[1], 0.5, S[3] - 1.0 }, { 7.4, 1.0, 1.2 }, { 0.55, 0.36, 0.2 }, "images/wood.png", nil, { smooth = 0.3 }, root)
    prim("cube", { S[1], 1.03, S[3] - 1.0 }, { 7.6, 0.06, 1.35 }, { 0.98, 0.98, 1.0 }, nil, nil, { smooth = 0.8 }, root)
    boxObstacle({ S[1] - 3.7, 0, S[3] - 1.6 }, { S[1] + 3.7, 0, S[3] - 0.4 })
    for _, sx in ipairs({ -1, 1 }) do
        prim("cube", { S[1] + sx * 3.6, 1.7, S[3] - 1.5 }, { 0.2, 3.4, 0.2 }, { 0.55, 0.36, 0.2 }, "images/wood.png", nil, nil, root)
    end
    -- toldo listrado
    for k = 0, 7 do
        prim("cube", { S[1] - 3.5 + k * 1.0, 3.3, S[3] - 0.9 }, { 1.0, 0.1, 1.9 }, k % 2 == 0 and { 0.95, 0.25, 0.25 } or { 1, 1, 1 }, nil, { -12, 0, 0 }, { smooth = 0.4 }, root)
    end
    local sign = prim("quad", { S[1], 2.7, S[3] - 0.5 }, { 3.4, 0.85, 1 }, { 1, 1, 1 }, nil, { 0, 180, 0 }, nil, root)
    A.uiQuad(sign)
    L10.bindTex(sign, "sign_shop")
    -- pontos dos itens no balcao
    for k = 1, 5 do
        W.shop.stands[k] = { S[1] - 3.0 + (k - 1) * 1.5, 1.1, S[3] - 1.0 }
    end
end

local function buildRebirth()
    local R = Lt.REBIRTH
    local root = A.empty("rebirth", W.root)
    prim("cylinder", { R[1], 0.25, R[3] }, { 3.2, 0.25, 3.2 }, { 0.95, 0.95, 1.0 }, "images/path.png", nil, { smooth = 0.6 }, root)
    prim("cylinder", { R[1], 0.55, R[3] }, { 2.2, 0.06, 2.2 }, { 0.7, 0.4, 1.0 }, nil, nil, { emit = { 0.6, 0.25, 1.0 } }, root)
    W.rebirthCrystal = prim("cube", { R[1], 2.0, R[3] }, { 0.8, 0.8, 0.8 }, { 0.8, 0.5, 1.0 }, nil, { 45, 0, 45 }, { emit = { 1.4, 0.7, 2.2 }, smooth = 0.95 }, root)
    W.obstacles[#W.obstacles + 1] = { x = R[1], z = R[3], r = 1.4 }
    local sign = prim("quad", { R[1], 3.4, R[3] - 0.6 }, { 3.0, 0.75, 1 }, { 1, 1, 1 }, nil, { 0, 0, 0 }, nil, root)
    A.uiQuad(sign)
    L10.bindTex(sign, "sign_rebirth")
    W.rebirthText = Tx.new({ parent = root, pos = { R[1], 2.95, R[3] - 0.62 }, h = 0.2, color = { 0.9, 0.7, 1 } })
end

---------------------------------------------------------------------------
-- Decoracao
---------------------------------------------------------------------------
local function tree(x, z, s)
    prim("cube", { x, 1.0 * s, z }, { 0.45 * s, 2.0 * s, 0.45 * s }, { 0.45, 0.3, 0.17 }, "images/wood.png")
    prim("cube", { x, 2.4 * s, z }, { 2.0 * s, 1.4 * s, 2.0 * s }, { 0.25, 0.65, 0.25 }, nil, nil, { smooth = 0.1 })
    prim("cube", { x, 3.3 * s, z }, { 1.3 * s, 0.9 * s, 1.3 * s }, { 0.3, 0.72, 0.3 }, nil, nil, { smooth = 0.1 })
    W.obstacles[#W.obstacles + 1] = { x = x, z = z, r = 0.35 * s }
end

local function buildDecor()
    local B = Lt.BOUNDS
    -- arvores entre as bases e nos cantos
    for _, sx in ipairs({ -1, 1 }) do
        for _, z in ipairs({ -28, -14, 0, 14, 28 }) do tree(sx * 17.5, z, 1.0 + (z % 3) * 0.08) end
        for _, z in ipairs({ -36, 36 }) do tree(sx * 9, z, 1.2) end
        tree(sx * 15, -38, 1.1)
        tree(sx * 15, 38, 1.1)
    end
    -- cerca nos limites
    for _, sx in ipairs({ -1, 1 }) do
        local x = sx * (B[2] + 0.3)
        prim("cube", { x, 0.5, 0 }, { 0.1, 0.12, B[4] * 2 }, { 1, 1, 1 })
        prim("cube", { x, 0.9, 0 }, { 0.1, 0.12, B[4] * 2 }, { 1, 1, 1 })
        for z = B[3], B[4], 3 do prim("cube", { x, 0.55, z }, { 0.14, 1.1, 0.14 }, { 1, 1, 1 }) end
    end
    for _, sz in ipairs({ -1, 1 }) do
        local z = sz * (B[4] + 0.3)
        prim("cube", { 0, 0.5, z }, { B[2] * 2, 0.12, 0.1 }, { 1, 1, 1 })
        prim("cube", { 0, 0.9, z }, { B[2] * 2, 0.12, 0.1 }, { 1, 1, 1 })
    end
    -- predios ao fundo (cidade blocada)
    local cols = { { 0.62, 0.7, 0.85 }, { 0.75, 0.65, 0.6 }, { 0.6, 0.75, 0.68 }, { 0.82, 0.8, 0.72 } }
    for k = 0, 23 do
        local a = k / 24 * math.pi * 2
        local r = 75 + (k % 4) * 8
        local h = 10 + (k * 7 % 5) * 6
        local o = prim("cube", { math.sin(a) * r, h / 2, math.cos(a) * r }, { 9 + k % 3 * 3, h, 9 }, cols[k % 4 + 1], "images/building.png", { 0, a * V.DEG, 0 }, { noShadow = true })
        A.tiling(o, (9 + k % 3 * 3) / 4, h / 4)
    end
    -- flores
    local fc = { { 1, 0.3, 0.4 }, { 1, 0.85, 0.2 }, { 0.6, 0.4, 1 }, { 1, 1, 1 } }
    for k = 0, 39 do
        local x = (k % 2 == 0 and -1 or 1) * (6.8 + (k * 37 % 9) * 1.1)
        local z = -32 + (k * 53 % 64)
        if not Lt.baseAt({ x, 0, z }) then
            prim("cube", { x, 0.08, z }, { 0.18, 0.16, 0.18 }, fc[k % 4 + 1], nil, { 0, k * 23, 0 }, { noShadow = true })
        end
    end
end

---------------------------------------------------------------------------
function W.build(parent)
    W.root = A.empty("map", parent)
    W.obstacles = {}
    buildSky()
    buildGround()
    buildCarpet()
    for i = 1, 8 do buildBase(i) end
    buildShop()
    buildRebirth()
    buildDecor()
    W.setSky("day")
end

-- atualizacao visual (setas da esteira, nuvens, cristal)
function W.update(dt, t)
    local C = Lt.CARPET
    for _, a in ipairs(W.arrows) do
        a.z = a.z + dt * 1.25
        if a.z > C.z1 - 0.5 then a.z = a.z - (C.z1 - C.z0 - 1) end
        A.posXYZ(a.o, 0, 0.065, a.z)
    end
    for _, c in ipairs(W.clouds) do
        c.a = c.a + c.spd * dt
        A.posXYZ(c.o, math.sin(c.a) * c.r, c.y, math.cos(c.a) * c.r)
    end
    if W.rebirthCrystal then
        A.rot(W.rebirthCrystal, 45, t * 40, 45)
        A.posXYZ(W.rebirthCrystal, Lt.REBIRTH[1], 2.0 + math.sin(t * 1.5) * 0.12, Lt.REBIRTH[3])
    end
end

-- liga/desliga os lasers da base
function W.setLasers(i, on)
    local b = W.bases[i]
    if b.lasersOn == on then return end
    b.lasersOn = on
    A.setVisible(b.lasers, on)
end

return W
