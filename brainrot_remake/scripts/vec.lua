-- vec.lua — matematica: vetores, quaternions, bases e angulos de Euler no estilo Unity.
-- Unity: sistema mao-esquerda, Y para cima, Z para frente. Quaternion.Euler(x,y,z) = Ry * Rx * Rz.
-- Vetores sao tabelas simples {x, y, z} (indices 1..3), sem metatabelas.

local V = {}

local sqrt, sin, cos, atan, asin, acos, abs = math.sqrt, math.sin, math.cos, math.atan, math.asin, math.acos, math.abs
local DEG, RAD = 180 / math.pi, math.pi / 180

V.DEG, V.RAD = DEG, RAD

function V.new(x, y, z) return { x or 0, y or 0, z or 0 } end
function V.copy(a) return { a[1], a[2], a[3] } end
function V.set(dst, a) dst[1], dst[2], dst[3] = a[1], a[2], a[3]; return dst end
function V.add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
function V.sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function V.scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
function V.madd(a, b, s) return { a[1] + b[1] * s, a[2] + b[2] * s, a[3] + b[3] * s } end
function V.dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function V.cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
function V.len(a) return sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
function V.len2(a) return a[1] * a[1] + a[2] * a[2] + a[3] * a[3] end
function V.dist(a, b)
    local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return sqrt(dx * dx + dy * dy + dz * dz)
end
function V.distXZ(a, b)
    local dx, dz = a[1] - b[1], a[3] - b[3]
    return sqrt(dx * dx + dz * dz)
end
function V.norm(a)
    local l = sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    if l < 1e-9 then return { 0, 0, 1 } end
    return { a[1] / l, a[2] / l, a[3] / l }
end
function V.lerp(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
function V.lerpInto(dst, b, t)
    dst[1] = dst[1] + (b[1] - dst[1]) * t
    dst[2] = dst[2] + (b[2] - dst[2]) * t
    dst[3] = dst[3] + (b[3] - dst[3]) * t
    return dst
end
function V.mid(a, b) return { (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5, (a[3] + b[3]) * 0.5 } end
function V.avg(list)
    local x, y, z, n = 0, 0, 0, #list
    for i = 1, n do local p = list[i]; x, y, z = x + p[1], y + p[2], z + p[3] end
    return { x / n, y / n, z / n }
end

-- Rotacao em Y igual a um Transform da Unity com eulerAngles (0, deg, 0).
function V.rotY(a, deg)
    local r = deg * RAD
    local c, s = cos(r), sin(r)
    return { a[1] * c + a[3] * s, a[2], -a[1] * s + a[3] * c }
end

-- Suavizacao independente de FPS: rate = velocidade (1/s).
function V.smoothK(rate, dt)
    return 1 - math.exp(-rate * dt)
end

function V.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

---------------------------------------------------------------------------
-- Matrizes 3x3 guardadas como tres colunas: m = { r = {...}, u = {...}, f = {...} }
-- (eixos locais X, Y, Z do objeto no espaco do pai).
---------------------------------------------------------------------------

-- Base ortonormal a partir de "frente" e um "cima" aproximado.
function V.basis(fwd, upHint)
    local f = V.norm(fwd)
    local r = V.cross(upHint, f)
    if V.len2(r) < 1e-8 then
        r = V.cross({ 0, 1, 0 }, f)
        if V.len2(r) < 1e-8 then r = { 1, 0, 0 } end
    end
    r = V.norm(r)
    local u = V.cross(f, r)
    return { r = r, u = u, f = f }
end

function V.identity() return { r = { 1, 0, 0 }, u = { 0, 1, 0 }, f = { 0, 0, 1 } } end

-- m * v (vetor do espaco local para o do pai)
function V.mulMV(m, v)
    local r, u, f = m.r, m.u, m.f
    return {
        r[1] * v[1] + u[1] * v[2] + f[1] * v[3],
        r[2] * v[1] + u[2] * v[2] + f[2] * v[3],
        r[3] * v[1] + u[3] * v[2] + f[3] * v[3],
    }
end

-- m^T * v (do espaco do pai para o local)
function V.mulTMV(m, v)
    return { V.dot(m.r, v), V.dot(m.u, v), V.dot(m.f, v) }
end

-- a * b (primeiro b, depois a)
function V.mulMM(a, b)
    return { r = V.mulMV(a, b.r), u = V.mulMV(a, b.u), f = V.mulMV(a, b.f) }
end

function V.transpose(m)
    local r, u, f = m.r, m.u, m.f
    return { r = { r[1], u[1], f[1] }, u = { r[2], u[2], f[2] }, f = { r[3], u[3], f[3] } }
end

-- Interpolacao de base: lerp em f e u, depois ortonormaliza.
function V.slerpBasis(a, b, t)
    return V.basis(V.lerp(a.f, b.f, t), V.lerp(a.u, b.u, t))
end

-- Matriz de rotacao em torno de um eixo unitario (graus).
function V.axisAngle(axis, deg)
    local a = deg * RAD
    local c, s = cos(a), sin(a)
    local x, y, z = axis[1], axis[2], axis[3]
    local t = 1 - c
    -- colunas da matriz
    return {
        r = { t * x * x + c, t * x * y + s * z, t * x * z - s * y },
        u = { t * x * y - s * z, t * y * y + c, t * y * z + s * x },
        f = { t * x * z + s * y, t * y * z - s * x, t * z * z + c },
    }
end

function V.rotateAround(v, axis, deg)
    return V.mulMV(V.axisAngle(axis, deg), v)
end

-- Euler (graus) no formato da Unity a partir da base. Elemento m[linha][coluna]:
-- coluna 0 = r, 1 = u, 2 = f.
function V.eulerFromBasis(m)
    local r, u, f = m.r, m.u, m.f
    local m12 = f[2]          -- linha 1, coluna 2
    local x, y, z
    if m12 < -0.99999 then
        x = 90; y = atan(-r[3], r[1]) * DEG; z = 0         -- m20 = r[3], m00 = r[1]
    elseif m12 > 0.99999 then
        x = -90; y = atan(-r[3], r[1]) * DEG; z = 0
    else
        x = asin(-m12) * DEG
        y = atan(f[1], f[3]) * DEG                          -- m02, m22
        z = atan(r[2], u[2]) * DEG                          -- m10, m11
    end
    return x, y, z
end

-- Base a partir de Euler da Unity: Ry * Rx * Rz.
function V.basisFromEuler(xd, yd, zd)
    local cx, sx = cos(xd * RAD), sin(xd * RAD)
    local cy, sy = cos(yd * RAD), sin(yd * RAD)
    local cz, sz = cos(zd * RAD), sin(zd * RAD)
    -- linhas da matriz Ry*Rx*Rz
    local m00, m01, m02 = cy * cz + sy * sx * sz, -cy * sz + sy * sx * cz, sy * cx
    local m10, m11, m12 = cx * sz, cx * cz, -sx
    local m20, m21, m22 = -sy * cz + cy * sx * sz, sy * sz + cy * sx * cz, cy * cx
    return { r = { m00, m10, m20 }, u = { m01, m11, m21 }, f = { m02, m12, m22 } }
end

-- Euler para um objeto cujo eixo Y local deve apontar ao longo de dir
-- (capsulas/cilindros da Unity sao alongados em Y).
function V.eulerAlongY(dir)
    local d = V.norm(dir)
    local x = acos(V.clamp(d[2], -1, 1)) * DEG
    local y = atan(d[1], d[3]) * DEG
    return x, y, 0
end

-- Quaternion (x,y,z,w) -> base
function V.basisFromQuat(qx, qy, qz, qw)
    local xx, yy, zz = qx * qx, qy * qy, qz * qz
    local xy, xz, yz = qx * qy, qx * qz, qy * qz
    local wx, wy, wz = qw * qx, qw * qy, qw * qz
    return {
        r = { 1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy) },
        u = { 2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx) },
        f = { 2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy) },
    }
end

function V.basisToQuat(m)
    local m00, m11, m22 = m.r[1], m.u[2], m.f[3]
    local tr = m00 + m11 + m22
    local qx, qy, qz, qw
    if tr > 0 then
        local s = sqrt(tr + 1) * 2
        qw = 0.25 * s
        qx = (m.u[3] - m.f[2]) / s
        qy = (m.f[1] - m.r[3]) / s
        qz = (m.r[2] - m.u[1]) / s
    elseif m00 > m11 and m00 > m22 then
        local s = sqrt(1 + m00 - m11 - m22) * 2
        qw = (m.u[3] - m.f[2]) / s
        qx = 0.25 * s
        qy = (m.u[1] + m.r[2]) / s
        qz = (m.f[1] + m.r[3]) / s
    elseif m11 > m22 then
        local s = sqrt(1 + m11 - m00 - m22) * 2
        qw = (m.f[1] - m.r[3]) / s
        qx = (m.u[1] + m.r[2]) / s
        qy = 0.25 * s
        qz = (m.f[2] + m.u[3]) / s
    else
        local s = sqrt(1 + m22 - m00 - m11) * 2
        qw = (m.r[2] - m.u[1]) / s
        qx = (m.f[1] + m.r[3]) / s
        qy = (m.f[2] + m.u[3]) / s
        qz = 0.25 * s
    end
    return qx, qy, qz, qw
end

-- Pose = posicao + base. Transforma ponto do local para o pai.
function V.poseApply(pos, m, p)
    local w = V.mulMV(m, p)
    return { pos[1] + w[1], pos[2] + w[2], pos[3] + w[3] }
end

function V.poseInverseApply(pos, m, p)
    return V.mulTMV(m, V.sub(p, pos))
end

---------------------------------------------------------------------------
-- Testes geometricos de raycast (raio: origem o, direcao unitaria d)
---------------------------------------------------------------------------

-- Raio contra esfera: retorna t ou nil
function V.raySphere(o, d, c, r)
    local ocx, ocy, ocz = o[1] - c[1], o[2] - c[2], o[3] - c[3]
    local b = ocx * d[1] + ocy * d[2] + ocz * d[3]
    local cc = ocx * ocx + ocy * ocy + ocz * ocz - r * r
    local disc = b * b - cc
    if disc < 0 then return nil end
    local s = sqrt(disc)
    local t = -b - s
    if t < 0 then t = -b + s end
    if t < 0 then return nil end
    return t
end

-- Raio contra capsula (segmento a-b, raio r). Retorna t ou nil.
function V.rayCapsule(o, d, a, b, r)
    local ab = V.sub(b, a)
    local c_ = V.dot(ab, ab)
    if c_ < 1e-9 then return V.raySphere(o, d, a, r) end
    local w0 = V.sub(o, a)
    local b_ = V.dot(d, ab)
    local d_ = V.dot(d, w0)
    local e_ = V.dot(ab, w0)
    local denom = c_ - b_ * b_
    local u
    if denom < 1e-9 then u = 0 else u = V.clamp((e_ - b_ * d_) / denom, 0, 1) end
    local t = V.dot(V.sub(V.madd(a, ab, u), o), d)
    if t < 0 then
        t = 0
        u = V.clamp(V.dot(V.sub(o, a), ab) / c_, 0, 1)
    end
    local pc = V.madd(a, ab, u)
    local pr = V.madd(o, d, t)
    local dist = V.dist(pr, pc)
    if dist > r then return nil end
    local th = t - sqrt(math.max(0, r * r - dist * dist))
    if th < 0 then th = 0 end
    return th
end

-- Raio contra AABB (mn, mx). Retorna t e a normal da face atingida.
function V.rayAABB(o, d, mn, mx)
    local tmin, tmax = -1e9, 1e9
    local nAxis = 0
    for i = 1, 3 do
        if abs(d[i]) < 1e-9 then
            if o[i] < mn[i] or o[i] > mx[i] then return nil end
        else
            local inv = 1 / d[i]
            local t1 = (mn[i] - o[i]) * inv
            local t2 = (mx[i] - o[i]) * inv
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin = t1; nAxis = i end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end
    if tmax < 0 then return nil end
    local t = tmin >= 0 and tmin or 0
    local n = { 0, 0, 0 }
    if nAxis > 0 then n[nAxis] = d[nAxis] > 0 and -1 or 1 end
    return t, n
end

-- Distancia de um ponto ate um segmento
function V.pointSegDist(p, a, b)
    local ab = V.sub(b, a)
    local l2 = V.dot(ab, ab)
    local u = 0
    if l2 > 1e-9 then u = V.clamp(V.dot(V.sub(p, a), ab) / l2, 0, 1) end
    local c = V.madd(a, ab, u)
    return V.dist(p, c), c
end

return V
