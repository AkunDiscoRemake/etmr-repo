-- net.lua — camada de rede. "solo" (com bots, sem internet) ou "online" (Photon via
-- EMRAPI.Multiplayer). Todo o jogo fala com a rede so por aqui: send / on.
-- As mensagens sao tabelas Lua viradas JSON.

local A = require("api")

local N = {}

N.mode = "solo"
N.state = "offline"      -- offline | connecting | inroom | failed
N.localId = "me"
N.actor = -1
N.handlers = {}
N.lastError = ""
N.ROOM_SIZE = 8

local MP = nil
local G

function N.init(ctx)
    G = ctx
    local ok, mp = pcall(function() return EMRAPI.Multiplayer end)
    MP = ok and mp or nil
end

function N.available() return MP ~= nil end
function N.online() return N.mode == "online" and N.state == "inroom" end

local function enc(t)
    local ok, s = pcall(function() return EMRAPI.Json:Encode(t) end)
    return ok and s or "{}"
end
local function dec(s)
    local ok, t = pcall(function() return EMRAPI.Json:Decode(s) end)
    if ok and type(t) == "table" then return t end
    return nil
end

function N.on(kind, fn)
    N.handlers[kind] = fn
end

-- tipos de mensagem que o jogo usa (registrados no MP de uma vez)
N.TYPES = { "hello", "assign", "pose", "base", "conv", "conv_sold", "buy_req", "steal_warn",
    "steal_req", "steal_ok", "steal_no", "steal_drop", "steal_done", "steal_cancel", "hit", "world", "fx", "bye" }

local function dispatch(kind, sender, json)
    local fn = N.handlers[kind]
    if not fn then return end
    local t = dec(json)
    if not t then return end
    local ok, err = pcall(fn, sender, t)
    if not ok then A.warnOnce("net_" .. kind, "rede " .. kind .. ": " .. tostring(err)) end
end

function N.send(kind, t)
    if not N.online() then return end
    pcall(function() MP:SendEvent(kind, enc(t)) end)
end

function N.isMaster()
    if not N.online() then return true end
    local ok, m = pcall(function() return MP:IsMaster() end)
    return ok and m
end

function N.players()
    if not N.online() then return {} end
    local ok, js = pcall(function() return MP:GetPlayers() end)
    if not ok then return {} end
    return dec(js) or {}
end

function N.playerCount()
    if not N.online() then return 1 end
    local ok, n = pcall(function() return MP:GetPlayerCount() end)
    return ok and n or 1
end

function N.roomName()
    if not N.online() then return "" end
    local ok, n = pcall(function() return MP:GetRoomName() end)
    return ok and n or ""
end

-- conecta e entra numa sala. cb(ok, err)
function N.connect(nick, cb)
    if not MP then cb(false, "no_mp"); return end
    N.state = "connecting"
    local function fail(err)
        N.state = "failed"
        N.lastError = tostring(err or "?")
        cb(false, N.lastError)
    end
    local ok, err = pcall(function()
        MP:SetNickname(nick)
        pcall(function() MP:SetAvatarsEnabled(false) end)
        for _, k in ipairs(N.TYPES) do
            MP:OnEvent(k, function(sender, json) dispatch(k, sender, json) end)
        end
        MP:OnPlayerJoined(function(actor, name)
            if N.handlers._joined then pcall(N.handlers._joined, actor, name) end
        end)
        MP:OnPlayerLeft(function(actor, name)
            if N.handlers._left then pcall(N.handlers._left, actor, name) end
        end)
        pcall(function()
            MP:OnMasterChanged(function(actor)
                if N.handlers._master then pcall(N.handlers._master, actor) end
            end)
        end)
        MP:OnDisconnected(function(reason)
            N.state = "offline"
            N.mode = "solo"
            if N.handlers._disconnected then pcall(N.handlers._disconnected, reason) end
        end)
        MP:Connect(function(okc, errc)
            if not okc then fail(errc); return end
            MP:JoinRandomOrCreateRoom(N.ROOM_SIZE, function(okj, errj)
                if not okj then fail(errj); return end
                N.mode = "online"
                N.state = "inroom"
                N.actor = MP:GetLocalActor()
                N.localId = "a" .. tostring(N.actor)
                cb(true)
            end)
        end)
    end)
    if not ok then fail(err) end
end

function N.leave()
    if MP and N.mode == "online" then
        pcall(function() MP:LeaveRoom(function() end) end)
        pcall(function() MP:Disconnect() end)
    end
    N.mode = "solo"
    N.state = "offline"
    N.localId = "me"
    N.actor = -1
end

-- voz (opcional, so se o app tiver Voice AppId)
function N.setVoice(on)
    if not N.online() then return "offline" end
    local ok, res = pcall(function() return MP:SetVoiceEnabled(on) end)
    return ok and tostring(res) or "erro"
end

return N
