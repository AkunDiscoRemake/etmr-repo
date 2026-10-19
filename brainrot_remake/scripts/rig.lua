-- rig.lua — "rig" do jogador.
-- Como nao da para mover a camera do celular, a locomocao move o MUNDO inteiro:
-- todo o conteudo do jogo fica dentro de `R.world`, e andar/virar desloca esse objeto.
-- Toda a logica do jogo trabalha em coordenadas LOCAIS do mundo (chao em y = 0).

local V = require("vec")
local A = require("api")

local R = {}

local IN = EMRAPI.Input

R.world = nil
R.T = { 0, 0, 0 }     -- posicao global da raiz do mundo
R.yaw = 0             -- rotacao Y global da raiz do mundo (graus)

R.height = 1.65       -- altura dos olhos do jogador (m)
R.head = { 0, 1.65, 0 }          -- cabeca em coord. locais
R.headB = V.identity()           -- base da cabeca (local)
R.headW = { 0, 0, 0 }            -- cabeca em coord. globais
R.headYaw = 0                    -- yaw da cabeca no espaco local (graus)
R.bodyYaw = 0                    -- yaw do "corpo" (segue a cabeca com atraso)
R.velocity = { 0, 0, 0 }         -- velocidade de locomocao (local)
R.bounds = nil                   -- {minX, maxX, minZ, maxZ}
R.obstacles = {}                 -- lista de {x, z, r} (pilares/colunas) e caixas {box={...}}
R.tracking = "6dof"

function R.toLocal(p)
    return V.rotY({ p[1] - R.T[1], p[2] - R.T[2], p[3] - R.T[3] }, -R.yaw)
end
function R.toWorld(p)
    local w = V.rotY(p, R.yaw)
    return { w[1] + R.T[1], w[2] + R.T[2], w[3] + R.T[3] }
end
function R.dirToWorld(d) return V.rotY(d, R.yaw) end
function R.dirToLocal(d) return V.rotY(d, -R.yaw) end

local function applyRoot()
    A.posXYZ(R.world, R.T[1], R.T[2], R.T[3])
    A.rot(R.world, 0, R.yaw, 0)
end

local function readHeadWorld()
    local x = IN:GetHeadPositionX()
    local y = IN:GetHeadPositionY()
    local z = IN:GetHeadPositionZ()
    local qx = IN:GetHeadRotationX()
    local qy = IN:GetHeadRotationY()
    local qz = IN:GetHeadRotationZ()
    local qw = IN:GetHeadRotationW()
    return { x, y, z }, V.basisFromQuat(qx, qy, qz, qw)
end

local function yawOf(f)
    return math.atan(f[1], f[3]) * V.DEG
end

function R.init(spawn, height)
    R.height = height or R.height
    local ok, mode = pcall(function() return EMRAPI.System:GetTrackingMode() end)
    R.tracking = ok and mode or "6dof"
    R.world = A.empty("BrainrotWorld")
    R.recenter(spawn)
    A.toLocalFn = R.toLocal
    A.toWorldFn = R.toWorld
end

-- Coloca o jogador no ponto `spawn` (local), olhando para +Z.
function R.recenter(spawn)
    spawn = spawn or { 0, 0, 0 }
    local hw, hb = readHeadWorld()
    R.yaw = yawOf(hb.f)
    local off = V.rotY({ spawn[1], R.height, spawn[3] }, R.yaw)
    R.T = { hw[1] - off[1], hw[2] - off[2], hw[3] - off[3] }
    R.liftY = 0
    applyRoot()
    R.update(0)
    R.bodyYaw = R.headYaw
end

-- Pulo: levanta o jogador `y` metros acima do chao (o mundo desce).
R.liftY = 0
function R.setLift(y)
    R.T[2] = R.T[2] - (y - R.liftY)
    R.liftY = y
    applyRoot()
end

-- Ajusta so a altura do chao mantendo a posicao.
function R.setHeight(h)
    local dy = h - R.height
    R.height = h
    R.T[2] = R.T[2] - dy
    applyRoot()
end

function R.update(dt)
    local hw, hb = readHeadWorld()
    R.headW = hw
    R.head = R.toLocal(hw)
    R.headB = {
        r = R.dirToLocal(hb.r),
        u = R.dirToLocal(hb.u),
        f = R.dirToLocal(hb.f),
    }
    R.headYaw = yawOf(R.headB.f)
    -- o corpo acompanha a cabeca quando ela vira mais de ~35 graus ou com o tempo
    local diff = ((R.headYaw - R.bodyYaw + 540) % 360) - 180
    local k = math.abs(diff) > 35 and V.smoothK(6, dt) or V.smoothK(1.2, dt)
    R.bodyYaw = R.bodyYaw + diff * k
end

-- Ponto no corpo do jogador (offset relativo ao "corpo": x direita, y a partir da cabeca, z frente)
function R.bodyPoint(ox, oy, oz)
    local o = V.rotY({ ox, 0, oz }, R.bodyYaw)
    return { R.head[1] + o[1], R.head[2] + oy, R.head[3] + o[3] }
end

-- Direcao "para frente" horizontal da cabeca (local)
function R.flatForward()
    local f = R.headB.f
    local l = math.sqrt(f[1] * f[1] + f[3] * f[3])
    if l < 1e-4 then return { 0, 0, 1 } end
    return { f[1] / l, 0, f[3] / l }
end

-- Resolve colisao de um circulo (raio pr) com limites e obstaculos.
-- obstacles: lista { {x,z,r} | {box={minX,maxX,minZ,maxZ}} }; usa R.obstacles + R.dynamic por padrao.
local function pushOut(x, z, pr, ob)
    if ob.r then
        local dx, dz = x - ob.x, z - ob.z
        local d = math.sqrt(dx * dx + dz * dz)
        local minD = ob.r + pr
        if d < minD and d > 1e-5 then
            x = ob.x + dx / d * minD
            z = ob.z + dz / d * minD
        end
    elseif ob.box then
        local bx = ob.box
        local cx = V.clamp(x, bx[1], bx[2])
        local cz = V.clamp(z, bx[3], bx[4])
        local dx, dz = x - cx, z - cz
        local d = math.sqrt(dx * dx + dz * dz)
        if d < pr then
            if d > 1e-5 then
                x = cx + dx / d * pr
                z = cz + dz / d * pr
            else
                -- dentro da caixa: empurra pela menor saida
                local opts = { { bx[1] - pr, z }, { bx[2] + pr, z }, { x, bx[3] - pr }, { x, bx[4] + pr } }
                local best, bd = nil, 1e9
                for _, o in ipairs(opts) do
                    local dd = math.abs(o[1] - x) + math.abs(o[2] - z)
                    if dd < bd then bd = dd; best = o end
                end
                x, z = best[1], best[2]
            end
        end
    end
    return x, z
end

R.dynamic = {}
local function collide(p, pr, dyn)
    local x, z = p[1], p[3]
    local b = R.bounds
    if b then
        x = V.clamp(x, b[1] + pr, b[2] - pr)
        z = V.clamp(z, b[3] + pr, b[4] - pr)
    end
    for _, ob in ipairs(R.obstacles) do x, z = pushOut(x, z, pr, ob) end
    for _, ob in ipairs(dyn or R.dynamic) do x, z = pushOut(x, z, pr, ob) end
    return x, z
end
R.collide = collide

-- Locomocao suave: move o jogador `dx, dz` em coordenadas locais.
function R.move(dx, dz)
    local target = { R.head[1] + dx, R.head[2], R.head[3] + dz }
    local x, z = collide(target, 0.25)
    local mx, mz = x - R.head[1], z - R.head[3]
    local w = V.rotY({ mx, 0, mz }, R.yaw)
    R.T[1] = R.T[1] - w[1]
    R.T[3] = R.T[3] - w[3]
    R.head[1], R.head[3] = x, z
    applyRoot()
end

-- Empurra o jogador para fora de paredes mesmo sem input (andar fisicamente no 6dof)
function R.resolvePhysicalCollision()
    local x, z = collide(R.head, 0.2)
    if math.abs(x - R.head[1]) > 1e-4 or math.abs(z - R.head[3]) > 1e-4 then
        R.move(0, 0)
    end
end

-- Snap turn em torno da cabeca (graus, positivo = direita)
function R.turn(a)
    local H = R.headW
    R.yaw = R.yaw - a
    local rel = V.rotY({ R.T[1] - H[1], R.T[2] - H[2], R.T[3] - H[3] }, -a)
    R.T = { H[1] + rel[1], H[2] + rel[2], H[3] + rel[3] }
    applyRoot()
    R.update(0)
    R.bodyYaw = R.bodyYaw + a
end

-- Landmarks da mao (21 pontos) em coordenadas locais. Retorna nil se nao rastreada.
local idx = {}
for i = 0, 20 do idx[i] = tostring(i) end

function R.readHand(side, out)
    local tracked = IN:IsHandTracked(side)
    if not tracked then return false end
    for i = 0, 20 do
        local x, y, z = IN:GetHandPosition(side, idx[i])
        if x == nil then return false end
        local p = R.toLocal({ x, y, z })
        local o = out[i]
        if o then o[1], o[2], o[3] = p[1], p[2], p[3] else out[i] = p end
    end
    return true
end

function R.gesture(side)
    local ok, g = pcall(function() return IN:GetHandGesture(side) end)
    return ok and g or ""
end

function R.pinch(side)
    local ok, v = pcall(function() return IN:GetPinchStrength(side) end)
    return ok and v or 0
end

return R
