-- prompts.lua — "ProximityPrompt" em VR: chegue perto, olhe para o alvo e SEGURE
-- o botao de pegar (R/L do Joy-Con ou fechar a mao) ate a barra encher.
-- Comprar = rapido, roubar = 5 segundos.

local V = require("vec")
local A = require("api")
local Tx = require("text3d")
local L10 = require("i18n")

local P = {}

local G
local cands = {}
local nc = 0
local card
P.active = nil
P.progress = 0
P.holding = false

function P.init(ctx)
    G = ctx
    card = { root = A.empty("prompt", G.rig.world) }
    card.bg = A.prim("quad", { parent = card.root, pos = { 0, 0.1, 0.01 }, scale = { 0.95, 0.24, 1 }, color = { 1, 1, 1 } })
    A.uiQuad(card.bg)
    card.barBg = A.prim("cube", { parent = card.root, pos = { 0, -0.07, 0 }, scale = { 0.9, 0.06, 0.02 }, color = { 0.12, 0.12, 0.16 } })
    A.uiQuad(card.barBg)
    card.bar = A.prim("cube", { parent = card.root, pos = { -0.45, -0.07, -0.006 }, scale = { 0.001, 0.05, 0.02 }, color = { 0.3, 1, 0.4 } })
    A.uiQuad(card.bar)
    card.info = Tx.new({ parent = card.root, pos = { 0, -0.2, 0 }, h = 0.11, color = { 1, 1, 1 } })
    card.why = A.prim("quad", { parent = card.root, pos = { 0, -0.36, 0 }, scale = { 0.7, 0.175, 1 }, color = { 1, 1, 1 } })
    A.uiQuad(card.why)
    A.setVisible(card.root, false)
    card.visible = false
end

-- c = { key, pos (alvo), cardPos, kind (textura), hold (s), ok (bool), why (chave), info (texto), done = fn }
function P.offer(c)
    nc = nc + 1
    cands[nc] = c
end

local function choose(feet, look)
    local best, bs = nil, -1e9
    for i = 1, nc do
        local c = cands[i]
        local d = V.distXZ(feet, c.pos)
        local r = c.range or 2.4
        if d < r then
            local to = V.sub(c.pos, feet)
            to[2] = 0
            local l = V.len(to)
            local dot = l > 0.05 and V.dot(V.scale(to, 1 / l), look) or 1
            local okDot = dot > (c.minDot or -0.2) or (not c.minDot and d < 0.9)
            if okDot then
                local score = dot * 2 - d * 0.9 + (c.prio or 0)
                if P.active and P.active.key == c.key then score = score + 0.6 end   -- estabilidade
                if score > bs then best, bs = c, score end
            end
        end
    end
    return best
end

-- inputHeld: o jogador esta segurando o botao/fechando a mao
function P.update(dt, feet, look, viewer, inputHeld)
    local c = choose(feet, look)
    if P.active and (not c or c.key ~= P.active.key) then
        if P.progress > 0 and P.active.cancel then P.active.cancel() end
        P.progress = 0
    end
    P.active = c
    if not c then
        P.progress = 0
        P.holding = false
        if card.visible then A.setVisible(card.root, false); card.visible = false end
        nc = 0
        return
    end
    if not card.visible then A.setVisible(card.root, true); card.visible = true end
    if card.kind ~= c.kind then
        card.kind = c.kind
        A.texture(card.bg, L10.tex("prompt_" .. c.kind))
    end
    local wantWhy = (not c.ok) and c.why or nil
    if wantWhy ~= card.whyKey then
        card.whyKey = wantWhy
        if wantWhy then
            A.setVisible(card.why, true, 0.7, 0.175, 1)
            A.texture(card.why, L10.tex("why_" .. wantWhy))
        else
            A.setVisible(card.why, false)
        end
    end
    Tx.set(card.info, c.info or "", c.infoColor or { 1, 1, 1 })
    local cp = c.cardPos or V.add(c.pos, { 0, 1.2, 0 })
    A.pos(card.root, cp)
    local d = { cp[1] - viewer[1], 0, cp[3] - viewer[3] }
    A.rot(card.root, 0, math.atan(d[1], d[3]) * V.DEG, 0)

    P.holding = inputHeld and c.ok
    if P.holding then
        local before = P.progress
        P.progress = P.progress + dt / math.max(0.05, c.hold or 1)
        if c.tick and math.floor(before * 5) ~= math.floor(P.progress * 5) then c.tick(P.progress) end
        if before == 0 and c.start then c.start() end
        if P.progress >= 1 then
            P.progress = 0
            P.holding = false
            local fn = c.done
            nc = 0
            if fn then fn() end
            return
        end
    else
        if P.progress > 0 and c.cancel then c.cancel() end
        P.progress = 0
    end
    local w = math.max(0.001, 0.9 * P.progress)
    A.scale(card.bar, w, 0.05, 0.02)
    A.posXYZ(card.bar, -0.45 + w / 2, -0.07, -0.006)
    nc = 0
end

function P.reset()
    P.progress = 0
    P.active = nil
    nc = 0
end

return P
