-- mock_emrapi.lua — EMRAPI falso para testar o jogo fora do celular (Lua 5.3).
-- Mantem um grafo de cena, fisica simplificada, timers, audio/log e input sintetico.
-- Usado por tools/run_sim.py. NAO vai dentro do .emrd.

MOCK = {
    time = 0, dt = 1 / 60,
    objects = {}, nextId = 1,
    log = {}, sounds = {}, errors = {},
    head = { pos = { 0.3, 0.1, -0.2 }, q = { 0, 0, 0, 1 } },
    hands = { left = { tracked = false, lm = {} }, right = { tracked = false, lm = {} } },
    gesture = { left = "None", right = "None" },
    keys = {},            -- "joystick button 5" = true
    axes = { Horizontal = 0, Vertical = 0 },
    joysticks = {},
    storage = {},
    ui = {}, buttons = {},
    withCS = true,
    trackingMode = "6dof",
}

local function vec3(x, y, z) return { x = x, y = y, z = z } end

---------------------------------------------------------------------------
-- Objetos de cena
---------------------------------------------------------------------------
local GO = {}
GO.__index = GO

local function newObj(kind, name)
    local o = setmetatable({
        id = MOCK.nextId, kind = kind, name = name or kind,
        parent = nil, pos = { 0, 0, 0 }, rot = { 0, 0, 0 }, scl = { 1, 1, 1 },
        color = { 1, 1, 1, 1 }, active = true, destroyed = false, colliders = {},
    }, GO)
    MOCK.nextId = MOCK.nextId + 1
    MOCK.objects[o.id] = o
    o.transform = setmetatable({}, {
        __index = function(_, k)
            if k == "localPosition" then return vec3(o.pos[1], o.pos[2], o.pos[3]) end
            if k == "localRotation" then
                local V = require("vec")
                local qx, qy, qz, qw = V.basisToQuat(V.basisFromEuler(o.rot[1], o.rot[2], o.rot[3]))
                return { x = qx, y = qy, z = qz, w = qw }
            end
        end,
    })
    return o
end

function GO:SetActive(v) self.active = v end
function GO:GetComponent(t)
    local o = self
    if t == "Renderer" or t == "MeshRenderer" then
        if o.kind == "empty" then return nil end
        o.material = o.material or {}
        return {
            material = {
                SetFloat = function(_, k, v) o.material[k] = v end,
                SetColor = function(_, k, c) o.material[k] = { c.r, c.g, c.b } end,
                EnableKeyword = function(_, k) o.material[k] = true end,
            },
        }
    end
    return nil
end

local function chk(o, fn)
    if o == nil then error(fn .. ": objeto nil", 3) end
    if getmetatable(o) ~= GO then error(fn .. ": nao e GameObject (" .. type(o) .. ")", 3) end
    if o.destroyed then error(fn .. ": objeto destruido #" .. o.id .. " " .. o.name, 3) end
end
local function num(v, fn)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
        error(fn .. ": numero invalido " .. tostring(v), 3)
    end
end

local root = newObj("empty", "AppRoot")

local Scene = {}
function Scene:GetRoot() return root end
function Scene:CreatePrimitive(k)
    assert(({ cube = 1, sphere = 1, capsule = 1, cylinder = 1, plane = 1, quad = 1 })[k], "primitivo invalido " .. tostring(k))
    local o = newObj(k, k); o.parent = root; return o
end
function Scene:CreateObject(n) local o = newObj("empty", n); o.parent = root; return o end
function Scene:Find(n)
    for _, o in pairs(MOCK.objects) do if o.name == n and not o.destroyed then return o end end
end
local function destroyRec(o)
    o.destroyed = true
    MOCK.objects[o.id] = nil
    for _, c in pairs(MOCK.objects) do if c.parent == o then destroyRec(c) end end
end
function Scene:Destroy(o) chk(o, "Destroy"); destroyRec(o) end
function Scene:SetPosition(o, x, y, z) chk(o, "SetPosition"); num(x, "SetPosition"); num(y, "SetPosition"); num(z, "SetPosition"); o.pos = { x, y, z } end
function Scene:SetRotation(o, x, y, z) chk(o, "SetRotation"); num(x, "SetRotation"); num(y, "SetRotation"); num(z, "SetRotation"); o.rot = { x, y, z } end
function Scene:SetScale(o, x, y, z) chk(o, "SetScale"); num(x, "SetScale"); num(y, "SetScale"); num(z, "SetScale"); o.scl = { x, y, z } end
function Scene:SetColor(o, r, g, b, a) chk(o, "SetColor"); num(r, "SetColor"); num(g, "SetColor"); num(b, "SetColor"); o.color = { r, g, b, a or 1 } end
function Scene:SetParent(c, p) chk(c, "SetParent"); chk(p, "SetParent"); c.parent = p end
function Scene:GetPositionX(o) chk(o, "GetPositionX"); return o.pos[1] end
function Scene:GetPositionY(o) chk(o, "GetPositionY"); return o.pos[2] end
function Scene:GetPositionZ(o) chk(o, "GetPositionZ"); return o.pos[3] end
function Scene:AddRigidbody(o, mass, grav)
    chk(o, "AddRigidbody")
    local rb = { mass = mass, useGravity = grav, isKinematic = false, velocity = vec3(0, 0, 0), angularVelocity = vec3(0, 0, 0) }
    function rb.AddForce(self, f) self.velocity = vec3(self.velocity.x + f.x / mass, self.velocity.y + f.y / mass, self.velocity.z + f.z / mass) end
    o.rb = rb
    return rb
end
function Scene:AddBoxCollider(o) chk(o, "AddBoxCollider"); o.colliders[#o.colliders + 1] = "box"; return {} end
function Scene:AddSphereCollider(o, r) chk(o, "AddSphereCollider"); num(r, "AddSphereCollider"); o.colliders[#o.colliders + 1] = "sphere"; return {} end
function Scene:SetTexture(o, path) chk(o, "SetTexture"); o.tex = path; MOCK.textures = MOCK.textures or {}; MOCK.textures[path] = true; return true end
function Scene:AttachToHeadAt(o, x, y, z) chk(o, "AttachToHeadAt"); o.headAttach = { x, y, z } end
function Scene:AttachToHead(o) chk(o, "AttachToHead"); o.headAttach = { 0, 0, 0.5 } end
function Scene:DetachFromHead(o) o.headAttach = nil end
function Scene:AttachToHand(o) end
function Scene:AttachToHandSmooth(o) end
function Scene:DetachFromHand(o) end
function Scene:LoadModel(path, cb) cb(nil, "mock: sem GLB") end
function Scene:Spawn(p) return newObj("empty") end
function Scene:SpawnAt(p) return newObj("empty") end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local Input = {}
function Input:IsHandTracked(s) return MOCK.hands[s].tracked end
function Input:GetHandPosition(s, point)
    local h = MOCK.hands[s]
    if not h.tracked then return 0, 0, 0 end
    local i = tonumber(point)
    local p = h.lm[i]
    return p[1], p[2], p[3]
end
function Input:GetHandRotation(s) return 0, 0, 0, 1 end
function Input:GetHandPositionX(s) return Input:GetHandPosition(s, "0") end
function Input:GetHandGesture(s) return MOCK.gesture[s] end
function Input:GetPinchStrength(s) return 0 end
function Input:IsGrabbing(s) return false end
function Input:GetHeadPositionX() return MOCK.head.pos[1] end
function Input:GetHeadPositionY() return MOCK.head.pos[2] end
function Input:GetHeadPositionZ() return MOCK.head.pos[3] end
function Input:GetHeadRotationX() return MOCK.head.q[1] end
function Input:GetHeadRotationY() return MOCK.head.q[2] end
function Input:GetHeadRotationZ() return MOCK.head.q[3] end
function Input:GetHeadRotationW() return MOCK.head.q[4] end

---------------------------------------------------------------------------
-- Timer / Tween
---------------------------------------------------------------------------
local timers, timerSeq = {}, 1
local Timer = {}
function Timer:Repeat(i, cb) timers[timerSeq] = { t = MOCK.time + i, i = i, cb = cb, rep = true }; timerSeq = timerSeq + 1; return timerSeq - 1 end
function Timer:Delay(i, cb) timers[timerSeq] = { t = MOCK.time + i, i = i, cb = cb, rep = false }; timerSeq = timerSeq + 1; return timerSeq - 1 end
function Timer:Cancel(id) timers[id] = nil end
function MOCK.tickTimers()
    for id, t in pairs(timers) do
        if MOCK.time >= t.t then
            t.cb()
            if t.rep then t.t = MOCK.time + t.i else timers[id] = nil end
        end
    end
end

local tweens, tweenSeq = {}, 1
local Tween = {}
local function addTween(kind, o, x, y, z, d, cb)
    chk(o, "Tween." .. kind)
    if d <= 0 then
        if kind == "move" then o.pos = { x, y, z } elseif kind == "scale" then o.scl = { x, y, z } else o.rot = { x, y, z } end
        if cb then cb() end
        return -1
    end
    local field = kind == "move" and "pos" or (kind == "scale" and "scl" or "rot")
    local from = { o[field][1], o[field][2], o[field][3] }
    for id, tw in pairs(tweens) do if tw.o == o and tw.field == field then tweens[id] = nil end end
    tweens[tweenSeq] = { o = o, field = field, from = from, to = { x, y, z }, t0 = MOCK.time, d = d, cb = cb }
    tweenSeq = tweenSeq + 1
    return tweenSeq - 1
end
function Tween:MoveTo(o, x, y, z, d, cb) return addTween("move", o, x, y, z, d, cb) end
function Tween:ScaleTo(o, x, y, z, d, cb) return addTween("scale", o, x, y, z, d, cb) end
function Tween:RotateTo(o, x, y, z, d, cb) return addTween("rot", o, x, y, z, d, cb) end
function Tween:Cancel(id) tweens[id] = nil end
function Tween:CancelAll() tweens = {} end
function Tween:IsRunning(id) return tweens[id] ~= nil end
function MOCK.tickTweens()
    for id, tw in pairs(tweens) do
        if tw.o.destroyed then tweens[id] = nil else
            local k = math.min(1, (MOCK.time - tw.t0) / tw.d)
            local s = k * k * (3 - 2 * k)
            for i = 1, 3 do tw.o[tw.field][i] = tw.from[i] + (tw.to[i] - tw.from[i]) * s end
            if k >= 1 then tweens[id] = nil; if tw.cb then tw.cb() end end
        end
    end
end

---------------------------------------------------------------------------
-- Fisica bem simples (so para os renders do teste)
---------------------------------------------------------------------------
function MOCK.tickPhysics(dt)
    for _, o in pairs(MOCK.objects) do
        local rb = o.rb
        if rb and not rb.isKinematic then
            local v = rb.velocity
            if rb.useGravity then v.y = v.y - 9.81 * dt end
            o.pos[1] = o.pos[1] + v.x * dt
            o.pos[2] = o.pos[2] + v.y * dt
            o.pos[3] = o.pos[3] + v.z * dt
            if o.pos[2] < 0.05 then o.pos[2] = 0.05; v.y = -v.y * 0.3; v.x = v.x * 0.8; v.z = v.z * 0.8 end
        end
    end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local UI = {}
local function uiEl(kind, parent, text)
    local o = newObj("ui_" .. kind, kind)
    o.parent = parent or root
    o.text = text
    MOCK.ui[#MOCK.ui + 1] = o
    return o
end
function UI:CreatePanel(w, h) num(w, "CreatePanel"); return uiEl("panel") end
function UI:CreateText(p, t) return uiEl("text", p, t) end
function UI:CreateButton(p, t, cb) local o = uiEl("button", p, t); MOCK.buttons[t] = cb; o.cb = cb; return o end
function UI:CreateSlider(p, a, b, cb) local o = uiEl("slider", p); o.cb = cb; return o end
function UI:CreateToggle(p, t, cb) local o = uiEl("toggle", p, t); MOCK.buttons[t] = cb; o.cb = cb; return o end
function UI:CreateImage(p, path) return uiEl("image", p, path) end
function UI:SetText(o, t) chk(o, "UI.SetText"); assert(type(t) == "string", "SetText precisa string"); o.text = t end
function UI:GetText(o) return o.text end
function UI:SetPosition(o, x, y, z) chk(o, "UI.SetPosition"); num(x, "UI.SetPosition"); num(y, "UI.SetPosition") end
function UI:SetSize(o, w, h) chk(o, "UI.SetSize"); num(w, "UI.SetSize"); num(h, "UI.SetSize") end
function UI:SetColor(o, r, g, b, a) chk(o, "UI.SetColor"); num(r, "UI.SetColor") end
function UI:SetActive(o, v) chk(o, "UI.SetActive"); o.active = v end
function UI:Destroy(o) Scene:Destroy(o) end

---------------------------------------------------------------------------
-- Resto do EMRAPI
---------------------------------------------------------------------------
local function logf(kind) return function(_, m) MOCK.log[#MOCK.log + 1] = kind .. ": " .. tostring(m) end end

local audioSeq = 1
EMRAPI = {
    Log = logf("LOG"), LogWarning = logf("WARN"), LogError = logf("ERROR"),
    App = { id = "com.test", displayMode = "scene", RequestExit = function() end, GetName = function() return "t" end },
    System = {
        GetTime = function() return MOCK.time end,
        GetDeltaTime = function() return MOCK.dt end,
        GetPlatform = function() return "editor" end,
        GetTrackingMode = function() return MOCK.trackingMode end,
    },
    Math = {
        Random = function(_, a, b) return a + math.random() * (b - a) end,
        Lerp = function(_, a, b, t) return a + (b - a) * t end,
        Clamp = function(_, v, a, b) return math.max(a, math.min(b, v)) end,
        Distance = function(_, a, b, c, d, e, f) return math.sqrt((a - d) ^ 2 + (b - e) ^ 2 + (c - f) ^ 2) end,
    },
    Scene = Scene, Input = Input, Timer = Timer, Tween = Tween, UI = UI,
    Audio = {
        Play = function(_, p) assert(type(p) == "string"); MOCK.sounds[#MOCK.sounds + 1] = p; audioSeq = audioSeq + 1; return audioSeq end,
        PlayAtPoint = function(_, p, x, y, z) num(x, "PlayAtPoint"); MOCK.sounds[#MOCK.sounds + 1] = p; audioSeq = audioSeq + 1; return audioSeq end,
        PlayLoop = function(_, p) MOCK.sounds[#MOCK.sounds + 1] = p; audioSeq = audioSeq + 1; return audioSeq end,
        Stop = function() end, SetVolume = function() end, SetPitch = function() end,
        SetLoop = function() end, IsPlaying = function() return true end,
    },
    Storage = {
        Set = function(_, k, v) MOCK.storage[k] = v end,
        GetString = function(_, k, d) local v = MOCK.storage[k]; if v == nil then return d end; return v end,
        SetNumber = function(_, k, v) MOCK.storage[k] = v end,
        GetNumber = function(_, k, d) local v = MOCK.storage[k]; if v == nil then return d end; return v end,
        SetBool = function(_, k, v) MOCK.storage[k] = v end,
        GetBool = function(_, k, d) local v = MOCK.storage[k]; if v == nil then return d end; return v end,
        Remove = function(_, k) MOCK.storage[k] = nil end,
        Save = function() end,
    },
    Hands = {
        SetVisible = function() end, Reset = function() end, SetColor = function() end,
        SetAlpha = function() end, IsVisible = function() return false end,
    },
    Camera = { SetBackground = function(_, m) MOCK.background = m end, GetBackground = function() return MOCK.background end, Reset = function() end },
    Json = { Encode = function() return "{}" end, Decode = function() return {} end },
}

---------------------------------------------------------------------------
-- CS (Unity) falso
---------------------------------------------------------------------------
function MOCK.installCS()
    local names = setmetatable({}, {
        __index = function(_, k)
            if k == "Length" then return #MOCK.joysticks end
            return MOCK.joysticks[k + 1]
        end,
    })
    CS = {
        UnityEngine = {
            Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
            Vector3 = function(x, y, z) return vec3(x, y, z) end,
            ForceMode = { Impulse = 1 },
            Rendering = { ShadowCastingMode = { Off = 0 } },
            Input = {
                GetKey = function(name) assert(type(name) == "string"); return MOCK.keys[name] == true end,
                GetAxis = function(n) return MOCK.axes[n] or 0 end,
                GetJoystickNames = function() return names end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Maos sinteticas: mao aberta + dobra dos dedos
---------------------------------------------------------------------------
-- Mao direita com palma para baixo no espaco da mao: x direita, y = dorso, z = dedos.
local OPEN = {
    [0] = { 0, 0, 0 },
    { -0.025, -0.006, 0.025 }, { -0.045, -0.009, 0.05 }, { -0.06, -0.009, 0.075 }, { -0.07, -0.009, 0.095 },
    { -0.022, 0, 0.09 }, { -0.026, 0, 0.13 }, { -0.028, 0, 0.155 }, { -0.03, 0, 0.175 },
    { 0, 0, 0.095 }, { 0, 0, 0.14 }, { 0, 0, 0.168 }, { 0, 0, 0.19 },
    { 0.02, 0, 0.09 }, { 0.022, 0, 0.13 }, { 0.024, 0, 0.155 }, { 0.025, 0, 0.175 },
    { 0.038, 0, 0.08 }, { 0.042, 0, 0.11 }, { 0.045, 0, 0.13 }, { 0.047, 0, 0.147 },
}

-- curl: {polegar, indicador, medio, anelar, mindinho} 0..1
function MOCK.handPoints(side, curl)
    local pts = {}
    for i = 0, 20 do pts[i] = { OPEN[i][1], OPEN[i][2], OPEN[i][3] } end
    local fingers = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 }, { 17, 18, 19, 20 } }
    local angles = { 85, 105, 70 }
    for fi = 2, 5 do
        local f = fingers[fi]
        local c = curl[fi]
        local base = pts[f[1]]
        local acc = 0
        local prev = { base[1], base[2], base[3] }
        for j = 2, 4 do
            acc = acc + angles[j - 1] * c
            local seg = { OPEN[f[j]][1] - OPEN[f[j - 1]][1], OPEN[f[j]][2] - OPEN[f[j - 1]][2], OPEN[f[j]][3] - OPEN[f[j - 1]][3] }
            -- dobra para o lado da palma (-y)
            local L = math.sqrt(seg[2] ^ 2 + seg[3] ^ 2)
            local p = { prev[1] + seg[1], prev[2] - math.sin(math.rad(acc)) * L, prev[3] + math.cos(math.rad(acc)) * L }
            pts[f[j]] = p
            prev = p
        end
    end
    -- polegar: dobra para dentro
    local c = curl[1]
    for j = 2, 4 do
        local p = pts[j]
        pts[j] = { p[1] + 0.025 * c * (j - 1) / 3, p[2] - 0.015 * c, p[3] - 0.01 * c * (j - 1) / 3 }
    end
    if side == "left" then
        for i = 0, 20 do pts[i][1] = -pts[i][1] end
    end
    return pts
end

-- Coloca a mao no mundo: wrist (posicao global), base {r,u,f} (u = dorso/palma pra cima? f = dedos)
function MOCK.setHand(side, wrist, basis, curl, tracked)
    local h = MOCK.hands[side]
    h.tracked = tracked ~= false
    local pts = MOCK.handPoints(side, curl)
    for i = 0, 20 do
        local p = pts[i]
        h.lm[i] = {
            wrist[1] + basis.r[1] * p[1] + basis.u[1] * p[2] + basis.f[1] * p[3],
            wrist[2] + basis.r[2] * p[1] + basis.u[2] * p[2] + basis.f[2] * p[3],
            wrist[3] + basis.r[3] * p[1] + basis.u[3] * p[2] + basis.f[3] * p[3],
        }
    end
end

---------------------------------------------------------------------------
-- Exportar a cena (transformacoes globais) para o render em three.js
---------------------------------------------------------------------------
local function worldMatrix(o, V)
    -- retorna pos, base (com escala nas colunas)
    local B = V.basisFromEuler(o.rot[1], o.rot[2], o.rot[3])
    local m = { r = V.scale(B.r, o.scl[1]), u = V.scale(B.u, o.scl[2]), f = V.scale(B.f, o.scl[3]) }
    local p = { o.pos[1], o.pos[2], o.pos[3] }
    local par = o.parent
    local visible = o.active
    while par do
        if not par.active then visible = false end
        local PB = V.basisFromEuler(par.rot[1], par.rot[2], par.rot[3])
        local PM = { r = V.scale(PB.r, par.scl[1]), u = V.scale(PB.u, par.scl[2]), f = V.scale(PB.f, par.scl[3]) }
        p = V.add(V.mulMV(PM, p), par.pos)
        m = { r = V.mulMV(PM, m.r), u = V.mulMV(PM, m.u), f = V.mulMV(PM, m.f) }
        par = par.parent
    end
    return p, m, visible
end

function MOCK.exportScene()
    local V = require("vec")
    local out = {}
    for _, o in pairs(MOCK.objects) do
        if o.kind ~= "empty" and not o.kind:find("^ui_") then
            local p, m, vis = worldMatrix(o, V)
            if vis then
                out[#out + 1] = string.format(
                    '{"k":"%s","p":[%.4f,%.4f,%.4f],"r":[%.5f,%.5f,%.5f],"u":[%.5f,%.5f,%.5f],"f":[%.5f,%.5f,%.5f],"c":[%.3f,%.3f,%.3f,%.3f],"t":%s,"e":%s,"m":%s}',
                    o.kind, p[1], p[2], p[3], m.r[1], m.r[2], m.r[3], m.u[1], m.u[2], m.u[3], m.f[1], m.f[2], m.f[3],
                    o.color[1], o.color[2], o.color[3], o.color[4],
                    o.tex and ('"' .. o.tex .. '"') or "null",
                    (o.material and o.material._EmissionColor) and string.format("[%.3f,%.3f,%.3f]", o.material._EmissionColor[1], o.material._EmissionColor[2], o.material._EmissionColor[3]) or "null",
                    (o.material and o.material._Metallic) and string.format("%.2f", o.material._Metallic) or "null")
            end
        end
    end
    local hp = MOCK.head.pos
    local q = MOCK.head.q
    return '{"head":[' .. hp[1] .. ',' .. hp[2] .. ',' .. hp[3] .. '],"q":[' .. q[1] .. ',' .. q[2] .. ',' .. q[3] .. ',' .. q[4] .. '],"objs":[' .. table.concat(out, ",") .. ']}'
end

function MOCK.countObjects()
    local n = 0
    for _ in pairs(MOCK.objects) do n = n + 1 end
    return n
end
