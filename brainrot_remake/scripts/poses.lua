-- poses.lua — poses da mao (21 pontos MediaPipe) no espaco do OBJETO segurado.
-- Definidas para a mao DIREITA; a esquerda e o espelho em X.
-- Eixos do objeto: x = direita, y = cima, z = frente (cano da arma).
--
-- Indices MediaPipe: 0 punho | polegar 1-4 | indicador 5-8 | medio 9-12 | anelar 13-16 | mindinho 17-20

local V = require("vec")

local P = {}

-- centro do cabo da pistola na altura y (o cabo e inclinado ~15 graus)
local function cz(y) return -0.01 + 0.268 * (y + 0.05) end

-- dedo enrolado num cabo vertical na altura y
local function wrapFinger(y, shrink)
    shrink = shrink or 1
    local c = cz(y)
    return {
        { 0.034, y, c + 0.000 },
        { 0.014 * shrink + 0.002, y, c + 0.036 * shrink },
        { -0.012 * shrink, y, c + 0.032 * shrink },
        { -0.024 * shrink, y, c + 0.012 },
    }
end

local function build(t)
    local pts = {}
    for i = 0, 20 do pts[i] = t[i] end
    return pts
end

-- Empunhadura de pistola (indicador no gatilho). Dois estados do indicador.
local function pistolPose(pull)
    local mid = wrapFinger(-0.026)
    local ring = wrapFinger(-0.048, 0.95)
    local pinky = wrapFinger(-0.068, 0.85)
    local tipRest = { -0.004, -0.015, 0.040 }
    local tipPull = { -0.003, -0.017, 0.029 }
    local dipRest = { 0.010, -0.012, 0.051 }
    local dipPull = { 0.011, -0.014, 0.041 }
    return build({
        [0] = { 0.012, -0.066, -0.076 },
        { 0.014, -0.046, -0.052 }, { -0.010, -0.024, -0.040 }, { -0.024, -0.008, -0.014 }, { -0.025, -0.004, 0.010 },
        { 0.034, -0.004, 0.008 }, { 0.026, -0.006, 0.050 }, V.lerp(dipRest, dipPull, pull), V.lerp(tipRest, tipPull, pull),
        mid[1], mid[2], mid[3], mid[4],
        ring[1], ring[2], ring[3], ring[4],
        { 0.030, -0.068, cz(-0.068) - 0.002 }, pinky[2], pinky[3], pinky[4],
    })
end

-- Punho fechado num cabo vertical (taco / cabo de faca). Indicador tambem enrolado.
local function fistPose()
    local idx = wrapFinger(-0.004)
    local mid = wrapFinger(-0.026)
    local ring = wrapFinger(-0.048, 0.95)
    local pinky = wrapFinger(-0.068, 0.85)
    return build({
        [0] = { 0.012, -0.066, -0.076 },
        { 0.014, -0.046, -0.052 }, { -0.010, -0.024, -0.040 }, { -0.022, -0.004, -0.004 }, { -0.016, 0.000, 0.026 },
        idx[1], idx[2], idx[3], idx[4],
        mid[1], mid[2], mid[3], mid[4],
        ring[1], ring[2], ring[3], ring[4],
        { 0.030, -0.068, cz(-0.068) - 0.002 }, pinky[2], pinky[3], pinky[4],
    })
end

-- Mao de apoio segurando um cilindro horizontal (ao longo de Z) por baixo: guarda-mao / bomba.
local function supportPose()
    local function f(z, s)
        s = s or 1
        return {
            { 0.012, -0.036, z },
            { -0.022 * s, -0.030, z },
            { -0.034 * s, -0.004, z },
            { -0.026 * s, 0.018 * s, z },
        }
    end
    local i, m, r, p = f(0.030), f(0.010), f(-0.010, 0.97), f(-0.028, 0.9)
    return build({
        [0] = { 0.036, -0.048, -0.066 },
        { 0.032, -0.040, -0.036 }, { 0.036, -0.020, -0.010 }, { 0.030, 0.000, 0.014 }, { 0.022, 0.012, 0.032 },
        i[1], i[2], i[3], i[4],
        m[1], m[2], m[3], m[4],
        r[1], r[2], r[3], r[4],
        p[1], p[2], p[3], p[4],
    })
end

-- Mao segurando um pente/objeto pequeno (pinca com polegar + dedos)
local function magPose()
    return build({
        [0] = { 0.010, -0.075, -0.040 },
        { 0.020, -0.060, -0.022 }, { 0.022, -0.040, -0.006 }, { 0.018, -0.020, 0.006 }, { 0.014, -0.004, 0.010 },
        { -0.002, -0.050, 0.018 }, { -0.012, -0.024, 0.026 }, { -0.016, -0.006, 0.024 }, { -0.016, 0.006, 0.016 },
        { -0.012, -0.056, 0.006 }, { -0.024, -0.030, 0.012 }, { -0.028, -0.010, 0.012 }, { -0.026, 0.004, 0.006 },
        { -0.020, -0.060, -0.006 }, { -0.030, -0.038, -0.002 }, { -0.032, -0.020, -0.002 }, { -0.030, -0.008, -0.004 },
        { -0.024, -0.064, -0.018 }, { -0.032, -0.046, -0.014 }, { -0.034, -0.032, -0.012 }, { -0.032, -0.022, -0.012 },
    })
end

P.pistol0 = pistolPose(0)
P.pistol1 = pistolPose(1)
P.pistol = P.pistol0     -- pose de referencia (gatilho solto)
P.fist = fistPose()
P.support = supportPose()
P.mag = magPose()

-- Base de referencia de cada pose (mesma funcao usada na mao rastreada)
local function handBasis(lm)
    return V.basis(V.sub(lm[9], lm[0]), V.sub(lm[5], lm[17]))
end
local function palmCenter(lm)
    return V.avg({ lm[0], lm[5], lm[9], lm[13], lm[17] })
end
P.handBasis = handBasis
P.palmCenter = palmCenter

local function mirror(pts)
    local o = {}
    for i = 0, 20 do local p = pts[i]; o[i] = { -p[1], p[2], p[3] } end
    return o
end

-- Cache por lado: pontos, base e centro da palma no espaco do objeto
local cache = {}
function P.get(name, side)
    local key = name .. side
    local c = cache[key]
    if c then return c end
    local pts = P[name]
    if side == "left" then pts = mirror(pts) end
    c = { pts = pts, basis = handBasis(pts), palm = palmCenter(pts) }
    cache[key] = c
    return c
end

-- Pose interpolada do gatilho da pistola
function P.pistolBlend(side, t)
    local a, b = P.get("pistol0", side), P.get("pistol1", side)
    if t <= 0 then return a.pts end
    if t >= 1 then return b.pts end
    local o = {}
    for i = 0, 20 do o[i] = V.lerp(a.pts[i], b.pts[i], t) end
    return o
end

-- Dado: mao rastreada (palma pc, base hb) e a pose (no espaco do objeto),
-- calcula a pose do objeto (posicao, base) para que a pose case com a mao real.
function P.objectFromHand(pc, hb, poseName, side)
    local c = P.get(poseName, side)
    local R = V.mulMM(hb, V.transpose(c.basis))
    local off = V.mulMV(R, c.palm)
    return { pc[1] - off[1], pc[2] - off[2], pc[3] - off[3] }, R
end

-- Pontos da pose transformados para o espaco local do mundo
function P.toWorld(pts, pos, basis, out)
    out = out or {}
    for i = 0, 20 do
        local p = pts[i]
        local w = V.mulMV(basis, p)
        local o = out[i]
        if o then
            o[1], o[2], o[3] = pos[1] + w[1], pos[2] + w[2], pos[3] + w[3]
        else
            out[i] = { pos[1] + w[1], pos[2] + w[2], pos[3] + w[3] }
        end
    end
    return out
end

return P
