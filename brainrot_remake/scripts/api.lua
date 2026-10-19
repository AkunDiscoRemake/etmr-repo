-- api.lua — camada fina e segura em cima do EMRAPI.
-- Tudo que depende de acesso direto a Unity (CS.UnityEngine.*) passa por pcall:
-- se a plataforma bloquear, o jogo continua funcionando sem o "extra".

local A = {}

local S = EMRAPI.Scene
A.V = require("vec")

A.hasCS = false
do
    local ok, cs = pcall(function() return CS end)
    A.hasCS = ok and cs ~= nil
end

A.matOk = A.hasCS   -- material (emissao/metalico) ainda nao falhou
A.rbOk = A.hasCS    -- Rigidbody (velocity/isKinematic) ainda nao falhou

local warned = {}
function A.warnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    EMRAPI:LogWarning("[Brainrot] " .. msg)
end

function A.log(msg) EMRAPI:Log("[Brainrot] " .. tostring(msg)) end

---------------------------------------------------------------------------
-- Objetos
---------------------------------------------------------------------------

-- Cria um primitivo ja configurado.
-- opt: parent, pos {x,y,z}, rot {x,y,z} (euler), scale {x,y,z}, color {r,g,b,a}, tex, mat, collider
function A.prim(kind, opt)
    local o = S:CreatePrimitive(kind)
    if o == nil then return nil end
    opt = opt or {}
    if opt.parent then S:SetParent(o, opt.parent) end
    local p = opt.pos
    if p then S:SetPosition(o, p[1], p[2], p[3]) else S:SetPosition(o, 0, 0, 0) end
    local r = opt.rot
    if r then S:SetRotation(o, r[1], r[2], r[3]) else S:SetRotation(o, 0, 0, 0) end
    local sc = opt.scale
    if sc then S:SetScale(o, sc[1], sc[2], sc[3]) end
    local c = opt.color
    if c then S:SetColor(o, c[1], c[2], c[3], c[4] or 1) end
    if opt.tex then A.texture(o, opt.tex) end
    if opt.mat then A.material(o, opt.mat) end
    if opt.collider == "box" then S:AddBoxCollider(o)
    elseif opt.collider == "sphere" then S:AddSphereCollider(o, opt.colliderRadius or 0.5) end
    return o
end

function A.empty(name, parent, pos, rot)
    local o = S:CreateObject(name or "obj")
    if parent then S:SetParent(o, parent) end
    if pos then S:SetPosition(o, pos[1], pos[2], pos[3]) else S:SetPosition(o, 0, 0, 0) end
    if rot then S:SetRotation(o, rot[1], rot[2], rot[3]) else S:SetRotation(o, 0, 0, 0) end
    return o
end

function A.pos(o, p) S:SetPosition(o, p[1], p[2], p[3]) end
function A.posXYZ(o, x, y, z) S:SetPosition(o, x, y, z) end
function A.rot(o, x, y, z) S:SetRotation(o, x, y, z) end
function A.rotBasis(o, m)
    local x, y, z = A.V.eulerFromBasis(m)
    S:SetRotation(o, x, y, z)
end
function A.scale(o, x, y, z) S:SetScale(o, x, y or x, z or x) end
function A.color(o, c, a) S:SetColor(o, c[1], c[2], c[3], a or c[4] or 1) end
function A.colorRGB(o, r, g, b, a) S:SetColor(o, r, g, b, a or 1) end
function A.parent(o, p) S:SetParent(o, p) end

function A.destroy(o)
    if o ~= nil then pcall(function() S:Destroy(o) end) end
end

function A.texture(o, path)
    local ok, res = pcall(function() return S:SetTexture(o, path) end)
    if not ok then A.warnOnce("tex", "SetTexture indisponivel: " .. tostring(res)) end
    return ok and res
end

-- Ativa/desativa (esconde) o objeto. Usa SetActive do GameObject quando possivel;
-- se nao der, encolhe a escala para zero.
function A.setVisible(o, vis, sx, sy, sz)
    if A.hasCS then
        local ok = pcall(function() o:SetActive(vis) end)
        if ok then return end
    end
    if vis then S:SetScale(o, sx or 1, sy or sx or 1, sz or sx or 1) else S:SetScale(o, 0, 0, 0) end
end

---------------------------------------------------------------------------
-- Materiais (opcional): metalico, suavidade e emissao.
---------------------------------------------------------------------------
local function unityColor(r, g, b, a)
    return CS.UnityEngine.Color(r, g, b, a or 1)
end

-- m: { metal = 0..1, smooth = 0..1, emit = {r,g,b} (intensidade ja embutida) }
function A.material(o, m)
    if not A.matOk or o == nil then return end
    local ok, err = pcall(function()
        local rend = o:GetComponent("Renderer")
        if rend == nil then return end
        local mat = rend.material
        if m.metal then mat:SetFloat("_Metallic", m.metal) end
        if m.smooth then
            mat:SetFloat("_Glossiness", m.smooth)
            mat:SetFloat("_Smoothness", m.smooth)
        end
        if m.emit then
            mat:EnableKeyword("_EMISSION")
            mat:SetColor("_EmissionColor", unityColor(m.emit[1], m.emit[2], m.emit[3], 1))
        end
        if m.noShadow then
            rend.shadowCastingMode = CS.UnityEngine.Rendering.ShadowCastingMode.Off
        end
    end)
    if not ok then
        A.matOk = false
        A.warnOnce("mat", "Material avancado indisponivel (ok, segue sem): " .. tostring(err))
    end
end

-- Repete a textura (tiling): sx, sy = quantos "ladrilhos" cabem no objeto.
-- As texturas tem 8x8 ladrilhos; sem CS a textura fica esticada (8 ladrilhos por face).
A.tileOk = A.hasCS
function A.tiling(o, sx, sy)
    if not A.tileOk or o == nil then return end
    local ok = pcall(function()
        local mat = o:GetComponent("Renderer").material
        mat.mainTextureScale = CS.UnityEngine.Vector2(sx / 8, sy / 8)
    end)
    if not ok then A.tileOk = false; A.warnOnce("tile", "tiling de textura indisponivel") end
end

-- Material "unlit" (sem luz): textos, placas, ceu. Tenta Sprites/Default (aceita
-- transparencia e cor), depois outros. Sem CS: material normal sem emissao.
A.unlitOk = A.hasCS
local unlitShader = nil
function A.unlit(o)
    if not A.unlitOk or o == nil then return false end
    local ok, err = pcall(function()
        if not unlitShader then
            for _, n in ipairs({ "Sprites/Default", "Unlit/Transparent", "Universal Render Pipeline/Unlit", "Unlit/Texture" }) do
                local s = CS.UnityEngine.Shader.Find(n)
                if s ~= nil then unlitShader = s; break end
            end
            if not unlitShader then error("nenhum shader unlit") end
        end
        local r = o:GetComponent("Renderer")
        r.material.shader = unlitShader
        r.shadowCastingMode = CS.UnityEngine.Rendering.ShadowCastingMode.Off
        r.receiveShadows = false
    end)
    if not ok then
        A.unlitOk = false
        A.warnOnce("unlit", "shader unlit indisponivel (ok, segue com o padrao): " .. tostring(err))
    end
    return ok
end

-- quad de interface: unlit se der; senao, material normal sem sombra
function A.uiQuad(o)
    if not A.unlit(o) then A.material(o, { noShadow = true }) end
    return o
end

-- Muda so a emissao (para piscar luzes, olhos dos bots etc).
function A.emission(o, r, g, b)
    if not A.matOk or o == nil then return end
    local ok = pcall(function()
        local mat = o:GetComponent("Renderer").material
        mat:SetColor("_EmissionColor", unityColor(r, g, b, 1))
    end)
    if not ok then A.matOk = false end
end

---------------------------------------------------------------------------
-- Fisica
---------------------------------------------------------------------------
function A.addBody(o, mass, gravity)
    local ok, rb = pcall(function() return S:AddRigidbody(o, mass, gravity ~= false) end)
    if ok then return rb end
    A.warnOnce("rb", "AddRigidbody falhou: " .. tostring(rb))
    return nil
end

function A.boxCollider(o) pcall(function() S:AddBoxCollider(o) end) end
function A.sphereCollider(o, r) pcall(function() S:AddSphereCollider(o, r) end) end

-- velocidade em coordenadas do MUNDO da Unity
function A.setVelocity(rb, vx, vy, vz)
    if not A.rbOk or rb == nil then return false end
    local ok = pcall(function()
        local v = CS.UnityEngine.Vector3(vx, vy, vz)
        local okv = pcall(function() rb.linearVelocity = v end)
        if not okv then rb.velocity = v end
    end)
    if not ok then
        A.rbOk = false
        A.warnOnce("vel", "Rigidbody.velocity indisponivel — arremessos ficam sem impulso")
    end
    return ok
end

function A.setAngular(rb, x, y, z)
    if not A.rbOk or rb == nil then return end
    pcall(function() rb.angularVelocity = CS.UnityEngine.Vector3(x, y, z) end)
end

function A.setKinematic(rb, k)
    if not A.rbOk or rb == nil then return false end
    local ok = pcall(function() rb.isKinematic = k end)
    return ok
end

function A.addImpulse(rb, x, y, z)
    if not A.rbOk or rb == nil then return end
    pcall(function()
        rb:AddForce(CS.UnityEngine.Vector3(x, y, z), CS.UnityEngine.ForceMode.Impulse)
    end)
end

---------------------------------------------------------------------------
-- Leitura de pose de objetos com fisica.
-- Preferimos transform.localPosition (sabemos que e local). Sem CS, usamos
-- Scene:GetPositionX/Y/Z e o modo detectado pela sonda (local ou mundo).
---------------------------------------------------------------------------
A.getPosIsWorld = false
A.toLocalFn = nil   -- definido pelo rig: converte mundo -> local do mundo do jogo

function A.readPos(o)
    if A.hasCS then
        local ok, x, y, z = pcall(function()
            local p = o.transform.localPosition
            return p.x, p.y, p.z
        end)
        if ok then return { x, y, z } end
    end
    local x, y, z = S:GetPositionX(o), S:GetPositionY(o), S:GetPositionZ(o)
    if A.getPosIsWorld and A.toLocalFn then return A.toLocalFn({ x, y, z }) end
    return { x, y, z }
end

-- rotacao local como base (ou nil se nao der para ler)
function A.readBasis(o)
    if not A.hasCS then return nil end
    local ok, q = pcall(function()
        local r = o.transform.localRotation
        return { r.x, r.y, r.z, r.w }
    end)
    if not ok then return nil end
    return A.V.basisFromQuat(q[1], q[2], q[3], q[4])
end

-- Sonda: descobre se GetPositionX devolve posicao local ou global.
function A.probe(worldRoot)
    local o = S:CreateObject("probe")
    S:SetParent(o, worldRoot)
    S:SetPosition(o, 1.234, 2.345, 3.456)
    local x = S:GetPositionX(o)
    A.getPosIsWorld = math.abs(x - 1.234) > 0.001
    A.destroy(o)
    A.log("GetPosition retorna " .. (A.getPosIsWorld and "mundo" or "local") .. " | CS=" .. tostring(A.hasCS))
end

---------------------------------------------------------------------------
-- Audio
---------------------------------------------------------------------------
A.sfxVolume = 1.0
A.toWorldFn = nil   -- definido pelo rig: local do jogo -> mundo

function A.sound(path, vol)
    local ok, id = pcall(function() return EMRAPI.Audio:Play(path) end)
    if ok and id and vol and vol < 1 then pcall(function() EMRAPI.Audio:SetVolume(id, vol * A.sfxVolume) end) end
    return ok and id or nil
end

-- som 3D num ponto em coordenadas locais do jogo
function A.sound3D(path, p, vol, pitch)
    local w = p
    if A.toWorldFn then w = A.toWorldFn(p) end
    local ok, id = pcall(function() return EMRAPI.Audio:PlayAtPoint(path, w[1], w[2], w[3]) end)
    if ok and id then
        if vol and vol ~= 1 then pcall(function() EMRAPI.Audio:SetVolume(id, vol * A.sfxVolume) end) end
        if pitch and pitch ~= 1 then pcall(function() EMRAPI.Audio:SetPitch(id, pitch) end) end
    end
    return ok and id or nil
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
function A.getNum(k, d)
    local ok, v = pcall(function() return EMRAPI.Storage:GetNumber(k, d) end)
    if ok and v ~= nil then return v end
    return d
end
function A.getStr(k, d)
    local ok, v = pcall(function() return EMRAPI.Storage:GetString(k, d) end)
    if ok and v ~= nil then return v end
    return d
end
function A.getBool(k, d)
    local ok, v = pcall(function() return EMRAPI.Storage:GetBool(k, d) end)
    if ok and v ~= nil then return v end
    return d
end
function A.setNum(k, v) pcall(function() EMRAPI.Storage:SetNumber(k, v) end) end
function A.setStr(k, v) pcall(function() EMRAPI.Storage:Set(k, v) end) end
function A.setBool(k, v) pcall(function() EMRAPI.Storage:SetBool(k, v) end) end
function A.save() pcall(function() EMRAPI.Storage:Save() end) end

return A
