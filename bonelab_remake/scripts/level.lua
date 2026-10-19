-- level.lua — o "Laboratorio": arena 24x24 m estilo BONELAB.
-- Constroi a geometria, guarda as caixas estaticas (para raycast e colisao do jogador)
-- e os pontos de interesse (spawn do jogador, mesa de armas, portais dos bots).

local V = require("vec")
local A = require("api")
local L10 = require("i18n")

local L = {}

L.statics = {}       -- { mn = {}, mx = {}, mat = "metal"|"concrete"|"wood" }
L.portals = {}       -- pontos de spawn dos bots
L.lights = {}        -- barras de luz (para piscar)
L.playerSpawn = { 0, 0, -8.5 }
L.tableTop = { 0, 0.94, -7.55 }   -- centro do tampo da mesa de armas
L.size = 12          -- meia largura da arena

local W -- raiz do mundo

local function box(center, size, opt)
    opt = opt or {}
    local o = A.prim("cube", {
        parent = W, pos = center, scale = size, color = opt.color or { 1, 1, 1 },
        tex = opt.tex, mat = opt.mat, collider = opt.collider ~= false and "box" or nil,
    })
    if opt.static ~= false then
        local h = V.scale(size, 0.5)
        L.statics[#L.statics + 1] = { mn = V.sub(center, h), mx = V.add(center, h), mat = opt.surface or "metal" }
    end
    return o
end

local function deco(kind, center, size, color, mat, tex, rot)
    return A.prim(kind, { parent = W, pos = center, scale = size, color = color, mat = mat, tex = tex, rot = rot })
end

local function obstacleBox(cx, cz, hx, hz)
    return { box = { cx - hx, cx + hx, cz - hz, cz + hz } }
end

function L.build(world, rig)
    W = world
    local S = L.size
    local H = 6.5

    -- piso (topo em y = 0)
    box({ 0, -0.1, 0 }, { S * 2, 0.2, S * 2 }, { tex = "images/floor.png", mat = { metal = 0.1, smooth = 0.55 }, surface = "concrete" })

    -- paredes
    local wallMat = { metal = 0.05, smooth = 0.35 }
    box({ 0, H / 2, S + 0.2 }, { S * 2 + 0.8, H, 0.4 }, { tex = "images/wall.png", mat = wallMat })
    box({ 0, H / 2, -S - 0.2 }, { S * 2 + 0.8, H, 0.4 }, { tex = "images/wall.png", mat = wallMat })
    box({ S + 0.2, H / 2, 0 }, { 0.4, H, S * 2 + 0.8 }, { tex = "images/wall_side.png", mat = wallMat })
    box({ -S - 0.2, H / 2, 0 }, { 0.4, H, S * 2 + 0.8 }, { tex = "images/wall_side.png", mat = wallMat })

    -- teto
    box({ 0, H + 0.15, 0 }, { S * 2 + 0.8, 0.3, S * 2 + 0.8 }, { tex = "images/ceiling.png", mat = { smooth = 0.2 }, collider = false })

    -- barras de luz no teto
    for i = -2, 2 do
        local o = deco("cube", { i * 4.4, H - 0.03, 0 }, { 0.35, 0.06, S * 1.7 }, { 1, 0.98, 0.92 }, { emit = { 2.2, 2.1, 1.9 }, noShadow = true })
        L.lights[#L.lights + 1] = o
    end

    -- faixa laranja luminosa nas paredes (estilo Bonelab)
    local acc = { 1, 0.45, 0.08 }
    local accMat = { emit = { 1.4, 0.5, 0.05 }, noShadow = true }
    deco("cube", { 0, 1.1, S - 0.02 }, { S * 2, 0.08, 0.06 }, acc, accMat)
    deco("cube", { 0, 1.1, -S + 0.02 }, { S * 2, 0.08, 0.06 }, acc, accMat)
    deco("cube", { S - 0.02, 1.1, 0 }, { 0.06, 0.08, S * 2 }, acc, accMat)
    deco("cube", { -S + 0.02, 1.1, 0 }, { 0.06, 0.08, S * 2 }, acc, accMat)
    -- rodape escuro
    deco("cube", { 0, 0.08, S - 0.03 }, { S * 2, 0.16, 0.08 }, { 0.12, 0.12, 0.14 }, { metal = 0.6, smooth = 0.6 })
    deco("cube", { 0, 0.08, -S + 0.03 }, { S * 2, 0.16, 0.08 }, { 0.12, 0.12, 0.14 }, { metal = 0.6, smooth = 0.6 })
    deco("cube", { S - 0.03, 0.08, 0 }, { 0.08, 0.16, S * 2 }, { 0.12, 0.12, 0.14 }, { metal = 0.6, smooth = 0.6 })
    deco("cube", { -S + 0.03, 0.08, 0 }, { 0.08, 0.16, S * 2 }, { 0.12, 0.12, 0.14 }, { metal = 0.6, smooth = 0.6 })

    -- pilares
    local pillars = { { -5, -2 }, { 5, -2 }, { -5, 5 }, { 5, 5 } }
    for _, p in ipairs(pillars) do
        box({ p[1], H / 2, p[2] }, { 1.2, H, 1.2 }, { tex = "images/concrete.png", mat = { smooth = 0.2 }, surface = "concrete" })
        -- quinas metalicas laranjas
        for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
            deco("cube", { p[1] + c[1] * 0.6, 1.25, p[2] + c[2] * 0.6 }, { 0.09, 2.5, 0.09 }, acc, { metal = 0.7, smooth = 0.6, emit = { 0.3, 0.1, 0 } })
        end
        deco("cube", { p[1], 2.6, p[2] }, { 1.26, 0.06, 1.26 }, { 0.95, 0.95, 1.0 }, { emit = { 1.6, 1.6, 1.8 }, noShadow = true })
        rig.obstacles[#rig.obstacles + 1] = obstacleBox(p[1], p[2], 0.6, 0.6)
    end

    -- coberturas baixas
    local covers = { { 0, 4, 2.8, 0.4 }, { -8, 1.5, 0.4, 2.4 }, { 8, 1.5, 0.4, 2.4 }, { -2.8, -3.5, 1.6, 0.4 }, { 2.8, -3.5, 1.6, 0.4 } }
    for _, c in ipairs(covers) do
        box({ c[1], 0.55, c[2] }, { c[3], 1.1, c[4] }, { tex = "images/cover.png", mat = { metal = 0.4, smooth = 0.5 } })
        deco("cube", { c[1], 1.12, c[2] }, { c[3] + 0.04, 0.04, c[4] + 0.04 }, acc, { emit = { 0.9, 0.3, 0.03 }, noShadow = true })
        rig.obstacles[#rig.obstacles + 1] = obstacleBox(c[1], c[2], c[3] / 2, c[4] / 2)
    end

    -- plataforma de spawn do jogador
    local ps = L.playerSpawn
    deco("cylinder", { ps[1], 0.01, ps[3] }, { 2.2, 0.01, 2.2 }, { 0.16, 0.17, 0.2 }, { metal = 0.7, smooth = 0.7 })
    deco("cylinder", { ps[1], 0.012, ps[3] }, { 2.3, 0.008, 2.3 }, acc, { emit = { 1.2, 0.4, 0.03 } })
    deco("cylinder", { ps[1], 0.016, ps[3] }, { 2.1, 0.008, 2.1 }, { 0.16, 0.17, 0.2 }, { metal = 0.7, smooth = 0.7 })

    -- mesa de armas
    local t = L.tableTop
    local tableTop = box({ t[1], t[2] - 0.03, t[3] }, { 1.7, 0.06, 0.62 }, { mat = { metal = 0.6, smooth = 0.6 } })
    L10.bindTex(tableTop, "table")
    for _, lx in ipairs({ -0.78, 0.78 }) do
        for _, lz in ipairs({ -0.25, 0.25 }) do
            deco("cube", { t[1] + lx, (t[2] - 0.06) / 2, t[3] + lz }, { 0.05, t[2] - 0.06, 0.05 }, { 0.15, 0.15, 0.17 }, { metal = 0.8, smooth = 0.6 })
        end
    end
    deco("cube", { t[1], t[2] - 0.065, t[3] - 0.3 }, { 1.7, 0.03, 0.02 }, acc, { emit = { 1.2, 0.4, 0.03 } })
    rig.obstacles[#rig.obstacles + 1] = obstacleBox(t[1], t[3], 0.85, 0.31)

    -- placas/posters
    deco("quad", { -S + 0.03, 3.4, 0 }, { 6, 2.4, 1 }, { 1, 1, 1 }, { emit = { 0.06, 0.06, 0.06 } }, "images/poster_logo.png", { 0, -90, 0 })
    L10.bindTex(deco("quad", { S - 0.03, 3.4, 2 }, { 4, 2, 1 }, { 1, 1, 1 }, { emit = { 0.04, 0.04, 0.04 } }, nil, { 0, 90, 0 }), "poster_lab")
    L10.bindTex(deco("quad", { 0, 4.9, S - 0.03 }, { 3.6, 0.9, 1 }, { 1, 1, 1 }, { emit = { 0.05, 0.05, 0.05 } }, nil, { 0, 0, 0 }), "sign_arena")

    -- faixas de perigo no chao em volta dos portais
    local portalPts = { { -9, 9 }, { 9, 9 }, { 0, 10 }, { -10, -1 }, { 10, -1 } }
    for _, p in ipairs(portalPts) do
        local pos = { p[1], 0, p[2] }
        L.portals[#L.portals + 1] = pos
        deco("cylinder", { p[1], 0.006, p[2] }, { 1.9, 0.006, 1.9 }, { 1, 1, 1 }, nil, "images/hazard_ring.png")
        local ring = deco("cylinder", { p[1], 0.012, p[2] }, { 1.3, 0.006, 1.3 }, { 0.15, 0.7, 1.0 }, { emit = { 0.2, 1.2, 2.0 }, noShadow = true })
        deco("cylinder", { p[1], 0.016, p[2] }, { 1.1, 0.006, 1.1 }, { 0.06, 0.07, 0.09 }, { metal = 0.8, smooth = 0.8 })
        L.lights[#L.lights + 1] = ring
    end

    rig.bounds = { -S + 0.1, S - 0.1, -S + 0.1, S - 0.1 }
    A.log("Nivel montado: " .. #L.statics .. " caixas estaticas")
end

-- Raycast contra a geometria estatica. Retorna t, normal, material
function L.raycast(o, d, maxDist)
    local best, bn, bm = maxDist or 1e9, nil, nil
    for _, s in ipairs(L.statics) do
        local t, n = V.rayAABB(o, d, s.mn, s.mx)
        if t and t < best and t > 0.0001 then best, bn, bm = t, n, s.mat end
    end
    if bn then return best, bn, bm end
    return nil
end

-- Linha de visao livre entre dois pontos?
function L.lineClear(a, b)
    local d = V.sub(b, a)
    local len = V.len(d)
    if len < 1e-4 then return true end
    local t = L.raycast(a, V.scale(d, 1 / len), len)
    return t == nil
end

return L
