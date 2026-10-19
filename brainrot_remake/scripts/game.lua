-- game.lua — o "cerebro" do jogo: sessao solo/online, regras de comprar/roubar/entregar,
-- pancadas, trancar base, loja de itens, renascer, prompts, tutorial, salvar e o menu.

local V = require("vec")
local A = require("api")
local K = require("catalog")
local Lt = require("layout")
local Tx = require("text3d")
local L10 = require("i18n")

local Gm = {}

local G
local ui = {}
local tut = {}
local saveT = 0
local poseT, baseT = 0, 0
local shopDisp = {}

Gm.mode = "boot"

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local function myEnt() return G.localEnt end
local function isAuthBase(b) return G.bases.list[b] and G.bases.list[b].auth end
local function online() return G.net.online() end
local function master() return G.net.isMaster() end

local function ownerIsLocal(b) return G.bases.list[b].owner == G.localId end

local function voice(id, pos)
    G.sound3D("sounds/voice/" .. id .. ".wav", pos, 1)
end

---------------------------------------------------------------------------
-- Comprar na esteira
---------------------------------------------------------------------------
-- ent compra o item `it`. Retorna true se o pedido foi aceito/enviado.
function Gm.buy(ent, it)
    if not it or not G.conveyor.items[it.uid] then return false end
    if online() and not master() then
        G.net.send("buy_req", { u = it.uid, by = ent.id, b = ent.base })
        it.requested = true
        return true
    end
    G.conveyor.sold(it.uid, ent.id, ent.base)
    G.net.send("conv_sold", { u = it.uid, by = ent.id, b = ent.base })
    if ent == myEnt() then
        G.player.spend(it.price)
        G.player.stats.bought = G.player.stats.bought + 1
        G.sound("sounds/buy.wav", 0.9)
        voice(it.id, { 0, 1, it.z })
        Gm.tutorial("bought")
    end
    return true
end

-- o brainrot comprado chegou na base
function Gm.onWalkerArrived(w)
    if isAuthBase(w.b) then
        local s = G.bases.add(w.b, w.id, w.mut)
        if s and ownerIsLocal(w.b) then
            G.sound3D("sounds/place.wav", Lt.slotPos(w.b, s), 1)
            Gm.save()
        elseif not s and ownerIsLocal(w.b) then
            -- base encheu no caminho: devolve metade do valor
            G.player.addMoney(K.sellValue(w.id, w.mut))
        end
    end
end

---------------------------------------------------------------------------
-- Roubar
---------------------------------------------------------------------------
function Gm.alarm(b, byName)
    if not ownerIsLocal(b) then return end
    G.hud.toast("alert_steal", 3.5, byName or "", { 1, 0.4, 0.4 })
    G.sound("sounds/alarm.wav", 1)
    Gm.tutorial("robbed")
end

function Gm.stealStart(ent, b, s)
    ent.stealing = { b = b, s = s, t = G.realTime }
    if ownerIsLocal(b) and ent ~= myEnt() then
        Gm.alarm(b, ent.name)
    elseif online() and not isAuthBase(b) then
        G.net.send("steal_warn", { b = b, s = s, by = ent.id, n = ent.name })
    end
end

function Gm.stealCancel(ent)
    local st = ent.stealing
    ent.stealing = nil
    if st and online() and not isAuthBase(st.b) then
        G.net.send("steal_cancel", { b = st.b, s = st.s, by = ent.id })
    end
end

local function grantSteal(ent, b, s)
    local slot = G.bases.list[b].slots[s]
    if not slot or slot.c then return false end
    G.bases.setCarried(b, s, ent.id)
    G.ents.setCarry(ent, b, s, slot.id, slot.mut)
    return true
end

function Gm.stealComplete(ent, b, s)
    ent.stealing = nil
    if isAuthBase(b) then
        if grantSteal(ent, b, s) then Gm.onStealGranted(ent, b, s) end
    else
        G.net.send("steal_req", { b = b, s = s, by = ent.id })
        ent.pendingSteal = { b = b, s = s, t = G.realTime }
    end
end

function Gm.onStealGranted(ent, b, s)
    local carry = ent.carry
    if ent == myEnt() then
        G.sound("sounds/steal.wav", 1)
        G.hud.toast("stolen_ok", 2.5)
        if carry then voice(carry.id, G.rig.head) end
    elseif ownerIsLocal(b) then
        G.hud.toast("alert_stolen", 3.5, ent.name, { 1, 0.4, 0.4 })
        G.sound("sounds/alarm.wav", 1)
    end
end

-- solta o brainrot (levou pancada, caiu na lava...) -> volta para a base de origem
function Gm.dropCarry(ent)
    local c = ent.carry
    if not c then return end
    if isAuthBase(c.b) then
        G.bases.setCarried(c.b, c.s, nil)
        if ownerIsLocal(c.b) and ent ~= myEnt() then
            G.hud.toast("recovered", 2.5)
            G.sound("sounds/recover.wav", 1)
        end
    else
        G.net.send("steal_drop", { b = c.b, s = c.s, by = ent.id })
    end
    if ent == myEnt() then G.sound("sounds/drop.wav", 1) end
    G.fx.sparkle(V.add(ent.pos, { 0, 2.2, 0 }), { 1, 1, 1 }, 10)
    G.ents.clearCarry(ent)
end

-- chegou em casa com o brainrot
function Gm.deliver(ent)
    local c = ent.carry
    if not c then return false end
    local home = ent.base
    if not home or not isAuthBase(home) then return false end
    local s2 = G.bases.freeSlot(home)
    if not s2 then return false end
    G.ents.clearCarry(ent)
    G.bases.add(home, c.id, c.mut, s2)
    if isAuthBase(c.b) then
        G.bases.remove(c.b, c.s)
    else
        G.net.send("steal_done", { b = c.b, s = c.s, by = ent.id })
    end
    if ent == myEnt() then
        G.player.stats.stolen = G.player.stats.stolen + 1
        G.sound("sounds/success.wav", 1)
        G.fx.confetti(V.add(Lt.slotPos(home, s2), { 0, 1, 0 }), 40)
        voice(c.id, Lt.slotPos(home, s2))
        G.hud.toast("stolen_home", 2.5)
        Gm.save()
    elseif ownerIsLocal(c.b) then
        G.hud.toast("alert_lost", 3.5, ent.name, { 1, 0.4, 0.4 })
        Gm.save()
    end
    return true
end

---------------------------------------------------------------------------
-- Pancadas
---------------------------------------------------------------------------
function Gm.hitEnt(target, dir, pow, stun, byId)
    G.fx.hit(V.add(target.pos, { 0, 1.3, 0 }))
    if target.auth then
        if target == myEnt() then
            G.player.onHit(dir, pow, stun)
        else
            G.ents.applyHit(target, dir, pow, stun)
            if target.stealing then target.stealing = nil end
            Gm.dropCarry(target)
            G.ai.onHit(target.id, byId)
        end
    else
        G.net.send("hit", { to = target.id, d = { dir[1], dir[3] }, p = pow, s = stun, by = byId })
    end
end

---------------------------------------------------------------------------
-- Trava
---------------------------------------------------------------------------
function Gm.lockBase(b)
    if not isAuthBase(b) or G.bases.isLocked(b) then return end
    G.bases.lock(b)
    G.sound3D("sounds/lock.wav", Lt.lockPos(b), 1)
end

function Gm.lockMyBase()
    if not G.myBase or G.bases.isLocked(G.myBase) then return end
    Gm.lockBase(G.myBase)
    G.hud.toast("base_locked", 2.5)
end

function Gm.onUnlock(b)
    if ownerIsLocal(b) then
        G.hud.toast("base_unlocked", 2.5)
        G.sound("sounds/unlock.wav", 0.8)
    end
end

---------------------------------------------------------------------------
-- Loja e renascer
---------------------------------------------------------------------------
local function buyGear(k)
    local Pl = G.player
    local it = Pl.ITEMS[k]
    if k == "trap" then
        if not Pl.spend(it.price) then return end
        Pl.owned.trap = true
        Pl.traps = Pl.traps + it.uses
    else
        if Pl.owned[k] or not Pl.spend(it.price) then return end
        Pl.owned[k] = true
    end
    G.sound("sounds/buy.wav", 1)
    G.fx.confetti(V.add(G.world.shop.stands[1], { 0, 0.3, 0 }), 20)
    Pl.equip(k)
    Gm.save()
end

function Gm.rebirthCost()
    return 1000000 * (5 ^ G.player.rebirths)
end

local function rebirth()
    local Pl = G.player
    local cost = Gm.rebirthCost()
    if Pl.money < cost then return end
    Pl.money = 0
    Pl.rebirths = Pl.rebirths + 1
    G.bases.list[G.myBase].rebirths = Pl.rebirths
    for s = 1, Lt.SLOTS do
        local slot = G.bases.list[G.myBase].slots[s]
        if slot and not slot.c then G.bases.remove(G.myBase, s) end
    end
    Pl.money = 500 * Pl.rebirths
    G.fx.confetti(V.add(Lt.REBIRTH, { 0, 2, 0 }), 60)
    G.sound("sounds/rebirth.wav", 1)
    G.hud.toast("rebirth_done", 4, "x" .. string.format("%.1f", 1 + 0.5 * Pl.rebirths))
    Gm.save()
end

---------------------------------------------------------------------------
-- Prompts do jogador local
---------------------------------------------------------------------------
local function offerPrompts(feet)
    local P = G.prompts
    local Pl = G.player
    local me = myEnt()
    if not me or not G.myBase then return end
    local carrying = me.carry ~= nil
    local my = G.myBase
    local fullMine = (G.bases.count(my) + G.conveyor.pendingFor(my)) >= Lt.SLOTS
    -- esteira
    local it, d = G.conveyor.nearest(feet, 2.6)
    if it and not it.requested then
        local ok, why = true, nil
        if carrying then ok, why = false, "carry"
        elseif fullMine then ok, why = false, "full"
        elseif Pl.money < it.price then ok, why = false, "money" end
        P.offer({
            key = "cv" .. it.uid, pos = { 0, 0, it.z }, cardPos = { 0, 0.55 + it.inst.size * 1.25 + 0.55, it.z },
            kind = "buy", hold = 0.6, ok = ok, why = why, info = "$" .. K.fmt(it.price),
            infoColor = ok and { 1, 0.9, 0.3 } or { 1, 0.4, 0.4 }, range = 2.6,
            done = function() Gm.buy(me, it) end,
        })
    end
    -- bases
    local bi = Lt.baseAt(feet)
    if bi and G.bases.list[bi].owner then
        for s = 1, Lt.SLOTS do
            local slot = G.bases.list[bi].slots[s]
            if slot and not slot.c then
                local sp = Lt.slotPos(bi, s)
                local top = G.bases.slotTop(bi, s)
                if bi == my then
                    local v = K.sellValue(slot.id, slot.mut)
                    P.offer({
                        key = "sell" .. s, pos = sp, cardPos = V.add(top, { 0, 0.75, 0 }), kind = "sell", hold = 3.0, minDot = 0.75,
                        ok = true, info = "+$" .. K.fmt(v), infoColor = { 0.5, 1, 0.5 }, range = 1.6, prio = -0.5,
                        done = function()
                            if G.bases.list[my].slots[s] == slot then
                                G.bases.remove(my, s)
                                Pl.addMoney(v, top)
                                G.sound("sounds/cash.wav", 1)
                                Gm.save()
                            end
                        end,
                    })
                else
                    local ok, why = true, nil
                    if carrying then ok, why = false, "carry"
                    elseif not G.bases.freeSlot(my) then ok, why = false, "full" end
                    P.offer({
                        key = "st" .. bi .. ":" .. s, pos = sp, cardPos = V.add(top, { 0, 0.75, 0 }), kind = "steal", hold = 5.0,
                        ok = ok, why = why, info = K.byId[slot.id].name:upper():sub(1, 22), infoColor = { 1, 1, 1 }, range = 1.9,
                        start = function() Gm.stealStart(me, bi, s) end,
                        cancel = function() Gm.stealCancel(me) end,
                        tick = function() G.sound("sounds/tick.wav", 0.35) end,
                        done = function() Gm.stealComplete(me, bi, s) end,
                    })
                end
            end
        end
    end
    -- loja
    for k, key in ipairs(Pl.ORDER) do
        local sp = G.world.shop.stands[k]
        local item = Pl.ITEMS[key]
        local owned = Pl.owned[key] and key ~= "trap"
        if owned then
            P.offer({ key = "eq" .. key, pos = sp, cardPos = V.add(sp, { 0, 0.9, 0 }), kind = "equip", hold = 0.3, ok = true,
                info = "", range = 1.8, done = function() Pl.equip(key) end })
        else
            local ok = Pl.money >= item.price
            P.offer({ key = "shop" .. key, pos = sp, cardPos = V.add(sp, { 0, 0.9, 0 }), kind = "shop", hold = 0.8, ok = ok,
                why = ok and nil or "money", info = "$" .. K.fmt(item.price), infoColor = ok and { 1, 0.9, 0.3 } or { 1, 0.4, 0.4 },
                range = 1.8, done = function() buyGear(key) end })
        end
    end
    -- renascer
    local cost = Gm.rebirthCost()
    P.offer({ key = "rebirth", pos = Lt.REBIRTH, cardPos = V.add(Lt.REBIRTH, { 0, 1.2, -1.6 }), kind = "rebirth", hold = 3,
        ok = Pl.money >= cost, why = Pl.money >= cost and nil or "money", info = "$" .. K.fmt(cost),
        infoColor = { 0.9, 0.7, 1 }, range = 2.8, done = rebirth })
end

---------------------------------------------------------------------------
-- Vitrine da loja (itens girando + nomes)
---------------------------------------------------------------------------
local function buildShopDisplay()
    local Pl = G.player
    for k, key in ipairs(Pl.ORDER) do
        local sp = G.world.shop.stands[k]
        local root = A.empty("disp", G.rig.world, V.add(sp, { 0, 0.15, 0 }))
        local tool = G.ents.makeTool(root, key)
        A.scale(tool.root, 1.6, 1.6, 1.6)
        local icon = A.prim("quad", { parent = G.rig.world, pos = V.add(sp, { 0, 1.45, 0.05 }), scale = { 0.9, 0.225, 1 }, rot = { 0, 180, 0 }, color = { 1, 1, 1 } })
        A.uiQuad(icon)
        L10.bindTex(icon, "itemname_" .. key)
        shopDisp[k] = { root = root, tool = tool }
    end
end

---------------------------------------------------------------------------
-- Tutorial
---------------------------------------------------------------------------
function Gm.tutorial(ev)
    if tut.done then return end
    local step = tut.step or 0
    if ev == "start" and step == 0 then
        tut.step = 1
        EMRAPI.Timer:Delay(2.0, function() G.hud.toast("tut_welcome", 7) end)
        EMRAPI.Timer:Delay(9.5, function() if (tut.step or 0) <= 1 then G.hud.toast("tut_menu", 6) end end)
    elseif ev == "bought" and step <= 1 then
        tut.step = 2
        EMRAPI.Timer:Delay(4.5, function() G.hud.toast("tut_collect", 6) end)
    elseif ev == "collected" and step == 2 then
        tut.step = 3
        EMRAPI.Timer:Delay(1.5, function() G.hud.toast("tut_steal", 7) end)
    elseif ev == "robbed" and step >= 1 and not tut.robbed then
        tut.robbed = true
        EMRAPI.Timer:Delay(3.6, function() G.hud.toast("tut_defend", 6) end)
    end
    if tut.step == 3 and tut.robbed then
        tut.done = true
        A.setBool("tutDone", true)
        A.save()
    end
end

---------------------------------------------------------------------------
-- Salvar / carregar
---------------------------------------------------------------------------
local function nowTime()
    local ok, t = pcall(function() return os.time() end)
    if ok and type(t) == "number" then return t end
    return nil
end

function Gm.save()
    local Pl = G.player
    A.setNum("money", Pl.money)
    A.setNum("rebirths", Pl.rebirths)
    local owned = {}
    for k in pairs(Pl.owned) do owned[#owned + 1] = k end
    A.setStr("owned", table.concat(owned, ","))
    A.setNum("traps", Pl.traps)
    A.setStr("equipped", Pl.equipped)
    if G.myBase then
        local list = {}
        for s = 1, Lt.SLOTS do
            local slot = G.bases.list[G.myBase].slots[s]
            -- online, brainrot sendo carregado por outro jogador nao entra no save (evita duplicar)
            if slot and not (slot.c and online()) then
                list[#list + 1] = s .. "=" .. slot.id .. ":" .. slot.mut .. ":" .. math.floor(slot.acc)
            end
        end
        A.setStr("base", table.concat(list, ","))
    end
    local t = nowTime()
    if t then A.setNum("lastTime", t) end
    A.save()
end

local function loadPlayer()
    local Pl = G.player
    Pl.money = A.getNum("money", 200)
    Pl.rebirths = A.getNum("rebirths", 0)
    Pl.owned = { bat = true }
    for k in (A.getStr("owned", "bat")):gmatch("[^,]+") do
        if Pl.ITEMS[k] then Pl.owned[k] = true end
    end
    Pl.traps = A.getNum("traps", 0)
    local eq = A.getStr("equipped", "bat")
    Pl.equip(Pl.owned[eq] and eq or "bat")
end

-- coloca os brainrots salvos na base (com renda offline nas placas)
local function loadBase(b)
    local str = A.getStr("base", "")
    local last = A.getNum("lastTime", 0)
    local now = nowTime()
    local away = 0
    if now and last > 0 then away = math.max(0, math.min(3 * 3600, now - last)) end
    local total = 0
    for e in str:gmatch("[^,]+") do
        local s, id, mut, acc = e:match("^(%d+)=([%w_]+):([%w_]+):?(%d*)$")
        s = tonumber(s)
        if s and K.byId[id] then
            local off = K.income(id, mut) * away * 0.5
            total = total + off
            G.bases.add(b, id, mut, s, (tonumber(acc) or 0) + off)
        end
    end
    if total >= 1 then
        EMRAPI.Timer:Delay(3.0, function() G.hud.toast("offline_money", 5, "$" .. K.fmt(total), { 0.5, 1, 0.5 }) end)
    end
end

---------------------------------------------------------------------------
-- Sessao
---------------------------------------------------------------------------
local function spawnLocal(b)
    local me = G.localEnt
    if me then G.ents.remove(me.id) end
    me = G.ents.spawnLocal(G.localId, G.settings.nick, G.settings.avatar, G.settings.outfit, b)
    G.localEnt = me
    me.item = G.player.equipped
    G.player.equip(G.player.equipped)
end

local function teleportHome(b)
    G.rig.recenter(Lt.spawnPos(b))
    G.rig.turn(Lt.baseYaw(b))
    G.player.reset()
end

local function placeMe(b)
    G.myBase = b
    G.bases.assign(b, G.localId, G.settings.nick, true, G.settings.avatar)
    G.bases.list[b].rebirths = G.player.rebirths
    loadBase(b)
    spawnLocal(b)
    teleportHome(b)
end

local function clearWorld()
    G.ai.clear()
    G.ents.clear()
    G.localEnt = nil
    G.conveyor.clear()
    for i = 1, 8 do G.bases.clear(i); G.bases.assign(i, nil, "", false) end
    G.myBase = nil
end

-- completa ate `want` bots (contando os que ja existem)
local function fillBots(want)
    local have = 0
    for _ in pairs(G.ai.bots) do have = have + 1 end
    local free = {}
    for i = 1, 8 do if not G.bases.list[i].owner then free[#free + 1] = i end end
    -- riqueza variada: sempre tem alguem com coisa boa para roubar
    local wealth = { 0, 1, 2, 1, 3, 0, 2 }
    local k = have
    for _, b in ipairs(free) do
        if k >= want then break end
        k = k + 1
        G.ai.spawn(b, k, wealth[(k - 1) % #wealth + 1])
    end
end

function Gm.startSolo()
    if online() then G.net.leave() end
    clearWorld()
    G.localId = "me"
    Gm.mode = "solo"
    placeMe(2)
    fillBots(7)
    G.conveyor.prefill()
    Gm.tutorial("start")
    Gm.updateStatus()
end

---------------------------------------------------------------------------
-- Online
---------------------------------------------------------------------------
local function sendHello()
    local me = myEnt()
    G.net.send("hello", { id = G.localId, n = G.settings.nick, av = G.settings.avatar, of = G.settings.outfit })
    if me then G.net.send("pose", G.ents.pose(me)) end
end

local function sendAssign()
    local map = {}
    for i = 1, 8 do
        local b = G.bases.list[i]
        if b.owner then map[#map + 1] = { i = i, o = b.owner, n = b.name } end
    end
    G.net.send("assign", { m = map })
end

local function sendAllBases()
    for i = 1, 8 do
        if isAuthBase(i) and G.bases.list[i].owner then G.net.send("base", G.bases.snapshot(i)) end
    end
end

-- mestre: arruma uma base para um jogador novo
local function masterAssign(id, name)
    for i = 1, 8 do if G.bases.list[i].owner == id then return i end end
    local free = nil
    for i = 1, 8 do if not G.bases.list[i].owner then free = i; break end end
    if not free then
        -- tira um bot para dar lugar
        for i = 1, 8 do
            local o = G.bases.list[i].owner
            if o and o:sub(1, 3) == "bot" then
                local be = G.ents.get(o)
                if be then Gm.dropCarry(be) end
                G.ai.remove(o)
                G.bases.clear(i)
                free = i
                break
            end
        end
    end
    if not free then return nil end
    G.bases.assign(free, id, name, false)
    return free
end

local function onAssign(t)
    for _, e in ipairs(t.m or {}) do
        local b = G.bases.list[e.i]
        if e.o == G.localId then
            if G.myBase ~= e.i then
                if G.myBase then G.bases.clear(G.myBase); G.bases.assign(G.myBase, nil, "", false) end
                placeMe(e.i)
                G.hud.toast("online_ok", 4, G.net.roomName())
                sendAllBases()
            end
        elseif not b.auth or b.owner ~= e.o then
            if b.owner ~= e.o then
                if b.auth and b.owner then G.bases.clear(e.i) end
                G.bases.assign(e.i, e.o, e.n, false)
            end
        end
    end
end

local function setupNet()
    local N = G.net
    N.on("hello", function(sender, t)
        local ent = G.ents.get(t.id)
        if not ent then
            ent = G.ents.spawnRemote(t.id, t.n or "?", t.av, t.of, nil)
            ent.pos = { 0, 0, 0 }
        end
        if master() then
            masterAssign(t.id, t.n)
            sendAssign()
            G.net.send("world", G.events.snapshot())
            for _, c in ipairs(G.conveyor.snapshot()) do G.net.send("conv", c) end
        end
        -- todos respondem com a propria pose e bases (para quem chegou agora)
        sendAllBases()
        if myEnt() then G.net.send("pose", G.ents.pose(myEnt())) end
    end)
    N.on("assign", function(sender, t) onAssign(t) end)
    N.on("pose", function(sender, t)
        if t.id == G.localId then return end
        local own = G.ents.get(t.id)
        if own and own.auth then return end
        G.ents.applyPose(t)
    end)
    N.on("base", function(sender, t) G.bases.applySnapshot(t) end)
    N.on("conv", function(sender, t) G.conveyor.spawn(t.u, t.id, t.m, t.z) end)
    N.on("conv_sold", function(sender, t)
        local it = G.conveyor.items[t.u]
        local price = it and it.price or 0
        G.conveyor.sold(t.u, t.by, t.b)
        if t.by == G.localId and it then
            G.player.spend(math.min(price, G.player.money))
            G.player.stats.bought = G.player.stats.bought + 1
            G.sound("sounds/buy.wav", 0.9)
            voice(it.id, { 0, 1, it.z })
            Gm.tutorial("bought")
        end
        local bot = G.ai.bots[t.by]
        if bot and it then bot.money = bot.money - price end
    end)
    N.on("buy_req", function(sender, t)
        if not master() then return end
        local it = G.conveyor.items[t.u]
        if not it then return end
        G.conveyor.sold(t.u, t.by, t.b)
        G.net.send("conv_sold", { u = t.u, by = t.by, b = t.b })
    end)
    N.on("steal_warn", function(sender, t)
        if ownerIsLocal(t.b) then Gm.alarm(t.b, t.n) end
        local ent = G.ents.get(t.by)
        if ent and not ent.auth then ent.stealing = { b = t.b, s = t.s, t = G.realTime } end
    end)
    N.on("steal_cancel", function(sender, t)
        local ent = G.ents.get(t.by)
        if ent and not ent.auth then ent.stealing = nil end
    end)
    N.on("steal_req", function(sender, t)
        if not isAuthBase(t.b) then return end
        local slot = G.bases.list[t.b].slots[t.s]
        if slot and not slot.c then
            G.bases.setCarried(t.b, t.s, t.by)
            G.net.send("steal_ok", { b = t.b, s = t.s, by = t.by, id = slot.id, m = slot.mut })
            local ent = G.ents.get(t.by)
            if ent then ent.stealing = nil end
            if ownerIsLocal(t.b) then
                G.hud.toast("alert_stolen", 3.5, ent and ent.name or "", { 1, 0.4, 0.4 })
                G.sound("sounds/alarm.wav", 1)
            end
        else
            G.net.send("steal_no", { b = t.b, s = t.s, by = t.by })
        end
    end)
    N.on("steal_ok", function(sender, t)
        local ent = G.ents.get(t.by)
        if ent and ent.auth then
            ent.pendingSteal = nil
            G.ents.setCarry(ent, t.b, t.s, t.id, t.m)
            Gm.onStealGranted(ent, t.b, t.s)
        end
    end)
    N.on("steal_no", function(sender, t)
        local ent = G.ents.get(t.by)
        if ent then ent.pendingSteal = nil end
    end)
    N.on("steal_drop", function(sender, t)
        if isAuthBase(t.b) then
            local slot = G.bases.list[t.b].slots[t.s]
            if slot and slot.c == t.by then
                G.bases.setCarried(t.b, t.s, nil)
                if ownerIsLocal(t.b) then G.hud.toast("recovered", 2.5); G.sound("sounds/recover.wav", 1) end
            end
        end
    end)
    N.on("steal_done", function(sender, t)
        if isAuthBase(t.b) then
            local slot = G.bases.list[t.b].slots[t.s]
            if slot and slot.c == t.by then
                G.bases.remove(t.b, t.s)
                if ownerIsLocal(t.b) then
                    local ent = G.ents.get(t.by)
                    G.hud.toast("alert_lost", 3.5, ent and ent.name or "", { 1, 0.4, 0.4 })
                    Gm.save()
                end
            end
        end
    end)
    N.on("hit", function(sender, t)
        local ent = G.ents.get(t.to)
        if ent and ent.auth then Gm.hitEnt(ent, { t.d[1], 0, t.d[2] }, t.p, t.s, t.by) end
    end)
    N.on("world", function(sender, t)
        if not master() then G.events.apply(t) end
    end)
    N.on("_left", function(actor)
        local id = "a" .. tostring(actor)
        local ent = G.ents.get(id)
        if ent then G.ents.remove(id) end
        -- devolve o que ele carregava das minhas bases
        for i = 1, 8 do
            local b = G.bases.list[i]
            if b.auth then
                for s = 1, Lt.SLOTS do
                    local slot = b.slots[s]
                    if slot and slot.c == id then G.bases.setCarried(i, s, nil) end
                end
            end
            if b.owner == id then
                G.bases.clear(i)
                G.bases.assign(i, nil, "", false)
            end
        end
        if master() then
            fillBots(math.max(0, 4 - G.net.playerCount()))
            sendAssign()
        end
    end)
    N.on("_master", function(actor)
        if master() then
            -- novo mestre: assume as bases dos bots (recria os bots)
            for i = 1, 8 do
                local o = G.bases.list[i].owner
                if o and o:sub(1, 3) == "bot" and not G.ai.bots[o] then
                    G.bases.clear(i)
                    G.bases.assign(i, nil, "", false)
                end
            end
            -- some com os bots antigos (eram remotos, do mestre que saiu)
            for i = #G.ents.order, 1, -1 do
                local e = G.ents.order[i]
                if e.kind == "remote" and e.id:sub(1, 3) == "bot" then G.ents.remove(e.id) end
            end
            fillBots(math.max(0, 4 - G.net.playerCount()))
            sendAssign()
            sendAllBases()
        end
    end)
    N.on("_disconnected", function()
        G.hud.toast("online_lost", 4)
        Gm.startSolo()
    end)
end

function Gm.goOnline()
    if online() or G.net.state == "connecting" then return end
    if not G.net.available() then
        G.hud.toast("online_noperm", 5)
        return
    end
    G.hud.toast("online_connecting", 6)
    Gm.updateStatus("connecting")
    G.net.connect(G.settings.nick, function(ok, err)
        if not ok then
            G.hud.toast("online_fail", 5, tostring(err or ""):sub(1, 30))
            Gm.updateStatus()
            return
        end
        -- entra no mundo online: guarda o que tinha, limpa bots e esteira
        Gm.save()
        clearWorld()
        G.localId = G.net.localId
        Gm.mode = "online"
        if master() then
            placeMe(1 + (G.net.actor % 8))
            fillBots(math.max(0, 4 - G.net.playerCount()))
            G.conveyor.prefill()
            sendAssign()
            sendAllBases()
        end
        sendHello()
        Gm.updateStatus()
    end)
end

---------------------------------------------------------------------------
-- Menu (painel da plataforma)
---------------------------------------------------------------------------
local function uiTry(fn)
    local ok, err = pcall(fn)
    if not ok then A.warnOnce("ui", "UI: " .. tostring(err)) end
end

function Gm.updateStatus(state)
    if not ui.status then return end
    local t = L10.t
    local s
    if state == "connecting" then s = t("st_connecting")
    elseif online() then s = t("st_online", G.net.roomName(), G.net.playerCount())
    else s = t("st_solo") end
    s = s .. "\n" .. t("st_money", K.fmt(G.player.money), G.player.rebirths)
    pcall(function() EMRAPI.UI:SetText(ui.status, s) end)
end

local function makeUI()
    uiTry(function()
        local U = EMRAPI.UI
        local t = L10.t
        local panel = U:CreatePanel(0.9, 1.05)
        ui.panel = panel
        U:SetColor(panel, 0.1, 0.12, 0.22, 0.95)
        local title = U:CreateText(panel, t("title"))
        U:SetPosition(title, 0, 230, 0); U:SetSize(title, 420, 40)
        ui.status = U:CreateText(panel, t("st_solo"))
        U:SetPosition(ui.status, 0, 185, 0); U:SetSize(ui.status, 420, 60)
        ui.pad = U:CreateText(panel, t("padSearch"))
        U:SetPosition(ui.pad, 0, 140, 0); U:SetSize(ui.pad, 420, 34)
        local function btn(text, x, y, cb)
            local b = U:CreateButton(panel, text, cb)
            U:SetPosition(b, x, y, 0); U:SetSize(b, 200, 42)
            return b
        end
        btn(t("bOnline"), -105, 95, function() Gm.goOnline() end)
        btn(t("bSolo"), 105, 95, function() Gm.startSolo() end)
        btn(t("bAvatar"), -105, 48, function()
            G.settings.avatar = G.settings.avatar == "bacon" and "acorn" or "bacon"
            G.settings.outfit = G.settings.avatar == "bacon" and 1 or 7
            A.setStr("avatar", G.settings.avatar); A.setNum("outfit", G.settings.outfit); A.save()
            Gm.applyAvatarColors()
            if G.myBase then
                spawnLocal(G.myBase)
                G.bases.list[G.myBase].avatar = G.settings.avatar
                G.bases.changed(G.myBase)
            end
            G.hud.toast(G.settings.avatar == "bacon" and "av_bacon" or "av_acorn", 2.5)
        end)
        btn(t("bDiff"), 105, 48, function()
            local order = { "easy", "normal", "hard" }
            local idx = 1
            for i, k in ipairs(order) do if k == G.settings.difficulty then idx = i end end
            G.settings.difficulty = order[idx % 3 + 1]
            A.setStr("difficulty", G.settings.difficulty); A.save()
            G.hud.toast("diff_" .. G.settings.difficulty, 2.5)
        end)
        btn(t("bCalib"), -105, 1, function()
            if G.controls.startCalibration() then G.hud.toast("calib", 4) end
        end)
        btn(t("bLang"), 105, 1, function() L10.cycle() end)
        local function toggle(text, key, x, y, apply)
            local tg = U:CreateToggle(panel, text, function(state)
                G.settings[key] = state
                A.setBool(key, state); A.save()
                if apply then apply(state) end
            end)
            U:SetPosition(tg, x, y, 0); U:SetSize(tg, 200, 34)
        end
        toggle(t("tSmooth"), "smoothTurn", -105, -42)
        toggle(t("tWalk"), "gestureWalk", 105, -42, function(v) G.controls.gestureWalk = v end)
        toggle(t("tVoice"), "voice", -105, -78, function(v)
            local r = G.net.setVoice(v)
            A.log("voz: " .. tostring(r))
        end)
        btn(t("bRecenter"), 105, -82, function() G.rig.recenter(G.rig.head and { G.rig.head[1], 0, G.rig.head[3] } or nil) end)
        local function slider(text, lo, hi, x, y, cb)
            local l = U:CreateText(panel, text)
            U:SetPosition(l, x, y + 22, 0); U:SetSize(l, 200, 26)
            local sl = U:CreateSlider(panel, lo, hi, cb)
            U:SetPosition(sl, x, y, 0); U:SetSize(sl, 190, 24)
        end
        slider(t("sHeight"), 1.2, 2.0, -105, -140, function(v)
            G.settings.height = v; G.rig.setHeight(v); A.setNum("height", v); A.save()
        end)
        slider(t("sSpeed"), 2.5, 6, 105, -140, function(v)
            G.settings.moveSpeed = v; A.setNum("moveSpeed", v); A.save()
        end)
        slider(t("sMusic"), 0, 1, -105, -195, function(v)
            G.settings.musicVol = v; G.events.setMusicVolume(v); A.setNum("musicVol", v); A.save()
        end)
        btn(t("bClose"), 105, -200, function() Gm.toggleMenu(false) end)
    end)
    G.controls.onCalibText = function(txt)
        if ui.status then pcall(function() EMRAPI.UI:SetText(ui.status, txt) end) end
    end
end

function Gm.toggleMenu(state)
    if not ui.panel then return end
    if state == nil then state = not ui.visible end
    ui.visible = state
    pcall(function() EMRAPI.UI:SetActive(ui.panel, state) end)
    if state then Gm.updateStatus() end
end

local function rebuildUI()
    local was = ui.visible
    if ui.panel then pcall(function() EMRAPI.UI:Destroy(ui.panel) end) end
    ui.panel, ui.status, ui.pad = nil, nil, nil
    makeUI()
    ui.visible = true
    if was == false then Gm.toggleMenu(false) end
end

local padText = ""
local function updatePadText()
    if not ui.pad then return end
    local C = G.controls
    local t
    if C.calibrating then t = L10.t("padCal")
    elseif C.padConnected then t = L10.t("padOn", C.padNames)
    else t = L10.t("padOff") end
    if t ~= padText then
        padText = t
        pcall(function() EMRAPI.UI:SetText(ui.pad, t) end)
    end
end

-- gesto: palma esquerda virada para o rosto por 1 s abre/fecha o menu
local palmT = 0
local function menuGesture(dt)
    local h = G.controls.hands.left
    if not h.tracked or h.usingPad then palmT = 0; return end
    local R = G.rig
    local toFace = V.norm(V.sub(R.head, h.palm))
    local normal = h.basis.r     -- mao esquerda: dorso = -r, palma = +r
    local open = h.curl[3] < 0.35 and h.curl[4] < 0.35
    if open and V.dot(normal, toFace) > 0.75 and V.dist(R.head, h.palm) < 0.5 then
        palmT = palmT + dt
        if palmT > 1.1 then palmT = -1.5; Gm.toggleMenu() end
    elseif palmT > 0 then
        palmT = 0
    elseif palmT < 0 then
        palmT = math.min(0, palmT + dt)
    end
end

---------------------------------------------------------------------------
-- Init / update
---------------------------------------------------------------------------
function Gm.applyAvatarColors(ctx)
    G = G or ctx
    local AV = require("avatars")
    local H = require("hands")
    local st = AV.STYLES[G.settings.avatar] or AV.STYLES.bacon
    local of = AV.OUTFITS[G.settings.outfit] or {}
    local skin = st.skin
    H.SKIN = skin
    H.PALM = V.scale(skin, 0.97)
    H.JOINT = V.scale(skin, 0.9)
    H.ACCENT = of.shirt or st.shirt
    H.SLEEVE = of.jacket or st.jacket
    -- recolore as maos ja criadas
    for _, side in ipairs({ "left", "right" }) do
        local h = H.get(side)
        if h then
            for _, b in ipairs(h.bones) do A.color(b, H.SKIN) end
            for i = 0, 20 do A.color(h.joints[i], H.JOINT) end
            A.color(h.palm, H.PALM)
            A.color(h.plate, H.ACCENT)
            A.color(h.cuff, H.ACCENT)
            A.color(h.stripe, H.ACCENT)
            A.color(h.forearm, H.SLEEVE)
        end
    end
end

function Gm.init(ctx)
    G = ctx
    G.onWalkerArrived = Gm.onWalkerArrived
    G.onRareSpawn = function(it, rar)
        if Gm.mode == "boot" then return end
        G.hud.toast(rar == "secret" and "spawn_secret" or "spawn_god", 4, K.byId[it.id].name:upper():sub(1, 24), { 1, 0.9, 0.4 })
        G.sound("sounds/rare.wav", 1)
    end
    G.onUnlock = Gm.onUnlock
    G.incomeMult = function(b)
        if G.bases.list[b].owner == G.localId then return G.player.moneyMult() end
        return 1 + 0.5 * (G.bases.list[b].rebirths or 0)
    end
    G.collide = function(p, r, ent)
        -- lasers bloqueiam quem nao e dono
        local dyn = {}
        for i = 1, 8 do
            if G.bases.isLocked(i) and (not ent or ent.base ~= i) and not Lt.inBase(i, p, 0.2) then
                dyn[#dyn + 1] = { box = G.world.bases[i].laserBox }
            end
        end
        local x, z = G.rig.collide(p, r, dyn)
        return { x, p[2], z }
    end
    -- perigos dos eventos
    G.onMeteor = function(p, r)
        local me = myEnt()
        if me and V.distXZ(me.pos, p) < r + 0.4 then G.player.onHit(V.sub(me.pos, p), 4, 1.6) end
        for _, e in ipairs(G.ents.order) do
            if e.kind == "bot" and V.distXZ(e.pos, p) < r + 0.4 then Gm.hitEnt(e, V.sub(e.pos, p), 4, 1.6, nil) end
        end
    end
    G.onLavaPool = function(p, r)
        local me = myEnt()
        if me and G.player.stunT <= 0 and G.player.y < 0.2 and V.distXZ(me.pos, p) < r then
            G.player.onHit(V.sub(me.pos, p), 2.5, 1.0)
        end
    end
    setupNet()
    buildShopDisplay()
    tut.done = A.getBool("tutDone", false)
    loadPlayer()
    makeUI()
    ui.visible = true
    Gm.toggleMenu(false)
    L10.onChange(function()
        rebuildUI()
        G.hud.reloadTextures()
    end)
end

local boardT = 0
local orphanT = 1
local function updateBoard()
    local rows = {}
    for i = 1, 8 do
        local b = G.bases.list[i]
        if b.owner then rows[#rows + 1] = { name = b.name, inc = G.bases.totalIncome(i) * G.incomeMult(i), me = b.owner == G.localId } end
    end
    table.sort(rows, function(a, b) return a.inc > b.inc end)
    local out = {}
    for k = 1, math.min(6, #rows) do
        local r = rows[k]
        local nm = r.name:upper():sub(1, 12)
        out[k] = { k .. " " .. nm .. " $" .. K.fmt(r.inc) .. "/S", r.me and { 1, 0.9, 0.3 } or { 1, 1, 1 } }
    end
    G.world.setBoard(out)
end

local statusT = 0
function Gm.update(dt)
    local R = G.rig
    local feet = { R.head[1], 0, R.head[3] }
    local me = myEnt()
    -- o avatar local segue o corpo (um pouco atras da cabeca)
    if me then
        local back = V.rotY({ 0, 0, -0.14 }, R.bodyYaw)
        me.pos = { feet[1] + back[1], 0, feet[3] + back[3] }
        me.y = G.player.y
        me.yaw = R.bodyYaw
        me.speed = G.moveSpeedNow or 0
        me.anim = G.prompts.holding and "hold" or "idle"
        me.stunT = G.player.stunT
        -- prompt de roubo ativo marca o jogador como "roubando" (os bots reagem)
        if not G.prompts.holding and me.stealing then Gm.stealCancel(me) end
    end
    -- esteira: quem manda sorteia
    local auth = (not online()) or master()
    -- dispara prompts do jogador
    offerPrompts(feet)
    local C = G.controls
    local held = (C.hands.left.grip or C.hands.right.grip) and not C.calibrating
    G.prompts.update(dt, feet, R.flatForward(), R.head, held)
    -- tutorial de coleta
    if tut.step == 2 and G.player.stats.collected > 0 then Gm.tutorial("collected") end
    -- vitrine
    for k, d in ipairs(shopDisp) do A.rot(d.root, 0, G.realTime * 50 + k * 30, 0) end
    -- rede
    if online() then
        poseT = poseT - dt
        if poseT <= 0 then
            poseT = 0.1
            if me then G.net.send("pose", G.ents.pose(me)) end
            for _, bot in pairs(G.ai.bots) do G.net.send("pose", G.ents.pose(bot.ent)) end
        end
        baseT = baseT - dt
        local periodic = baseT <= 0
        if periodic then baseT = 5 end
        for i = 1, 8 do
            local b = G.bases.list[i]
            if b.auth and b.owner and (b.dirty or periodic) then
                b.dirty = false
                G.net.send("base", G.bases.snapshot(i))
            end
        end
        -- jogadores/bots remotos que pararam de mandar pose
        for i = #G.ents.order, 1, -1 do
            local e = G.ents.order[i]
            if e.kind == "remote" and e.lastPose and G.realTime - e.lastPose > 12 then G.ents.remove(e.id) end
        end
        -- roubo pendente sem resposta: desiste
        if me and me.pendingSteal and G.realTime - me.pendingSteal.t > 3 then me.pendingSteal = nil end
    else
        for i = 1, 8 do G.bases.list[i].dirty = false end
    end
    -- menu
    if C.menuDown then Gm.toggleMenu() end
    menuGesture(dt)
    statusT = statusT - dt
    if statusT <= 0 then
        statusT = 1
        updatePadText()
        if ui.visible then Gm.updateStatus() end
    end
    -- vaga "carregada" por alguem que nao existe mais volta para o dono
    orphanT = orphanT - dt
    if orphanT <= 0 then
        orphanT = 1
        for i = 1, 8 do
            local b = G.bases.list[i]
            if b.auth then
                for s = 1, Lt.SLOTS do
                    local slot = b.slots[s]
                    if slot and slot.c and not G.ents.get(slot.c) then
                        slot.orphan = (slot.orphan or 0) + 1
                        if slot.orphan >= 4 then slot.orphan = nil; G.bases.setCarried(i, s, nil) end
                    elseif slot then
                        slot.orphan = nil
                    end
                end
            end
        end
        -- marcas de "roubando" velhas expiram
        for _, e in ipairs(G.ents.order) do
            if e.stealing and e.stealing.t and G.realTime - e.stealing.t > 6.5 then e.stealing = nil end
        end
    end
    boardT = boardT - dt
    if boardT <= 0 then boardT = 3; updateBoard() end
    -- salvar de tempos em tempos
    saveT = saveT + dt
    if saveT > 15 then saveT = 0; Gm.save() end
    return auth
end

function Gm.shutdown()
    pcall(Gm.save)
    pcall(function() G.net.leave() end)
    pcall(function() G.events.shutdown() end)
end

return Gm
