-- hands.lua — MAO FAKE ARTICULADA.
-- Substitui o esqueleto padrao da plataforma por uma mao de "manequim/robo":
-- falanges em capsulas, juntas em esferas, palma + placa,
-- punho com bracelete e antebraco. Cada frame e montada a partir dos 21 landmarks
-- (rastreados ou de uma pose quando a mao segura uma arma).

local V = require("vec")
local A = require("api")

local H = {}

local BONES = {
    -- {a, b, raio}
    { 0, 1, 0.0135 }, { 1, 2, 0.0110 }, { 2, 3, 0.0098 }, { 3, 4, 0.0090 },
    { 5, 6, 0.0098 }, { 6, 7, 0.0090 }, { 7, 8, 0.0082 },
    { 9, 10, 0.0100 }, { 10, 11, 0.0092 }, { 11, 12, 0.0084 },
    { 13, 14, 0.0095 }, { 14, 15, 0.0087 }, { 15, 16, 0.0079 },
    { 17, 18, 0.0085 }, { 18, 19, 0.0078 }, { 19, 20, 0.0071 },
}
local JOINT_R = {
    [0] = 0.020,
    0.014, 0.012, 0.0105, 0.0095,
    0.0118, 0.0102, 0.0094, 0.0088,
    0.0120, 0.0104, 0.0096, 0.0090,
    0.0114, 0.0098, 0.0090, 0.0084,
    0.0104, 0.0090, 0.0082, 0.0076,
}

-- estilo SUPERHOT: mao de manequim branca, juntas cinza claro
H.SKIN = { 0.95, 0.95, 0.96 }
H.JOINT = { 0.62, 0.63, 0.66 }
H.PALM = { 0.9, 0.9, 0.92 }
H.ACCENT = { 0.98, 0.98, 1.0 }
H.SLEEVE = { 0.82, 0.83, 0.86 }

H.list = {}

local function makeHand(side, parent)
    local h = { side = side, visible = true, parts = {} }
    h.root = A.empty("Hand_" .. side, parent)
    h.joints, h.bones = {}, {}
    for i = 0, 20 do
        local r = JOINT_R[i]
        local o = A.prim("sphere", {
            parent = h.root, scale = { r * 2, r * 2, r * 2 }, color = H.JOINT,
            mat = { metal = 0.2, smooth = 0.7, noShadow = true },
        })
        h.joints[i] = o
    end
    -- pontas dos dedos com colisor para empurrar objetos
    for _, i in ipairs({ 4, 8, 12, 16, 20 }) do A.sphereCollider(h.joints[i], 0.5) end
    for bi, b in ipairs(BONES) do
        local o = A.prim("capsule", {
            parent = h.root, color = H.SKIN, mat = { metal = 0.05, smooth = 0.55, noShadow = true },
        })
        h.bones[bi] = o
    end
    h.palm = A.prim("cube", { parent = h.root, color = H.PALM, mat = { metal = 0.2, smooth = 0.4 } })
    A.boxCollider(h.palm)
    h.plate = A.prim("cube", {
        parent = h.root, color = H.ACCENT,
        mat = { metal = 0.1, smooth = 0.8 },
    })
    h.knuckle = A.prim("cube", { parent = h.root, color = H.JOINT, mat = { metal = 0.9, smooth = 0.8 } })
    h.cuff = A.prim("cylinder", {
        parent = h.root, color = H.ACCENT, mat = { metal = 0.1, smooth = 0.8 },
    })
    h.forearm = A.prim("capsule", { parent = h.root, color = H.SLEEVE, mat = { metal = 0.1, smooth = 0.3 } })
    h.stripe = A.prim("cube", {
        parent = h.root, color = { 0.7, 0.72, 0.76 }, mat = { smooth = 0.6 },
    })
    h.pts = {}
    for i = 0, 20 do h.pts[i] = { 0, 0, 0 } end
    h.basis = V.identity()
    h.wrist = { 0, 0, 0 }
    h.dorsal = { 0, 1, 0 }
    return h
end

function H.init(parent)
    H.list.left = makeHand("left", parent)
    H.list.right = makeHand("right", parent)
    -- esconde o esqueleto padrao da plataforma (o tracking continua)
    pcall(function() EMRAPI.Hands:SetVisible("both", false) end)
end

local lastLen = {}

local function placeSegment(o, a, b, r)
    local d = V.sub(b, a)
    local len = V.len(d)
    if len < 1e-5 then len = 1e-5 end
    local m = V.mid(a, b)
    A.posXYZ(o, m[1], m[2], m[3])
    local ex, ey, ez = V.eulerAlongY(d)
    A.rot(o, ex, ey, ez)
    -- capsula Unity: altura 2, diametro 1 (ao longo de Y). Soma o raio nas pontas.
    -- so reescala se o comprimento mudou mais de 1 mm
    local l = lastLen[o]
    if not l or math.abs(l - len) > 0.001 then
        lastLen[o] = len
        A.scale(o, r * 2, (len + r * 2) * 0.5, r * 2)
    end
end

function H.setVisible(side, vis)
    local h = H.list[side]
    if not h or h.visible == vis then return end
    h.visible = vis
    A.setVisible(h.root, vis, 1, 1, 1)
end

-- Desenha a mao com os 21 pontos (coordenadas locais do mundo).
function H.draw(side, pts)
    local h = H.list[side]
    if not h then return end
    for i = 0, 20 do
        local p = pts[i]
        local q = h.pts[i]
        q[1], q[2], q[3] = p[1], p[2], p[3]
        A.posXYZ(h.joints[i], p[1], p[2], p[3])
    end
    for bi, b in ipairs(BONES) do
        placeSegment(h.bones[bi], pts[b[1]], pts[b[2]], b[3])
    end

    -- base da palma: f = punho->medio, u = mindinho->indicador, r = normal
    local wrist = pts[0]
    local f = V.sub(pts[9], wrist)
    local length = V.len(f)
    local B = V.basis(f, V.sub(pts[5], pts[17]))
    h.basis = B
    local dorsal = side == "right" and B.r or V.scale(B.r, -1)
    h.dorsal = dorsal
    h.wrist = V.copy(wrist)
    local width = V.dist(pts[5], pts[17]) + 0.022
    local center = V.avg({ wrist, pts[5], pts[9], pts[13], pts[17] })
    center = V.madd(center, B.f, -0.004)

    A.pos(h.palm, center)
    A.rotBasis(h.palm, B)
    A.scale(h.palm, 0.026, width, length * 0.92)

    local pc = V.madd(center, dorsal, 0.016)
    A.pos(h.plate, V.madd(pc, B.f, -0.006))
    A.rotBasis(h.plate, B)
    A.scale(h.plate, 0.007, width * 0.78, length * 0.62)

    -- barra dos nos dos dedos
    local kn = V.madd(V.avg({ pts[5], pts[9], pts[13], pts[17] }), dorsal, 0.008)
    A.pos(h.knuckle, kn)
    A.rotBasis(h.knuckle, B)
    A.scale(h.knuckle, 0.012, width * 0.95, 0.016)

    -- antebraco segue a direcao punho->palma, um pouco "para baixo" da mao
    local armDir = V.norm(V.madd(B.f, dorsal, 0.08))
    local cuffC = V.madd(wrist, armDir, -0.018)
    A.pos(h.cuff, cuffC)
    local ex, ey, ez = V.eulerAlongY(armDir)
    A.rot(h.cuff, ex, ey, ez)
    A.scale(h.cuff, 0.066, 0.016, 0.066)

    local elbow = V.madd(wrist, armDir, -0.26)
    placeSegment(h.forearm, V.madd(wrist, armDir, -0.03), elbow, 0.03)

    -- faixa luminosa no antebraco (lado de cima)
    local sc = V.madd(V.madd(wrist, armDir, -0.12), dorsal, 0.03)
    A.pos(h.stripe, sc)
    A.rotBasis(h.stripe, V.basis(dorsal, armDir))
    A.scale(h.stripe, 0.012, 0.08, 0.004)
end

function H.get(side) return H.list[side] end

function H.reset()
    pcall(function() EMRAPI.Hands:Reset("both") end)
end

return H
