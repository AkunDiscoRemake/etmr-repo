-- labels.lua — placas flutuantes dos brainrots (nome, raridade, mutacao, $/s, preco).
-- Os modulos "pedem" placas a cada frame (Lb.want); so os mais perto do jogador
-- ganham uma placa de verdade (pool pequeno = barato para o celular).

local V = require("vec")
local A = require("api")
local K = require("catalog")
local Tx = require("text3d")
local L10 = require("i18n")

local Lb = {}

local POOL = 9
local RANGE = 8.5
local pool = {}
local wants = {}
local nw = 0

local function quad(parent, y, w, h)
    local o = A.prim("quad", { parent = parent, pos = { 0, y, 0 }, scale = { w, h, 1 }, color = { 1, 1, 1 } })
    return A.uiQuad(o)
end

function Lb.init(root)
    for i = 1, POOL do
        local e = { root = A.empty("label", root) }
        e.mut = quad(e.root, 0.5, 0.62, 0.155)
        e.name = quad(e.root, 0.29, 1.0, 0.25)
        e.rar = quad(e.root, 0.09, 0.62, 0.155)
        e.inc = Tx.new({ parent = e.root, pos = { 0, -0.08, 0 }, h = 0.13, color = { 0.45, 1, 0.45 } })
        e.price = Tx.new({ parent = e.root, pos = { 0, -0.25, 0 }, h = 0.13, color = { 1, 0.85, 0.25 } })
        A.setVisible(e.root, false)
        e.visible = false
        pool[i] = e
    end
    L10.onChange(function()
        for _, e in ipairs(pool) do e.key = nil end
    end)
end

-- key: identificador estavel; pos: ponto da placa; price: mostra preco (esteira)
function Lb.want(key, pos, id, mut, price, extra)
    nw = nw + 1
    local w = wants[nw]
    if not w then w = {}; wants[nw] = w end
    w.key, w.pos, w.id, w.mut, w.price, w.extra = key, pos, id, mut, price, extra
end

local function fill(e, w)
    local d = K.byId[w.id]
    e.key = w.key
    A.texture(e.name, "images/names/" .. w.id .. ".png")
    A.texture(e.rar, L10.tex("rar_" .. d.rarity))
    local mut = w.mut or "none"
    if mut ~= "none" then
        A.setVisible(e.mut, true, 0.62, 0.155, 1)
        A.texture(e.mut, L10.tex("mut_" .. mut))
    else
        A.setVisible(e.mut, false)
    end
    Tx.set(e.inc, "$" .. K.fmt(K.income(w.id, mut)) .. "/S")
    if w.price then Tx.set(e.price, "$" .. K.fmt(w.price)) else Tx.set(e.price, w.extra or "") end
end

function Lb.update(viewer)
    -- os mais perto primeiro
    local list = {}
    for i = 1, nw do
        local w = wants[i]
        local d = V.dist(w.pos, viewer)
        if d < RANGE then list[#list + 1] = { w = w, d = d } end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local used = {}
    local chosen = {}
    for i = 1, math.min(POOL, #list) do chosen[list[i].w.key] = list[i].w end
    -- mantem as placas que ja mostram o mesmo item
    for _, e in ipairs(pool) do
        if e.key and chosen[e.key] then
            used[e.key] = e
        end
    end
    local free = {}
    for _, e in ipairs(pool) do
        if not (e.key and used[e.key] == e) then free[#free + 1] = e end
    end
    for key, w in pairs(chosen) do
        local e = used[key]
        if not e then
            e = table.remove(free)
            if e then fill(e, w); used[key] = e end
        elseif w.price then
            Tx.set(e.price, "$" .. K.fmt(w.price))
        end
        if e then
            if not e.visible then A.setVisible(e.root, true); e.visible = true end
            A.pos(e.root, w.pos)
            local d = { w.pos[1] - viewer[1], 0, w.pos[3] - viewer[3] }
            A.rot(e.root, 0, math.atan(d[1], d[3]) * V.DEG, 0)
            local s = math.max(0.7, math.min(1.15, V.dist(w.pos, viewer) / 5))
            A.scale(e.root, s, s, s)
        end
    end
    for _, e in ipairs(free) do
        if e.visible then A.setVisible(e.root, false); e.visible = false end
        e.key = nil
    end
    nw = 0
end

return Lb
