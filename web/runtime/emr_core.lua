-- emr_core.lua — EMRAPI do EnJoyTheMR reimplementada para o NAVEGADOR.
-- Os jogos (scripts/*.lua) rodam SEM NENHUMA MUDANCA: este arquivo oferece a mesma API
-- (EMRAPI.Scene, Input, Audio, UI, Timer, Tween, Storage, Multiplayer... e o "CS" da Unity
-- que os jogos usam) e conversa com o host JavaScript (host.js) pelas funcoes H_*.
--
-- Convencao: tudo aqui esta no sistema de coordenadas da Unity (mao esquerda);
-- o host converte para o three.js.

local EMR = { time = 0, dt = 1 / 60, head = { 0, 0, 0, 0, 0, 0, 1 }, frame = 0 }
EMR_STATE = EMR

local function warn(msg) H_log(2, tostring(msg)) end

---------------------------------------------------------------------------
-- GameObject
---------------------------------------------------------------------------
local GO = {}
GO.__index = GO
local objs = {}            -- id -> GameObject (para Find e callbacks)

local function vec3(x, y, z) return { x = x, y = y, z = z } end

local function newGO(id, kind, name)
    local o = setmetatable({ id = id, kind = kind, name = name or kind }, GO)
    objs[id] = o
    return o
end

-- transform: so o que os jogos usam (localPosition/localRotation, position)
local TF = {}
TF.__index = function(t, k)
    local id = rawget(t, "_id")
    if k == "localPosition" then return vec3(H_getpos(id)) end
    if k == "position" then return vec3(H_getwpos(id)) end
    if k == "localRotation" then
        local x, y, z, w = H_getrot(id)
        return { x = x, y = y, z = z, w = w }
    end
    if k == "localScale" then
        local _, _, _, _, _, _, sx, sy, sz = H_gettrs(id)
        return vec3(sx, sy, sz)
    end
    return nil
end
TF.__newindex = function(t, k, v)
    local id = rawget(t, "_id")
    if k == "localPosition" then H_pos(id, v.x, v.y, v.z)
    elseif k == "localScale" then H_scale(id, v.x, v.y, v.z) end
end

GO.__index = function(o, k)
    if k == "transform" then
        local t = setmetatable({ _id = rawget(o, "id") }, TF)
        rawset(o, "transform", t)
        return t
    end
    if k == "gameObject" then return o end
    return GO[k]
end

function GO:SetActive(v) H_active(self.id, v and true or false) end
function GO:IsActive() return H_isactive(self.id) end

-- material (proxy) — o que a Unity Standard/URP aceita e os jogos usam
local MAT = {}
MAT.__index = function(m, k)
    if k == "SetFloat" then
        return function(_, prop, v)
            if prop == "_Metallic" then H_mat(m._id, "metal", v, 0, 0)
            elseif prop == "_Glossiness" or prop == "_Smoothness" then H_mat(m._id, "smooth", v, 0, 0) end
        end
    elseif k == "SetColor" then
        return function(_, prop, c)
            if prop == "_EmissionColor" then H_mat(m._id, "emit", c.r or 0, c.g or 0, c.b or 0)
            elseif prop == "_Color" or prop == "_BaseColor" then H_color(m._id, c.r, c.g, c.b, c.a or 1) end
        end
    elseif k == "EnableKeyword" or k == "DisableKeyword" then
        return function() end
    elseif k == "shader" then
        return rawget(m, "_shader")
    end
    return nil
end
MAT.__newindex = function(m, k, v)
    if k == "shader" then
        rawset(m, "_shader", v)
        if v and v.unlit then H_mat(m._id, "unlit", 1, 0, 0) end
    elseif k == "mainTextureScale" then
        H_mat(m._id, "tiling", v.x, v.y, 0)
    elseif k == "color" then
        H_color(m._id, v.r, v.g, v.b, v.a or 1)
    end
end

local REND = {}
REND.__index = function(r, k)
    if k == "material" or k == "sharedMaterial" then return rawget(r, "_mat") end
    return nil
end
REND.__newindex = function(r, k, v)
    if k == "shadowCastingMode" then H_mat(r._id, "noshadow", (v == 0) and 1 or 0, 0, 0)
    elseif k == "receiveShadows" then H_mat(r._id, "recvshadow", v and 1 or 0, 0, 0) end
end

-- Rigidbody (proxy)
local RB = {}
RB.__index = function(rb, k)
    local id = rawget(rb, "_id")
    if k == "velocity" or k == "linearVelocity" then return vec3(H_getvel(id)) end
    if k == "angularVelocity" then return vec3(H_getang(id)) end
    if k == "isKinematic" then return rawget(rb, "_kin") or false end
    if k == "AddForce" then
        return function(_, f, mode) H_force(id, f.x, f.y, f.z, (mode == 1) and 1 or 0) end
    end
    if k == "MovePosition" then return function(_, p) H_pos(id, p.x, p.y, p.z) end end
    return nil
end
RB.__newindex = function(rb, k, v)
    local id = rawget(rb, "_id")
    if k == "velocity" or k == "linearVelocity" then H_setvel(id, v.x, v.y, v.z)
    elseif k == "angularVelocity" then H_setang(id, v.x, v.y, v.z)
    elseif k == "isKinematic" then rawset(rb, "_kin", v and true or false); H_kin(id, v and true or false)
    elseif k == "useGravity" then H_grav(id, v and true or false)
    elseif k == "mass" then H_mass(id, v) end
end

function GO:GetComponent(t)
    if self.kind == "empty" and (t == "Renderer" or t == "MeshRenderer") then return nil end
    if t == "Renderer" or t == "MeshRenderer" then
        local r = rawget(self, "_rend")
        if not r then
            r = setmetatable({ _id = self.id, _mat = setmetatable({ _id = self.id }, MAT) }, REND)
            rawset(self, "_rend", r)
        end
        return r
    end
    if t == "Rigidbody" then return rawget(self, "_rb") end
    if t == "Transform" then return self.transform end
    return nil
end

local function chk(o, fn)
    if type(o) ~= "table" or not rawget(o, "id") then error(fn .. ": GameObject invalido", 3) end
end

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------
local Scene = {}
local ROOT = newGO(H_root(), "empty", "AppRoot")
local PRIMS = { cube = 1, sphere = 1, capsule = 1, cylinder = 1, plane = 1, quad = 1 }

function Scene:GetRoot() return ROOT end
function Scene:CreatePrimitive(k)
    if not PRIMS[k] then return nil end
    return newGO(H_create(k), k)
end
function Scene:CreateObject(name) return newGO(H_create("empty"), "empty", name) end
function Scene:Find(name)
    for _, o in pairs(objs) do if o.name == name and not o.destroyed then return o end end
    return nil
end
function Scene:Destroy(o)
    if o == nil then return end
    chk(o, "Destroy")
    o.destroyed = true
    objs[o.id] = nil
    H_destroy(o.id)
end
function Scene:SetPosition(o, x, y, z) H_pos(o.id, x, y, z) end
function Scene:SetRotation(o, x, y, z) H_rot(o.id, x, y, z) end
function Scene:SetScale(o, x, y, z) H_scale(o.id, x, y, z) end
function Scene:SetColor(o, r, g, b, a) H_color(o.id, r, g, b, a or 1) end
function Scene:SetParent(c, p) H_parent(c.id, p and p.id or ROOT.id) end
function Scene:GetPositionX(o) local x = H_getpos(o.id); return x end
function Scene:GetPositionY(o) local _, y = H_getpos(o.id); return y end
function Scene:GetPositionZ(o) local _, _, z = H_getpos(o.id); return z end
function Scene:SetTexture(o, path) return H_tex(o.id, tostring(path)) end
function Scene:AddRigidbody(o, mass, grav)
    chk(o, "AddRigidbody")
    H_addbody(o.id, mass or 1, grav ~= false)
    local rb = setmetatable({ _id = o.id }, RB)
    rawset(o, "_rb", rb)
    return rb
end
function Scene:AddBoxCollider(o) chk(o, "AddBoxCollider"); H_collider(o.id, 1, 0); return {} end
function Scene:AddSphereCollider(o, r) chk(o, "AddSphereCollider"); H_collider(o.id, 2, r or 0.5); return {} end
function Scene:AttachToHead(o) H_headattach(o.id, true, 0, 0, 0.5) end
function Scene:AttachToHeadAt(o, x, y, z) H_headattach(o.id, true, x, y, z) end
function Scene:DetachFromHead(o) H_headattach(o.id, false, 0, 0, 0) end
function Scene:AttachToHand() end
function Scene:AttachToHandSmooth() end
function Scene:DetachFromHand() end
function Scene:LoadModel(path, cb) if cb then cb(nil, "GLB nao suportado na versao web") end end
function Scene:Spawn() return newGO(H_create("empty"), "empty") end
function Scene:SpawnAt() return newGO(H_create("empty"), "empty") end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local Input = {}
local SIDE = { left = 0, right = 1 }
local NAMED = { Wrist = 0, ThumbTip = 4, IndexTip = 8, MiddleTip = 12, RingTip = 16, PinkyTip = 20 }

function Input:IsHandTracked(s) return H_handok(SIDE[s] or 1) end
function Input:GetHandPosition(s, point)
    local side = SIDE[s] or 1
    local i = tonumber(point)
    if i then return H_joint(side, i) end
    if point == "PalmCenter" then
        local sx, sy, sz = 0, 0, 0
        for _, k in ipairs({ 0, 5, 9, 13, 17 }) do
            local x, y, z = H_joint(side, k)
            sx, sy, sz = sx + x, sy + y, sz + z
        end
        return sx / 5, sy / 5, sz / 5
    end
    return H_joint(side, NAMED[point] or 0)
end
function Input:GetHandPositionX(s, p) local x = Input:GetHandPosition(s, p or "PalmCenter"); return x end
function Input:GetHandRotation(s) return 0, 0, 0, 1 end
function Input:GetHandGesture(s) return H_gesture(SIDE[s] or 1) end
function Input:GetPinchStrength(s) return H_pinch(SIDE[s] or 1) end
function Input:IsGrabbing(s) return H_gesture(SIDE[s] or 1) == "Fist" end
function Input:GetHeadPositionX() return EMR.head[1] end
function Input:GetHeadPositionY() return EMR.head[2] end
function Input:GetHeadPositionZ() return EMR.head[3] end
function Input:GetHeadRotationX() return EMR.head[4] end
function Input:GetHeadRotationY() return EMR.head[5] end
function Input:GetHeadRotationZ() return EMR.head[6] end
function Input:GetHeadRotationW() return EMR.head[7] end

---------------------------------------------------------------------------
-- Timer / Tween
---------------------------------------------------------------------------
local timers, timerSeq = {}, 1
local Timer = {}
function Timer:Repeat(i, cb) timers[timerSeq] = { t = EMR.time + i, i = i, cb = cb, rep = true }; timerSeq = timerSeq + 1; return timerSeq - 1 end
function Timer:Delay(i, cb) timers[timerSeq] = { t = EMR.time + i, i = i, cb = cb, rep = false }; timerSeq = timerSeq + 1; return timerSeq - 1 end
function Timer:Cancel(id) if id then timers[id] = nil end end
local function tickTimers()
    local due = {}
    for id, t in pairs(timers) do
        if EMR.time >= t.t then due[#due + 1] = id end
    end
    table.sort(due)
    for _, id in ipairs(due) do
        local t = timers[id]
        if t then
            if t.rep then t.t = EMR.time + math.max(t.i, 0.001) else timers[id] = nil end
            local ok, err = pcall(t.cb)
            if not ok then H_log(3, "Timer: " .. tostring(err)) end
        end
    end
end

local tweens, tweenSeq = {}, 1
local Tween = {}
local function addTween(kind, o, x, y, z, d, cb)
    chk(o, "Tween")
    local px, py, pz, rx, ry, rz, sx, sy, sz = H_gettrs(o.id)
    local from = kind == "move" and { px, py, pz } or (kind == "scale" and { sx, sy, sz } or { rx, ry, rz })
    if not d or d <= 0 then
        if kind == "move" then H_pos(o.id, x, y, z) elseif kind == "scale" then H_scale(o.id, x, y, z) else H_rot(o.id, x, y, z) end
        if cb then cb() end
        return -1
    end
    for id, tw in pairs(tweens) do if tw.o == o and tw.kind == kind then tweens[id] = nil end end
    tweens[tweenSeq] = { o = o, kind = kind, from = from, to = { x, y, z }, t0 = EMR.time, d = d, cb = cb }
    tweenSeq = tweenSeq + 1
    return tweenSeq - 1
end
function Tween:MoveTo(o, x, y, z, d, cb) return addTween("move", o, x, y, z, d, cb) end
function Tween:ScaleTo(o, x, y, z, d, cb) return addTween("scale", o, x, y, z, d, cb) end
function Tween:RotateTo(o, x, y, z, d, cb) return addTween("rot", o, x, y, z, d, cb) end
function Tween:Cancel(id) if id then tweens[id] = nil end end
function Tween:CancelAll() tweens = {} end
function Tween:IsRunning(id) return tweens[id] ~= nil end
local function tickTweens()
    for id, tw in pairs(tweens) do
        if tw.o.destroyed then tweens[id] = nil else
            local k = math.min(1, (EMR.time - tw.t0) / tw.d)
            local s = k * k * (3 - 2 * k)
            local f, t = tw.from, tw.to
            local x, y, z = f[1] + (t[1] - f[1]) * s, f[2] + (t[2] - f[2]) * s, f[3] + (t[3] - f[3]) * s
            if tw.kind == "move" then H_pos(tw.o.id, x, y, z) elseif tw.kind == "scale" then H_scale(tw.o.id, x, y, z) else H_rot(tw.o.id, x, y, z) end
            if k >= 1 then
                tweens[id] = nil
                if tw.cb then local ok, err = pcall(tw.cb); if not ok then H_log(3, "Tween: " .. tostring(err)) end end
            end
        end
    end
end

---------------------------------------------------------------------------
-- UI (paineis 3D desenhados pelo host)
---------------------------------------------------------------------------
local UI = {}
local uiCb = {}
local function uiEl(id, kind)
    local o = newGO(id, "ui_" .. kind)
    return o
end
function UI:CreatePanel(w, h) return uiEl(H_ui("panel", 0, "", w or 1, h or 1), "panel") end
function UI:CreateText(p, t) return uiEl(H_ui("text", p and p.id or 0, tostring(t or ""), 0, 0), "text") end
function UI:CreateButton(p, t, cb)
    local o = uiEl(H_ui("button", p and p.id or 0, tostring(t or ""), 0, 0), "button")
    uiCb[o.id] = cb
    return o
end
function UI:CreateImage(p, path) return uiEl(H_ui("image", p and p.id or 0, tostring(path or ""), 0, 0), "image") end
function UI:SetImage(el, path) H_uiset(el.id, "image", tostring(path), 0, 0, 0, 0) end
function UI:CreateInputField(p, placeholder, cb)
    local o = uiEl(H_ui("input", p and p.id or 0, tostring(placeholder or ""), 0, 0), "input")
    uiCb[o.id] = cb
    return o
end
function UI:CreateSlider(p, a, b, cb)
    local o = uiEl(H_ui("slider", p and p.id or 0, "", a or 0, b or 1), "slider")
    uiCb[o.id] = cb
    return o
end
function UI:CreateToggle(p, t, cb)
    local o = uiEl(H_ui("toggle", p and p.id or 0, tostring(t or ""), 0, 0), "toggle")
    uiCb[o.id] = cb
    return o
end
function UI:CreateScrollView(p, w, h) return uiEl(H_ui("scroll", p and p.id or 0, "", w or 1, h or 1), "scroll") end
function UI:SetColor(el, r, g, b, a) H_uiset(el.id, "color", "", r, g, b, a or 1) end
function UI:SetPosition(el, x, y, z) H_uiset(el.id, "pos", "", x, y, z or 0, 0) end
function UI:SetSize(el, w, h) H_uiset(el.id, "size", "", w, h, 0, 0) end
function UI:SetText(el, t)
    rawset(el, "text", tostring(t))
    H_uiset(el.id, "text", tostring(t), 0, 0, 0, 0)
end
function UI:GetText(el) return H_uitext(el.id) end
function UI:SetActive(el, v) H_uiset(el.id, "active", "", v and 1 or 0, 0, 0, 0) end
function UI:Destroy(el) uiCb[el.id] = nil; H_uiset(el.id, "destroy", "", 0, 0, 0, 0) end

-- chamado pelo host quando o jogador aperta algo no painel
function EMR_UI_EVENT(id, kind, value)
    local cb = uiCb[id]
    if not cb then return end
    local ok, err
    if kind == "button" then ok, err = pcall(cb)
    elseif kind == "toggle" then ok, err = pcall(cb, value ~= 0)
    elseif kind == "slider" then ok, err = pcall(cb, value)
    else ok, err = pcall(cb, value) end
    if not ok then H_log(3, "UI: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local JSON = {}
local function encVal(v, out)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "0"
        elseif math.type(v) == "integer" then out[#out + 1] = tostring(v)
        else out[#out + 1] = string.format("%.14g", v) end
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif t == "table" then
        local n = #v
        local isArr = n > 0 or next(v) == nil
        if isArr then for k in pairs(v) do if type(k) ~= "number" then isArr = false break end end end
        if isArr then
            out[#out + 1] = "["
            for i = 1, n do if i > 1 then out[#out + 1] = "," end encVal(v[i], out) end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, x in pairs(v) do
                if type(x) ~= "function" then
                    if not first then out[#out + 1] = "," end
                    first = false
                    out[#out + 1] = '"' .. tostring(k) .. '":'
                    encVal(x, out)
                end
            end
            out[#out + 1] = "}"
        end
    else out[#out + 1] = "null" end
end
function JSON.encode(v) local out = {} encVal(v, out) return table.concat(out) end
function JSON.decode(s)
    if type(s) ~= "string" then return nil end
    local pos = 1
    local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local val
    local function str()
        local out = {}
        pos = pos + 1
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local n = s:sub(pos + 1, pos + 1)
                if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16) or 63); pos = pos + 6
                else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n; pos = pos + 2 end
            else out[#out + 1] = c; pos = pos + 1 end
        end
        return table.concat(out)
    end
    function val()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while pos <= #s do
                ws(); local k = str(); ws(); pos = pos + 1
                t[k] = val(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d ~= "," then break end
            end
            return t
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while pos <= #s do
                t[#t + 1] = val(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d ~= "," then break end
            end
            return t
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local e = s:find("[,%]}%s]", pos) or #s + 1
            local n = tonumber(s:sub(pos, e - 1)); pos = e
            return n
        end
    end
    local ok, r = pcall(val)
    if ok then return r end
    return nil
end

---------------------------------------------------------------------------
-- Storage (localStorage, isolado por id do app)
---------------------------------------------------------------------------
local Storage = {}
local function sget(k) return H_sget(tostring(k)) end
function Storage:Set(k, v) H_sset(tostring(k), "s" .. tostring(v)) end
function Storage:SetString(k, v) H_sset(tostring(k), "s" .. tostring(v)) end
function Storage:GetString(k, d)
    local v = sget(k)
    if v == nil then return d end
    return v:sub(2)
end
function Storage:SetNumber(k, v) H_sset(tostring(k), "n" .. string.format("%.17g", v)) end
function Storage:GetNumber(k, d)
    local v = sget(k)
    if v == nil then return d end
    return tonumber(v:sub(2)) or d
end
function Storage:SetBool(k, v) H_sset(tostring(k), "b" .. (v and "1" or "0")) end
function Storage:GetBool(k, d)
    local v = sget(k)
    if v == nil then return d end
    local b = v:sub(2)
    return b == "1" or b == "true"
end
function Storage:HasKey(k) return sget(k) ~= nil end
function Storage:Remove(k) H_sdel(tostring(k)) end
function Storage:Delete(k) H_sdel(tostring(k)) end
function Storage:Save() H_ssave() end

---------------------------------------------------------------------------
-- Audio
---------------------------------------------------------------------------
local Audio = {}
function Audio:Play(path) return H_aplay(tostring(path), 0, 0, 0, 0, 0) end
function Audio:PlayAtPoint(path, x, y, z) return H_aplay(tostring(path), 1, x, y, z, 0) end
function Audio:PlayLoop(path) return H_aplay(tostring(path), 0, 0, 0, 0, 1) end
function Audio:Stop(id) H_astop(id or 0) end
function Audio:SetVolume(a, b)
    if b == nil then H_amaster(a) else H_aset(a, "vol", b) end
end
function Audio:SetPitch(id, p) H_aset(id, "pitch", p) end
function Audio:SetLoop(id, l) H_aset(id, "loop", l and 1 or 0) end
function Audio:IsPlaying(id) return H_aplaying(id or 0) end

---------------------------------------------------------------------------
-- Resto
---------------------------------------------------------------------------
local Hands = {}
function Hands:SetVisible() end
function Hands:Reset() end
function Hands:SetColor() end
function Hands:SetAlpha() end
function Hands:IsVisible() return false end

local Camera = {}
function Camera:SetBackground(m) EMR.bg = m; H_bg(tostring(m)) end
function Camera:GetBackground() return EMR.bg or "hide" end
function Camera:Reset() H_bg("hide") end

local Keyboard = {}
function Keyboard:Show() end
function Keyboard:Hide() end
function Keyboard:Reset() end

EMRAPI = {
    Log = function(_, m) H_log(1, tostring(m)) end,
    LogWarning = function(_, m) H_log(2, tostring(m)) end,
    LogError = function(_, m) H_log(3, tostring(m)) end,
    App = {
        id = H_appid(), displayMode = "scene",
        RequestExit = function() H_exit() end,
        GetName = function() return H_appname() end,
    },
    System = {
        GetTime = function() return EMR.time end,
        GetDeltaTime = function() return EMR.dt end,
        GetPlatform = function() return "web" end,
        GetTrackingMode = function() return H_tracking() end,
    },
    Math = {
        Random = function(_, a, b) return a + math.random() * (b - a) end,
        Lerp = function(_, a, b, t) return a + (b - a) * t end,
        Clamp = function(_, v, a, b) return math.max(a, math.min(b, v)) end,
        Distance = function(_, a, b, c, d, e, f) return math.sqrt((a - d) ^ 2 + (b - e) ^ 2 + (c - f) ^ 2) end,
    },
    Scene = Scene, Input = Input, Timer = Timer, Tween = Tween, UI = UI, Audio = Audio,
    Storage = Storage, Hands = Hands, Camera = Camera, Keyboard = Keyboard,
    Json = { Encode = function(_, v) return JSON.encode(v) end, Decode = function(_, s) return JSON.decode(s) end },
}

---------------------------------------------------------------------------
-- Multiplayer (Photon via host) — so existe se o app pedir a permissao
---------------------------------------------------------------------------
local mp = { handlers = {}, cbs = {}, seq = 0 }
local function mpcb(cb)
    mp.seq = mp.seq + 1
    mp.cbs[mp.seq] = cb
    return mp.seq
end
local MP = {}
function MP:Connect(cb) H_mp("connect", "", mpcb(cb), 0) end
function MP:ConnectWithAppId(id, cb) H_mp("connectid", tostring(id), mpcb(cb), 0) end
function MP:Disconnect() H_mp("disconnect", "", 0, 0) end
function MP:IsConnected() return H_mpq("connected") == "1" end
function MP:GetState() return H_mpq("state") end
function MP:OnDisconnected(cb) mp.onDisc = cb end
function MP:SetNickname(n) H_mp("nick", tostring(n), 0, 0) end
function MP:SetAvatarsEnabled(v) mp.avatars = v end
function MP:CreateRoom(name, n, cb) H_mp("create", tostring(name), mpcb(cb), n or 8) end
function MP:JoinRoom(name, cb) H_mp("join", tostring(name), mpcb(cb), 0) end
function MP:JoinOrCreateRoom(name, n, cb) H_mp("joinorcreate", tostring(name), mpcb(cb), n or 8) end
function MP:JoinRandomOrCreateRoom(n, cb) H_mp("random", "", mpcb(cb), n or 8) end
function MP:LeaveRoom(cb) H_mp("leave", "", mpcb(cb), 0) end
function MP:GetRoomList(cb) H_mp("roomlist", "", mpcb(cb), 0) end
function MP:IsInRoom() return H_mpq("inroom") == "1" end
function MP:GetRoomName() return H_mpq("room") end
function MP:GetPlayerCount() return tonumber(H_mpq("count")) or 0 end
function MP:IsMaster() return H_mpq("master") == "1" end
function MP:GetLocalActor() return tonumber(H_mpq("actor")) or -1 end
function MP:GetPlayers() return H_mpq("players") end
function MP:OnPlayerJoined(cb) mp.onJoin = cb end
function MP:OnPlayerLeft(cb) mp.onLeft = cb end
function MP:OnMasterChanged(cb) mp.onMaster = cb end
function MP:SendEvent(kind, json) H_mp("send", tostring(kind), 0, 0, tostring(json or "")) end
function MP:SendEventToAll(kind, json)
    H_mp("send", tostring(kind), 0, 0, tostring(json or ""))
    local h = mp.handlers[kind]
    if h then pcall(h, MP:GetLocalActor(), json) end
end
function MP:SendEventTo(actor, kind, json) H_mp("sendto", tostring(kind), actor, 0, tostring(json or "")) end
function MP:OnEvent(kind, cb) mp.handlers[kind] = cb end
function MP:OffEvent(kind) mp.handlers[kind] = nil end
function MP:SetRoomProperty(k, v) H_mp("roomprop", tostring(k), 0, 0, tostring(v)) end
function MP:GetRoomProperty(k) return H_mpq("roomprop:" .. tostring(k)) end
function MP:SetPlayerProperty(k, v) H_mp("playerprop", tostring(k), 0, 0, tostring(v)) end
function MP:GetPlayerProperty(a, k) return H_mpq("playerprop:" .. tostring(a) .. ":" .. tostring(k)) end
function MP:OnRoomPropertyChanged(cb) mp.onRoomProp = cb end
function MP:OnPlayerPropertyChanged(cb) mp.onPlayerProp = cb end
function MP:SetSyncRate() end
function MP:SpawnSynced() return nil end
function MP:SetVoiceEnabled(v) return "voz nao disponivel na versao web" end
function MP:IsVoiceEnabled() return false end
function MP:SetVoiceVad() end
function MP:MutePlayer() end
function MP:IsPlayerMuted() return false end
function MP:OnPlayerSpeaking() end

-- eventos que o host juntou desde o ultimo frame
local function pollMP()
    while true do
        local kind, a, b, c = H_mppoll()
        if kind == nil then break end
        local ok, err = true, nil
        if kind == "cb" then
            local cb = mp.cbs[a]
            mp.cbs[a] = nil
            if cb then ok, err = pcall(cb, b == "1", c ~= "" and c or nil) end
        elseif kind == "event" then
            local h = mp.handlers[b]
            if h then ok, err = pcall(h, a, c) end
        elseif kind == "join" then
            if mp.onJoin then ok, err = pcall(mp.onJoin, a, b) end
        elseif kind == "left" then
            if mp.onLeft then ok, err = pcall(mp.onLeft, a, b) end
        elseif kind == "master" then
            if mp.onMaster then ok, err = pcall(mp.onMaster, a) end
        elseif kind == "disconnected" then
            if mp.onDisc then ok, err = pcall(mp.onDisc, b) end
        elseif kind == "roomprop" then
            if mp.onRoomProp then ok, err = pcall(mp.onRoomProp, b, c) end
        elseif kind == "playerprop" then
            if mp.onPlayerProp then ok, err = pcall(mp.onPlayerProp, a, b, c) end
        end
        if not ok then H_log(3, "Multiplayer: " .. tostring(err)) end
    end
end

if H_hasperm("multiplayer") then EMRAPI.Multiplayer = MP end
if not H_hasperm("network") then EMRAPI.Network = nil end

---------------------------------------------------------------------------
-- "CS" (Unity via xLua): so as partes que os jogos usam
---------------------------------------------------------------------------
local names = setmetatable({}, {
    __index = function(_, k)
        local list = EMR.joyNames or {}
        if k == "Length" then return #list end
        if type(k) == "number" then return list[k + 1] end
        return nil
    end,
})
local RenderSettings = setmetatable({}, {
    __newindex = function(_, k, v)
        if k == "ambientLight" then H_ambient(v.r, v.g, v.b) end
    end,
})
CS = {
    UnityEngine = {
        Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end,
        Vector3 = function(x, y, z) return vec3(x, y, z) end,
        Vector2 = function(x, y) return { x = x, y = y } end,
        ForceMode = { Force = 0, Impulse = 1, VelocityChange = 2, Acceleration = 5 },
        Rendering = { ShadowCastingMode = { Off = 0, On = 1 } },
        Shader = {
            Find = function(n)
                if n == "Sprites/Default" or n == "Unlit/Transparent" or n == "Unlit/Texture" or n == "Universal Render Pipeline/Unlit" then
                    return { name = n, unlit = true }
                end
                if n == "Standard" then return { name = n } end
                return nil
            end,
        },
        RenderSettings = RenderSettings,
        Input = {
            GetKey = function(name) return H_key(tostring(name)) end,
            GetKeyDown = function(name) return H_key(tostring(name)) end,
            GetAxis = function(n) return H_axis(tostring(n)) end,
            GetJoystickNames = function()
                local s = H_joynames()
                local list = {}
                for n in s:gmatch("[^\n]+") do list[#list + 1] = n end
                EMR.joyNames = list
                return names
            end,
        },
    },
}

---------------------------------------------------------------------------
-- Ciclo de vida (chamado pelo host)
---------------------------------------------------------------------------
function EMR_START()
    if OnStart then
        local ok, err = xpcall(OnStart, debug.traceback)
        if not ok then H_log(3, "OnStart: " .. tostring(err)) end
    end
end

function EMR_FRAME(dt, t)
    EMR.dt = dt
    EMR.time = t
    EMR.frame = EMR.frame + 1
    local h = EMR.head
    h[1], h[2], h[3], h[4], h[5], h[6], h[7] = H_head()
    pollMP()
    tickTimers()
    tickTweens()
    if OnUpdate then
        local ok, err = xpcall(OnUpdate, debug.traceback, dt)
        if not ok then H_log(3, "OnUpdate: " .. tostring(err)) end
    end
end

function EMR_PAUSE(p)
    local fn = p and OnPause or OnResume
    if fn then pcall(fn) end
end

function EMR_DESTROY()
    if OnDestroy then pcall(OnDestroy) end
end

return EMR
