-- ai.lua — IA dos bots rivais. Cada bot tem uma base, dinheiro e personalidade:
--   * compra brainrots na esteira (os melhores que cabem no bolso)
--   * coleta a renda, tranca a base quando esta rica
--   * ROUBA: vai ate outra base (inclusive a sua!), segura 5 s e sai correndo
--   * DEFENDE: persegue quem esta roubando dele e da tacada
-- Em jogo online quem roda os bots e o mestre da sala.

local V = require("vec")
local A = require("api")
local K = require("catalog")
local Lt = require("layout")

local AI = {}

local G
AI.bots = {}

AI.NAMES = {
    { "xXNoobSlayerXx", "bacon", 2 }, { "acorn_queen", "acorn", 7 }, { "TralaleroFan", "bacon", 6 },
    { "MatteoGamer", "bacon", 4 }, { "PizzaLover", "acorn", 5 }, { "brr_patapim", "bacon", 3 },
    { "LilaLarila", "acorn", 1 }, { "Sahur_Hunter", "bacon", 8 }, { "cappuccina", "acorn", 2 },
    { "bombardiro99", "bacon", 5 },
}

local DIFF = {
    easy = { stealGap = { 110, 200 }, aggro = 0.4, speed = 3.4, chase = 3.0, react = 2.6, grace = 240 },
    normal = { stealGap = { 70, 140 }, aggro = 0.7, speed = 3.8, chase = 3.4, react = 1.8, grace = 150 },
    hard = { stealGap = { 40, 90 }, aggro = 1.0, speed = 4.2, chase = 3.8, react = 1.0, grace = 75 },
}

function AI.init(ctx)
    G = ctx
end

local function diff() return DIFF[G.settings.difficulty or "normal"] or DIFF.normal end

-- cria um bot na base b (dados iniciais conforme a "riqueza" desejada)
function AI.spawn(b, k, wealth)
    local n = AI.NAMES[(k - 1) % #AI.NAMES + 1]
    local id = "bot" .. k
    local ent = G.ents.spawnBot(id, n[1], n[2], n[3], b)
    ent.pos = Lt.spawnPos(b)
    ent.yaw = Lt.baseYaw(b)
    local bot = {
        ent = ent, b = b, money = 150 + wealth * 400, state = "home", think = G.rand() * 1.5,
        path = {}, nextSteal = diff().grace * (0.6 + G.rand() * 0.8) + k * 9, holdT = 0, target = nil,
        personality = 0.5 + G.rand() * 0.8, lockCd = 30 + G.rand() * 60, wander = 0,
    }
    AI.bots[id] = bot
    G.bases.assign(b, id, n[1], true, n[2])
    -- brainrots iniciais: alguns comuns/raros (e um especial para valer a pena roubar!)
    local pool = { "noobini", "lirili", "timcheese", "fluriflura", "talpa", "svinina", "pipikiwi", "trippi", "footera", "bobritto" }
    local count = 2 + math.floor(wealth * 1.5)
    for i = 1, math.min(8, count) do
        local id2 = pool[math.min(#pool, 1 + math.floor(G.rand() * (3 + wealth * 2)))]
        G.bases.add(b, id2, G.rand() < 0.12 and "gold" or "none")
    end
    if wealth >= 2 then
        local best = ({ "cappuccino", "patapim", "trulimero", "bananita", "chimpbanana", "ballerina" })[1 + math.floor(G.rand() * 6)]
        G.bases.add(b, best, "none")
    end
    if wealth >= 3 then
        G.bases.add(b, ({ "frigo", "rhino", "bombardiro" })[1 + math.floor(G.rand() * 3)], "none")
    end
    return bot
end

function AI.remove(id)
    local bot = AI.bots[id]
    if not bot then return end
    G.ents.remove(id)
    AI.bots[id] = nil
end

---------------------------------------------------------------------------
-- Caminhos
---------------------------------------------------------------------------
local function outsidePath(bot, from, toBase, toPoint)
    local path = {}
    local fromBase = Lt.baseAt(from)
    if fromBase and fromBase ~= toBase then
        path[#path + 1] = Lt.doorPos(fromBase)
        path[#path + 1] = Lt.frontPos(fromBase)
    end
    if toBase and fromBase ~= toBase then
        path[#path + 1] = Lt.frontPos(toBase)
        path[#path + 1] = Lt.doorPos(toBase)
    end
    path[#path + 1] = toPoint
    return path
end

local function setPath(bot, toBase, point)
    bot.path = outsidePath(bot, bot.ent.pos, toBase, point)
    bot.pathBase = toBase
end

-- anda pelo caminho; retorna true ao chegar no fim
local function walk(bot, dt, speed)
    local ent = bot.ent
    local tgt = bot.path[1]
    if not tgt then ent.speed = 0; return true end
    -- base trancada no caminho: espera do lado de fora
    if bot.pathBase and bot.pathBase ~= bot.b and G.bases.isLocked(bot.pathBase) and V.distXZ(tgt, Lt.doorPos(bot.pathBase)) < 0.1 then
        ent.speed = 0
        bot.blocked = true
        return false
    end
    bot.blocked = false
    local d = V.sub(tgt, ent.pos)
    d[2] = 0
    local len = V.len(d)
    if len < 0.35 then
        table.remove(bot.path, 1)
        return #bot.path == 0
    end
    local dir = V.scale(d, 1 / len)
    local np = V.madd(ent.pos, dir, speed * dt)
    np = G.collide(np, 0.3, ent)
    local moved = V.distXZ(np, ent.pos)
    ent.pos = np
    ent.speed = moved / math.max(dt, 1e-4)
    local wantYaw = math.atan(dir[1], dir[3]) * V.DEG
    local diffA = ((wantYaw - ent.yaw + 540) % 360) - 180
    ent.yaw = ent.yaw + diffA * math.min(1, dt * 10)
    -- preso? pula para o proximo ponto
    bot.stuck = (moved < speed * dt * 0.2) and (bot.stuck or 0) + dt or 0
    if bot.stuck > 1.2 then table.remove(bot.path, 1); bot.stuck = 0 end
    return false
end

---------------------------------------------------------------------------
-- Decisoes
---------------------------------------------------------------------------
local function myIncome(bot) return G.bases.totalIncome(bot.b) end

-- quem esta roubando/carregando algo da minha base?
local function thiefOf(bot)
    for _, e in ipairs(G.ents.order) do
        if e ~= bot.ent then
            if e.carry and e.carry.b == bot.b then return e end
            if e.stealing and e.stealing.b == bot.b then return e end
        end
    end
    return nil
end

local function pickStealTarget(bot)
    local best, bestV = nil, 0
    for i = 1, 8 do
        local base = G.bases.list[i]
        if i ~= bot.b and base.owner and not G.bases.isLocked(i) then
            local v, s = G.bases.best(i, true)
            -- prefere o jogador humano (o jogo fica vivo!) e alvos melhores que os proprios
            local w = v * (base.owner == G.localId and 1.6 or 1.0) * (0.6 + G.rand() * 0.8)
            if s and w > bestV then best, bestV = { b = i, s = s }, w end
        end
    end
    return best
end

local function pickBuy(bot)
    if not G.bases.freeSlot(bot.b) then return nil end
    if G.bases.count(bot.b) + G.conveyor.pendingFor(bot.b) >= Lt.SLOTS then return nil end
    local best, bv = nil, 0
    for _, it in pairs(G.conveyor.items) do
        if it.price <= bot.money and it.z < Lt.CARPET.z1 - 8 and it.z > bot.ent.pos[3] - 14 then
            local v = K.income(it.id, it.mut)
            if v > bv then best, bv = it, v end
        end
    end
    return best
end

local function think(bot)
    local ent = bot.ent
    local d = diff()
    if ent.stunT > 0 then return end
    -- 1) defender a base
    local thief = thiefOf(bot)
    if thief and bot.state ~= "defend" then
        -- tempo de reacao (e se esta longe de casa, pode nem perceber)
        if not bot.noticeT then
            local far = V.distXZ(ent.pos, Lt.bases[bot.b].center) > 20
            bot.noticeT = (far and G.rand() > 0.5 + d.aggro * 0.3) and 1e9 or (d.react * (0.7 + G.rand() * 0.8))
        end
        bot.noticeT = bot.noticeT - 0.5
        if bot.noticeT <= 0 and not ent.carry then
            bot.state = "defend"
            bot.chase = thief
            bot.noticeT = nil
            return
        end
    elseif not thief then
        bot.noticeT = nil
    end
    if bot.state == "defend" and not thief then bot.state = "home" end
    -- 2) carregando: volta para casa
    if ent.carry then
        if bot.state ~= "return" then
            bot.state = "return"
            setPath(bot, bot.b, Lt.basePoint(bot.b, 0, 0, 0))
        end
        return
    end
    if bot.state == "steal" or bot.state == "stealing" or bot.state == "buy" then return end
    -- 3) roubar
    bot.nextSteal = bot.nextSteal - 0.5
    if bot.nextSteal <= 0 and G.bases.freeSlot(bot.b) then
        local tgt = pickStealTarget(bot)
        bot.nextSteal = d.stealGap[1] + G.rand() * (d.stealGap[2] - d.stealGap[1])
        if tgt then
            bot.state = "steal"
            bot.target = tgt
            local sp = Lt.slotPos(tgt.b, tgt.s)
            local q = Lt.slotUV[tgt.s]
            setPath(bot, tgt.b, Lt.basePoint(tgt.b, q.padU, q.v, 0))
            return
        end
    end
    -- 4) comprar
    local it = pickBuy(bot)
    if it then
        bot.state = "buy"
        bot.buyItem = it
        local side = Lt.bases[bot.b].center[1] < 0 and -1 or 1
        setPath(bot, nil, { side * 2.0, 0, math.min(Lt.CARPET.z1 - 4, it.z + 4) })
        return
    end
    -- 5) trancar a base quando esta rica e tem gente perto
    bot.lockCd = bot.lockCd - 0.5
    if bot.lockCd <= 0 and not G.bases.isLocked(bot.b) and G.bases.value(bot.b) > 20000 then
        for _, e in ipairs(G.ents.order) do
            if e ~= ent and V.distXZ(e.pos, Lt.bases[bot.b].center) < 14 then
                bot.state = "lock"
                setPath(bot, bot.b, Lt.lockPos(bot.b))
                bot.lockCd = 90 + G.rand() * 60
                return
            end
        end
    end
    -- 6) passear em casa
    if bot.state == "home" and #bot.path == 0 then
        bot.wander = bot.wander - 0.5
        if bot.wander <= 0 then
            bot.wander = 3 + G.rand() * 5
            setPath(bot, bot.b, Lt.basePoint(bot.b, (G.rand() * 2 - 1) * 2.0, (G.rand() * 2 - 1) * 3.5, 0))
        end
    end
end

---------------------------------------------------------------------------
-- Atualizacao
---------------------------------------------------------------------------
local function update(bot, dt)
    local ent = bot.ent
    local d = diff()
    -- renda vai direto para o bolso
    bot.collectT = (bot.collectT or 0) + dt
    if bot.collectT > 2 then
        bot.collectT = 0
        for s = 1, Lt.SLOTS do bot.money = bot.money + G.bases.collect(bot.b, s) end
    end
    bot.think = bot.think - dt
    if bot.think <= 0 then bot.think = 0.5; think(bot) end
    if ent.stunT > 0 then
        ent.speed = 0
        if bot.state == "stealing" then
            ent.stealing = nil
            bot.state = "home"
        end
        return
    end
    local speed = d.speed * (ent.carry and 0.8 or 1)
    local st = bot.state
    if st == "defend" then
        local c = bot.chase
        if not c or not G.ents.get(c.id) or (not c.carry and not c.stealing) then bot.state = "home"; return end
        bot.path = { V.copy(c.pos) }
        bot.pathBase = nil
        walk(bot, dt, d.chase)
        local dist = V.distXZ(ent.pos, c.pos)
        if dist < 1.9 and ent.swing <= 0 and (bot.swingCd or 0) <= 0 and c.stunT <= 0 then
            ent.swing = 0.001
            bot.swingCd = 1.0
            bot.pendingHit = { t = 0.18, target = c }
            G.sound3D("sounds/swing.wav", ent.pos, 0.7)
        end
    elseif st == "steal" then
        local tgt = bot.target
        local slot = G.bases.list[tgt.b].slots[tgt.s]
        if not slot or slot.c then bot.state = "home"; return end
        if walk(bot, dt, speed) then
            bot.state = "stealing"
            bot.holdT = 0
            ent.stealing = { b = tgt.b, s = tgt.s }
            G.game.stealStart(ent, tgt.b, tgt.s)
        elseif bot.blocked then
            bot.waitT = (bot.waitT or 0) + dt
            if bot.waitT > 8 then bot.waitT = 0; bot.state = "home"; setPath(bot, bot.b, Lt.spawnPos(bot.b)) end
        end
    elseif st == "stealing" then
        local tgt = bot.target
        local slot = G.bases.list[tgt.b].slots[tgt.s]
        ent.speed = 0
        ent.anim = "hold"
        local sp = Lt.slotPos(tgt.b, tgt.s)
        ent.yaw = math.atan(sp[1] - ent.pos[1], sp[3] - ent.pos[3]) * V.DEG
        if not slot or slot.c then ent.stealing = nil; ent.anim = "idle"; bot.state = "home"; return end
        bot.holdT = bot.holdT + dt
        if bot.holdT >= 5 then
            ent.stealing = nil
            ent.anim = "idle"
            G.game.stealComplete(ent, tgt.b, tgt.s)
            bot.state = "return"
            setPath(bot, bot.b, Lt.basePoint(bot.b, 0, 0, 0))
        end
    elseif st == "return" then
        if not ent.carry then bot.state = "home"; return end
        walk(bot, dt, speed)
        if Lt.inBase(bot.b, ent.pos, 0.5) then
            G.game.deliver(ent)
            bot.state = "home"
        end
    elseif st == "buy" then
        local it = bot.buyItem
        if not it or not G.conveyor.items[it.uid] then bot.state = "home"; setPath(bot, bot.b, Lt.spawnPos(bot.b)); return end
        walk(bot, dt, speed)
        local dist = V.distXZ(ent.pos, { 0, 0, it.z })
        if dist < 2.3 then
            bot.buyHold = (bot.buyHold or 0) + dt
            ent.anim = "hold"
            if bot.buyHold > 0.8 then
                bot.buyHold = 0
                ent.anim = "idle"
                if it.price <= bot.money and G.game.buy(ent, it) then bot.money = bot.money - it.price end
                bot.state = "home"
                setPath(bot, bot.b, Lt.spawnPos(bot.b))
            end
        elseif #bot.path == 0 then
            bot.state = "home"
        end
    elseif st == "lock" then
        if walk(bot, dt, speed) then
            G.game.lockBase(bot.b)
            bot.state = "home"
        end
    else
        ent.anim = "idle"
        walk(bot, dt, speed * 0.55)
    end
    if bot.pendingHit then
        bot.pendingHit.t = bot.pendingHit.t - dt
        if bot.pendingHit.t <= 0 then
            local c = bot.pendingHit.target
            bot.pendingHit = nil
            if c and G.ents.get(c.id) and V.distXZ(ent.pos, c.pos) < 2.3 then
                G.game.hitEnt(c, V.sub(c.pos, ent.pos), 3.2, 1.8, ent.id)
                G.sound3D("sounds/bonk.wav", c.pos, 1)
            end
        end
    end
    bot.swingCd = math.max(0, (bot.swingCd or 0) - dt)
end

function AI.update(dt)
    for _, bot in pairs(AI.bots) do update(bot, dt) end
end

-- alguem bateu num bot: ele fica bravo e persegue (revanche)
function AI.onHit(id, byId)
    local bot = AI.bots[id]
    if not bot then return end
    bot.state = "home"
    bot.path = {}
    if bot.ent.stealing then bot.ent.stealing = nil end
    local by = G.ents.get(byId or "")
    if by and G.rand() < diff().aggro * bot.personality then
        bot.revenge = by
    end
end

function AI.clear()
    for id in pairs(AI.bots) do AI.remove(id) end
end

return AI
