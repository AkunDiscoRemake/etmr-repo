-- bases.lua — estado das 8 bases: dono, 10 vagas com brainrots, dinheiro acumulado
-- nas placas, trava (lasers) e modelos 3D (com LOD para bases longe).
--
-- Autoridade: cada base tem um "auth" (quem decide o que acontece nela).
-- Solo: tudo e local. Online: o dono humano decide a propria base; bases de bots
-- sao do mestre da sala. Bases remotas so espelham os "snapshots" recebidos.

local V = require("vec")
local A = require("api")
local Lt = require("layout")
local K = require("catalog")
local M = require("models")
local Tx = require("text3d")

local B = {}

B.list = {}
local G

local LOD_NEAR = 24     -- m: modelos completos ate aqui

function B.init(ctx)
    G = ctx
    for i = 1, 8 do
        B.list[i] = { index = i, owner = nil, name = "", slots = {}, lockT = 0, auth = false, avatar = "bacon", rebirths = 0 }
    end
end

local function W() return G.world end

---------------------------------------------------------------------------
-- Modelos
---------------------------------------------------------------------------
local function proxyFor(i, s, d)
    local p = Lt.slotPos(i, s)
    local h = d.rar.size
    local o = A.prim("cube", { parent = W().bases[i].root, pos = { p[1], 0.42 + h * 0.4, p[3] }, scale = { h * 0.55, h * 0.8, h * 0.55 }, color = d.rar.color })
    return o
end

local function spawnModel(i, s, slot)
    local d = K.byId[slot.id]
    if not d then return end
    local p = Lt.slotPos(i, s)
    slot.inst = M.build(d, W().bases[i].root, slot.mut)
    A.posXYZ(slot.inst.root, p[1], 0.42, p[3])
    A.rot(slot.inst.root, 0, Lt.slotYaw(i, s), 0)
    slot.proxy = proxyFor(i, s, d)
    slot.lod = nil
end

local function despawnModel(slot)
    if slot.inst then M.destroy(slot.inst); slot.inst = nil end
    if slot.proxy then A.destroy(slot.proxy); slot.proxy = nil end
end

local function setLod(slot, near)
    if slot.lod == near then return end
    slot.lod = near
    if slot.inst then A.setVisible(slot.inst.root, near and not slot.c) end
    if slot.proxy then A.setVisible(slot.proxy, (not near) and not slot.c) end
end

local function refreshCarried(slot)
    -- brainrot carregado por alguem some da vaga (aparece na cabeca do ladrao)
    slot.lod = nil
end

---------------------------------------------------------------------------
-- Dono / vagas
---------------------------------------------------------------------------
function B.assign(i, owner, name, auth, avatar)
    local b = B.list[i]
    b.owner = owner
    b.name = name or ""
    b.auth = auth and true or false
    b.avatar = avatar or "bacon"
    local wb = W().bases[i]
    local col = { 1, 1, 1 }
    if owner == nil then
        Tx.set(wb.sign, "")
        Tx.set(wb.signInner, "")
    else
        Tx.set(wb.sign, b.name, col)
        Tx.set(wb.signInner, b.name, col)
    end
end

function B.clear(i)
    local b = B.list[i]
    for s = 1, Lt.SLOTS do
        local slot = b.slots[s]
        if slot then despawnModel(slot) end
        b.slots[s] = nil
    end
    b.lockT = 0
    W().setLasers(i, false)
end

function B.freeSlot(i)
    local b = B.list[i]
    for s = 1, Lt.SLOTS do
        if not b.slots[s] then return s end
    end
    return nil
end

function B.count(i)
    local n = 0
    for s = 1, Lt.SLOTS do if B.list[i].slots[s] then n = n + 1 end end
    return n
end

-- coloca um brainrot (retorna a vaga ou nil se cheia)
function B.add(i, id, mut, s, acc)
    local b = B.list[i]
    s = s or B.freeSlot(i)
    if not s or b.slots[s] then return nil end
    local slot = { id = id, mut = mut or "none", acc = acc or 0, c = nil }
    b.slots[s] = slot
    spawnModel(i, s, slot)
    if G.fx then G.fx.sparkle(V.add(Lt.slotPos(i, s), { 0, 0.6, 0 }), K.byId[id].rar.color) end
    B.changed(i)
    return s
end

function B.remove(i, s)
    local b = B.list[i]
    local slot = b.slots[s]
    if not slot then return nil end
    despawnModel(slot)
    b.slots[s] = nil
    B.changed(i)
    return slot
end

-- marca a vaga como "sendo carregada" por alguem (ou devolve com nil)
function B.setCarried(i, s, carrier)
    local slot = B.list[i].slots[s]
    if not slot then return end
    slot.c = carrier
    refreshCarried(slot)
    B.changed(i)
end

function B.changed(i)
    B.list[i].dirty = true
end

---------------------------------------------------------------------------
-- Trava
---------------------------------------------------------------------------
function B.lockTime(i)
    return 60 + 10 * (B.list[i].rebirths or 0)
end

function B.lock(i, t)
    local b = B.list[i]
    b.lockT = t or B.lockTime(i)
    W().setLasers(i, true)
    B.changed(i)
end

function B.isLocked(i) return B.list[i].lockT > 0 end

---------------------------------------------------------------------------
-- Renda
---------------------------------------------------------------------------
function B.slotIncome(i, s)
    local slot = B.list[i].slots[s]
    if not slot then return 0 end
    return K.income(slot.id, slot.mut)
end

function B.totalIncome(i)
    local t = 0
    for s = 1, Lt.SLOTS do t = t + B.slotIncome(i, s) end
    return t
end

-- melhor brainrot da base (valor) e a vaga
function B.best(i, skipCarried)
    local best, bs = 0, nil
    for s = 1, Lt.SLOTS do
        local slot = B.list[i].slots[s]
        if slot and not (skipCarried and slot.c) then
            local v = K.price(slot.id, slot.mut)
            if v > best then best, bs = v, s end
        end
    end
    return best, bs
end

function B.value(i)
    local t = 0
    for s = 1, Lt.SLOTS do
        local slot = B.list[i].slots[s]
        if slot then t = t + K.price(slot.id, slot.mut) end
    end
    return t
end

-- coleta o dinheiro de uma vaga
function B.collect(i, s)
    local slot = B.list[i].slots[s]
    if not slot or slot.acc < 1 then return 0 end
    local v = math.floor(slot.acc)
    slot.acc = slot.acc - v
    return v
end

---------------------------------------------------------------------------
-- Rede
---------------------------------------------------------------------------
function B.snapshot(i)
    local b = B.list[i]
    local slots = {}
    for s = 1, Lt.SLOTS do
        local slot = b.slots[s]
        if slot then slots[#slots + 1] = { s = s, id = slot.id, m = slot.mut, c = slot.c } end
    end
    return { i = i, o = b.owner, n = b.name, l = math.floor(b.lockT * 10) / 10, sl = slots, av = b.avatar, r = b.rebirths }
end

function B.applySnapshot(t)
    local i = t.i
    local b = B.list[i]
    if not b or b.auth then return end
    if b.owner ~= t.o or b.name ~= t.n then B.assign(i, t.o, t.n, false, t.av) end
    b.rebirths = t.r or 0
    local want = {}
    for _, e in ipairs(t.sl or {}) do want[e.s] = e end
    for s = 1, Lt.SLOTS do
        local cur, w = b.slots[s], want[s]
        if w then
            if not cur or cur.id ~= w.id or cur.mut ~= w.m then
                if cur then despawnModel(cur) end
                local slot = { id = w.id, mut = w.m or "none", acc = 0, c = w.c }
                b.slots[s] = slot
                if K.byId[w.id] then spawnModel(i, s, slot) end
            elseif cur.c ~= w.c then
                cur.c = w.c
                refreshCarried(cur)
            end
        elseif cur then
            despawnModel(cur)
            b.slots[s] = nil
        end
    end
    b.lockT = t.l or 0
    W().setLasers(i, b.lockT > 0)
end

---------------------------------------------------------------------------
-- Atualizacao
---------------------------------------------------------------------------
local padT = 0
function B.update(dt, t, viewer)
    padT = padT + dt
    local updPads = padT > 0.25
    if updPads then padT = 0 end
    for i = 1, 8 do
        local b = B.list[i]
        local wb = W().bases[i]
        -- trava
        if b.lockT > 0 then
            b.lockT = b.lockT - dt
            if b.lockT <= 0 then
                b.lockT = 0
                W().setLasers(i, false)
                if b.auth then B.changed(i) end
                if G.onUnlock then G.onUnlock(i) end
            end
        end
        -- renda (so quem tem autoridade acumula)
        if b.auth and b.owner then
            local mult = G.incomeMult and G.incomeMult(i) or 1
            for s = 1, Lt.SLOTS do
                local slot = b.slots[s]
                if slot and not slot.c then
                    slot.acc = slot.acc + K.income(slot.id, slot.mut) * mult * dt
                end
            end
        end
        -- LOD + animacao + texto das placas
        local dist = V.distXZ(viewer, Lt.bases[i].center)
        local near = dist < LOD_NEAR
        for s = 1, Lt.SLOTS do
            local slot = b.slots[s]
            if slot then
                setLod(slot, near)
                if near and slot.inst and not slot.c then
                    M.animate(slot.inst, t, "idle")
                    if dist < 14 then
                        G.labels.want("b" .. i .. ":" .. s, B.slotTop(i, s), slot.id, slot.mut, nil)
                    end
                end
            end
            if updPads then
                local pad = wb.pads[s]
                if slot and b.auth and b.owner == G.localId and dist < 16 then
                    Tx.set(pad.text, "$" .. K.fmt(slot.acc))
                    local d = { pad.pos[1] - viewer[1], 0, pad.pos[3] - viewer[3] }
                    A.rot(pad.text.root, 0, math.atan(d[1], d[3]) * V.DEG, 0)
                else
                    Tx.set(pad.text, "")
                end
            end
        end
        if updPads then
            if b.lockT > 0 and dist < 20 then
                Tx.set(wb.lockText, math.ceil(b.lockT) .. "S")
            elseif b.owner == G.localId and dist < 20 then
                Tx.set(wb.lockText, "LOCK")
            else
                Tx.set(wb.lockText, "")
            end
            if dist < 20 then
                local d = { wb.lockPos[1] - viewer[1], 0, wb.lockPos[3] - viewer[3] }
                A.rot(wb.lockText.root, 0, math.atan(d[1], d[3]) * V.DEG, 0)
            end
        end
    end
end

-- posicao (topo) do brainrot de uma vaga
function B.slotTop(i, s)
    local slot = B.list[i].slots[s]
    local h = slot and K.byId[slot.id] and K.byId[slot.id].rar.size or 0.7
    return V.add(Lt.slotPos(i, s), { 0, 0.15 + h * 1.05, 0 })
end

return B
