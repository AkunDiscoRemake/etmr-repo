-- layout.lua — geometria do mapa (coordenadas locais do mundo do jogo, metros).
--
--            z+ (fim da esteira; altar de RENASCER a esquerda)
--   base4  |  esteira  |  base8
--   base3  |  vermelha |  base7
--   base2  |    (x=0)  |  base6
--   base1  |           |  base5
--            z- (inicio da esteira; LOJA de itens a direita)

local V = require("vec")

local Lt = {}

Lt.BOUNDS = { -19.5, 19.5, -41, 41 }
Lt.CARPET = { halfW = 1.6, z0 = -34, z1 = 34 }
Lt.SHOP = { 6.8, 0, -36.4 }      -- ao lado do inicio da esteira (visivel de longe)
Lt.REBIRTH = { -6.8, 0, 36.6 }   -- ao lado do fim da esteira
Lt.BASE_DEPTH = 10
Lt.BASE_WIDTH = 11
Lt.DOOR_HALF = 2.5
Lt.WALL_H = 3.0
Lt.SLOTS = 10

local ZS = { -21, -7, 7, 21 }
Lt.bases = {}
for i = 1, 8 do
    local left = i <= 4
    local z = ZS[(i - 1) % 4 + 1]
    local c = { left and -11 or 11, 0, z }
    local f = { left and 1 or -1, 0, 0 }       -- frente: da base para a esteira
    local r = { f[3], 0, -f[1] }                -- direita de quem olha para a frente
    Lt.bases[i] = { index = i, center = c, f = f, r = r, yaw = left and 90 or -90 }
end

-- ponto local da base (u = direita, v = frente) -> mundo do jogo
function Lt.basePoint(i, u, v, y)
    local b = Lt.bases[i]
    return { b.center[1] + b.r[1] * u + b.f[1] * v, y or 0, b.center[3] + b.r[3] * u + b.f[3] * v }
end

-- mundo -> (u, v) da base
function Lt.toBase(i, p)
    local b = Lt.bases[i]
    local d = { p[1] - b.center[1], 0, p[3] - b.center[3] }
    return d[1] * b.r[1] + d[3] * b.r[3], d[1] * b.f[1] + d[3] * b.f[3]
end

-- vagas: 5 de cada lado, olhando para o corredor do meio
Lt.slotUV = {}
for k = 0, 4 do
    Lt.slotUV[#Lt.slotUV + 1] = { u = -4.1, v = -3.5 + k * 1.75, padU = -2.85, face = 90 }
end
for k = 0, 4 do
    Lt.slotUV[#Lt.slotUV + 1] = { u = 4.1, v = -3.5 + k * 1.75, padU = 2.85, face = -90 }
end

function Lt.slotPos(i, s)
    local q = Lt.slotUV[s]
    return Lt.basePoint(i, q.u, q.v, 0.3)
end
function Lt.padPos(i, s)
    local q = Lt.slotUV[s]
    return Lt.basePoint(i, q.padU, q.v, 0.0)
end
-- yaw (graus) de um brainrot na vaga: olha para o corredor
function Lt.slotYaw(i, s)
    local b = Lt.bases[i]
    local q = Lt.slotUV[s]
    local d = q.u < 0 and b.r or V.scale(b.r, -1)
    return math.atan(d[1], d[3]) * V.DEG
end

function Lt.lockPos(i) return Lt.basePoint(i, 0, -4.15, 0) end
function Lt.spawnPos(i) return Lt.basePoint(i, 0, 0.5, 0) end
function Lt.doorPos(i) return Lt.basePoint(i, 0, 5.0, 0) end
-- ponto na frente da porta, na grama (caminho dos bots)
function Lt.frontPos(i) return Lt.basePoint(i, 0, 6.6, 0) end
-- yaw de quem sai da base olhando para a esteira
function Lt.baseYaw(i)
    local f = Lt.bases[i].f
    return math.atan(f[1], f[3]) * V.DEG
end

-- dentro da base (area interna)?
function Lt.inBase(i, p, margin)
    local u, v = Lt.toBase(i, p)
    margin = margin or 0
    return math.abs(u) < Lt.BASE_WIDTH / 2 - margin and v > -Lt.BASE_DEPTH / 2 + margin and v < Lt.BASE_DEPTH / 2 + 0.3
end

function Lt.baseAt(p)
    for i = 1, 8 do if Lt.inBase(i, p) then return i end end
    return nil
end

-- posicao na esteira (z) -> mundo
function Lt.carpetPoint(z) return { 0, 0.06, z } end

return Lt
