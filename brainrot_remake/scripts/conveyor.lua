-- conveyor.lua — a esteira vermelha: brainrots aparecem no inicio e andam ate o fim.
-- Comprou? O brainrot sai andando sozinho ate a base do comprador.
-- Quem sorteia os brainrots e o mestre da sala (ou o jogo solo); os outros so espelham.

local V = require("vec")
local A = require("api")
local K = require("catalog")
local M = require("models")
local Lt = require("layout")

local CV = {}

CV.SPEED = 1.35
CV.items = {}          -- andando na esteira
CV.walkers = {}        -- comprados, indo para a base
local G
local seq = 0
local spawnT = 1.0

function CV.init(ctx)
    G = ctx
    CV.root = A.empty("conveyor", G.rig.world)
end

local function makeInst(id, mut)
    local d = K.byId[id]
    local inst = M.build(d, CV.root, mut)
    return inst
end

-- cria um item na esteira (z opcional para "pre-encher" no inicio)
function CV.spawn(uid, id, mut, z)
    if CV.items[uid] or not K.byId[id] then return end
    local it = { uid = uid, id = id, mut = mut or "none", z = z or Lt.CARPET.z0 + 0.5, t = 0 }
    it.inst = makeInst(id, it.mut)
    it.price = K.price(id, it.mut)
    CV.items[uid] = it
    A.posXYZ(it.inst.root, 0, 0.06, it.z)
    local rar = K.byId[id].rarity
    if (rar == "god" or rar == "secret") and G.onRareSpawn then G.onRareSpawn(it, rar) end
    return it
end

function CV.remove(uid)
    local it = CV.items[uid]
    if not it then return end
    M.destroy(it.inst)
    CV.items[uid] = nil
end

-- sorteia e anuncia um novo brainrot (so quem manda)
function CV.roll(z)
    seq = seq + 1
    local uid = (G.net.localId or "me") .. ":" .. seq
    local luck = G.events.luck()
    local id = K.rollBrainrot(G.rand, luck)
    local emut, ech = G.events.mutation()
    local mut = K.rollMutation(G.rand, emut, ech)
    CV.spawn(uid, id, mut, z)
    G.net.send("conv", { u = uid, id = id, m = mut, z = z or Lt.CARPET.z0 + 0.5 })
    return uid
end

-- vendido: o item sai da esteira e anda ate a base `b`
function CV.sold(uid, buyerId, b)
    local it = CV.items[uid]
    if not it then return end
    CV.items[uid] = nil
    local start = { 0, 0.06, it.z }
    local w = {
        uid = uid, id = it.id, mut = it.mut, inst = it.inst, buyer = buyerId, b = b,
        pts = { start, { start[1] + (Lt.frontPos(b)[1] > 0 and 2.2 or -2.2), 0.06, Lt.frontPos(b)[3] }, Lt.frontPos(b), Lt.spawnPos(b) },
        k = 1, pos = start,
    }
    CV.walkers[#CV.walkers + 1] = w
    if G.fx then G.fx.sparkle(V.add(start, { 0, 0.8, 0 }), K.byId[it.id].rar.color) end
end

-- quantos estao indo para a base b (para reservar vaga)
function CV.pendingFor(b)
    local n = 0
    for _, w in ipairs(CV.walkers) do if w.b == b then n = n + 1 end end
    return n
end

function CV.update(dt, t, viewer, authority)
    local C = Lt.CARPET
    -- novos itens
    if authority then
        spawnT = spawnT - dt
        if spawnT <= 0 then
            spawnT = 2.6 + G.rand() * 1.6
            CV.roll()
        end
    end
    for uid, it in pairs(CV.items) do
        it.z = it.z + CV.SPEED * dt
        if it.z > C.z1 + 0.5 then
            CV.remove(uid)
        else
            A.posXYZ(it.inst.root, 0, 0.06, it.z)
            local near = math.abs(it.z - viewer[3]) < 30
            if near then M.animate(it.inst, t, "walk") end
            G.labels.want("cv" .. uid, { 0, 0.3 + it.inst.size * 1.25, it.z }, it.id, it.mut, it.price)
        end
    end
    -- de vez em quando o brainrot mais perto "fala" o nome
    CV.chatT = (CV.chatT or 4) - dt
    if CV.chatT <= 0 then
        CV.chatT = 5 + G.rand() * 5
        local it, d = CV.nearest(viewer, 7)
        if it then G.sound3D("sounds/voice/" .. it.id .. ".wav", { 0, 1, it.z }, 0.75) end
    end
    -- comprados andando ate a base
    for i = #CV.walkers, 1, -1 do
        local w = CV.walkers[i]
        local target = w.pts[w.k + 1]
        if not target then
            table.remove(CV.walkers, i)
            M.destroy(w.inst)
            if G.onWalkerArrived then G.onWalkerArrived(w) end
        else
            local d = V.sub(target, w.pos)
            d[2] = 0
            local len = V.len(d)
            local step = 3.2 * dt
            if len <= step then
                w.pos = { target[1], 0.06, target[3] }
                w.k = w.k + 1
            else
                w.pos = V.madd(w.pos, V.scale(d, 1 / len), step)
            end
            A.posXYZ(w.inst.root, w.pos[1], w.pos[2], w.pos[3])
            if len > 0.01 then A.rot(w.inst.root, 0, math.atan(d[1], d[3]) * V.DEG, 0) end
            M.animate(w.inst, t, "walk")
        end
    end
end

-- item da esteira mais perto de um ponto (para o prompt de comprar)
function CV.nearest(p, maxD)
    local best, bd = nil, maxD or 2.2
    for _, it in pairs(CV.items) do
        local d = V.distXZ(p, { 0, 0, it.z })
        if d < bd then best, bd = it, d end
    end
    return best, bd
end

-- pre-enche a esteira ao comecar (nao comecar vazia!)
function CV.prefill()
    local C = Lt.CARPET
    local z = C.z0 + 3
    while z < C.z1 - 3 do
        CV.roll(z)
        z = z + 3.2 + G.rand() * 1.5
    end
end

function CV.clear()
    for uid in pairs(CV.items) do CV.remove(uid) end
    for _, w in ipairs(CV.walkers) do M.destroy(w.inst) end
    CV.walkers = {}
end

-- snapshot para quem entra na sala depois
function CV.snapshot()
    local list = {}
    for uid, it in pairs(CV.items) do list[#list + 1] = { u = uid, id = it.id, m = it.mut, z = math.floor(it.z * 10) / 10 } end
    return list
end

return CV
