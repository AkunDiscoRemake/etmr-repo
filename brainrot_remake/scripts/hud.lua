-- hud.lua — interface no mundo 3D que acompanha o olhar (com atraso, para nao enjoar):
--   * painel baixo: dinheiro, renda/s, item na mao, boosts ativos
--   * avisos grandes (toasts) na altura dos olhos: eventos, alarmes, dicas
--   * borda vermelha quando leva pancada

local V = require("vec")
local A = require("api")
local K = require("catalog")
local Tx = require("text3d")
local L10 = require("i18n")

local Hd = {}

local G
local panel = {}
local toast = { t = 0 }
local flash = { t = 0, parts = {} }
local yawS = 0

local function quad(parent, pos, w, h, tex)
    local o = A.prim("quad", { parent = parent, pos = pos, scale = { w, h, 1 }, color = { 1, 1, 1 } })
    A.uiQuad(o)
    if tex then A.texture(o, tex) end
    return o
end

function Hd.init(ctx)
    G = ctx
    local world = G.rig.world
    panel.root = A.empty("hud", world)
    panel.bg = A.prim("cube", { parent = panel.root, pos = { 0, 0, 0.012 }, scale = { 0.62, 0.17, 0.005 }, color = { 0.08, 0.09, 0.14 } })
    A.uiQuad(panel.bg)
    panel.money = Tx.new({ parent = panel.root, pos = { 0.02, 0.028, 0 }, h = 0.065, color = { 0.45, 1, 0.45 } })
    panel.income = Tx.new({ parent = panel.root, pos = { 0.02, -0.042, 0 }, h = 0.036, color = { 1, 0.9, 0.4 } })
    panel.item = quad(panel.root, { -0.255, 0, 0 }, 0.09, 0.09, "images/item_bat.png")
    panel.itemN = Tx.new({ parent = panel.root, pos = { -0.255, -0.065, 0 }, h = 0.028, color = { 1, 1, 1 } })
    panel.boosts = {}
    for i = 1, 3 do
        local b = { q = quad(panel.root, { 0.36 + (i - 1) * 0.105, 0.02, 0 }, 0.09, 0.09) }
        b.t = Tx.new({ parent = panel.root, pos = { 0.36 + (i - 1) * 0.105, -0.045, 0 }, h = 0.026, color = { 1, 1, 1 } })
        A.setVisible(b.q, false)
        panel.boosts[i] = b
    end
    panel.carry = quad(panel.root, { 0, 0.15, 0 }, 0.6, 0.11)
    A.setVisible(panel.carry, false)
    panel.carryOn = false

    toast.root = A.empty("toast", world)
    toast.q = quad(toast.root, { 0, 0, 0 }, 1.1, 0.275)
    toast.txt = Tx.new({ parent = toast.root, pos = { 0, -0.22, 0 }, h = 0.08, color = { 1, 1, 1 } })
    A.setVisible(toast.root, false)
    toast.visible = false

    flash.root = A.empty("flash", world)
    local r = { 1, 0.1, 0.1 }
    for _, p in ipairs({ { 0, 0.24, 0.6, 0.06 }, { 0, -0.24, 0.6, 0.06 }, { 0.3, 0, 0.06, 0.54 }, { -0.3, 0, 0.06, 0.54 } }) do
        local o = A.prim("cube", { parent = flash.root, pos = { p[1], p[2], 0 }, scale = { p[3], p[4], 0.01 }, color = r })
        A.uiQuad(o)
    end
    A.setVisible(flash.root, false)
    flash.visible = false
end

-- mensagem grande (chave de textura localizada), texto extra opcional
function Hd.toast(key, dur, extra, color)
    toast.key = key
    toast.t = dur or 3
    local tall = key:sub(1, 4) == "tut_"
    A.scale(toast.q, 1.1, tall and 0.55 or 0.275, 1)
    A.posXYZ(toast.txt.root, 0, tall and -0.36 or -0.22, 0)
    A.texture(toast.q, L10.tex(key))
    Tx.set(toast.txt, extra or "", color or { 1, 1, 1 })
    if not toast.visible then A.setVisible(toast.root, true); toast.visible = true end
end

function Hd.flash()
    flash.t = 0.45
end

local lastMoney, lastItem, lastInc = nil, nil, nil
local slowT = 0

function Hd.update(dt)
    local R = G.rig
    local f = R.flatForward()
    local hy = math.atan(f[1], f[3]) * V.DEG
    local diff = ((hy - yawS + 540) % 360) - 180
    if math.abs(diff) > 20 then yawS = yawS + diff * math.min(1, dt * 3) else yawS = yawS + diff * math.min(1, dt * 0.6) end
    local fw = { math.sin(math.rad(yawS)), 0, math.cos(math.rad(yawS)) }
    -- painel: embaixo, na frente
    local pp = V.add(R.head, V.add(V.scale(fw, 0.62), { 0, -0.36, 0 }))
    A.pos(panel.root, pp)
    A.rot(panel.root, 22, yawS, 0)
    -- toast: altura dos olhos
    if toast.visible then
        local tp = V.add(R.head, V.add(V.scale(fw, 1.5), { 0, 0.22, 0 }))
        A.pos(toast.root, tp)
        A.rot(toast.root, -6, yawS, 0)
        toast.t = toast.t - dt
        if toast.t <= 0 then A.setVisible(toast.root, false); toast.visible = false end
    end
    -- flash
    if flash.t > 0 then
        flash.t = flash.t - dt
        if not flash.visible then A.setVisible(flash.root, true); flash.visible = true end
        local h = R.head
        A.pos(flash.root, V.add(h, V.scale(R.headB.f, 0.32)))
        A.rotBasis(flash.root, V.basis(R.headB.f, R.headB.u))
        if flash.t <= 0 then A.setVisible(flash.root, false); flash.visible = false end
    end
    -- conteudo
    local Pl = G.player
    local m = math.floor(Pl.money)
    if m ~= lastMoney then lastMoney = m; Tx.set(panel.money, "$" .. K.fmt(m)) end
    slowT = slowT - dt
    if slowT <= 0 then
        slowT = 0.5
        local inc = G.myBase and G.bases.totalIncome(G.myBase) * Pl.moneyMult() or 0
        local is = "+$" .. K.fmt(inc) .. "/S"
        if is ~= lastInc then lastInc = is; Tx.set(panel.income, is) end
        local item = Pl.equipped
        local itemS = item .. (item == "trap" and Pl.traps or "") .. (item == "cloak" and math.ceil(Pl.cloakCd) or "")
        if itemS ~= lastItem then
            lastItem = itemS
            A.texture(panel.item, "images/item_" .. item .. ".png")
            if item == "trap" then Tx.set(panel.itemN, "x" .. Pl.traps)
            elseif item == "cloak" and Pl.cloakCd > 0 then Tx.set(panel.itemN, math.ceil(Pl.cloakCd) .. "S")
            else Tx.set(panel.itemN, "") end
        end
        local bl = G.events.boosts()
        for i = 1, 3 do
            local b = panel.boosts[i]
            local e = bl[i]
            if e then
                if b.kind ~= e[1] then
                    b.kind = e[1]
                    A.texture(b.q, "images/boost_" .. e[1] .. ".png")
                end
                if not b.on then A.setVisible(b.q, true, 0.09, 0.09, 1); b.on = true end
                local sec = math.ceil(e[2])
                Tx.set(b.t, sec >= 60 and (math.floor(sec / 60) .. ":" .. string.format("%02d", sec % 60)) or (sec .. "S"))
            else
                if b.on then A.setVisible(b.q, false); b.on = false; b.kind = nil end
                Tx.set(b.t, "")
            end
        end
        local carrying = G.localEnt and G.localEnt.carry ~= nil
        if carrying ~= panel.carryOn then
            panel.carryOn = carrying
            if carrying then
                A.setVisible(panel.carry, true, 0.6, 0.11, 1)
                A.texture(panel.carry, L10.tex("hud_carry"))
            else
                A.setVisible(panel.carry, false)
            end
        end
    end
end

function Hd.reloadTextures()
    if panel.carryOn then A.texture(panel.carry, L10.tex("hud_carry")) end
    if toast.visible and toast.key then A.texture(toast.q, L10.tex(toast.key)) end
end

return Hd
