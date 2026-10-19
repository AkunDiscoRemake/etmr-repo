-- avatars.lua — avatares blocados estilo Roblox (R6): BACON HAIR e ACORN GIRL.
-- Montados com cubos; bracos e pernas giram nos ombros/quadril para andar,
-- carregar um brainrot acima da cabeca, bater com o taco e cair atordoado.

local V = require("vec")
local A = require("api")
local Tx = require("text3d")

local AV = {}

local S = 0.34   -- 1 "stud" em metros (avatar com ~1,75 m)

-- estilos: cores das pecas
AV.STYLES = {
    bacon = {
        skin = { 0.96, 0.80, 0.62 }, shirt = { 0.12, 0.38, 0.92 }, jacket = { 0.08, 0.08, 0.1 },
        pants = { 0.1, 0.1, 0.12 }, shoes = { 0.95, 0.95, 0.95 }, hair = { 0.55, 0.3, 0.13 }, hair2 = { 0.42, 0.21, 0.08 },
        face = "images/face_bacon.png",
    },
    acorn = {
        skin = { 0.98, 0.82, 0.68 }, shirt = { 1.0, 0.55, 0.75 }, jacket = { 0.95, 0.4, 0.62 },
        pants = { 0.45, 0.35, 0.85 }, shoes = { 1, 1, 1 }, hair = { 0.5, 0.29, 0.12 }, hair2 = { 0.32, 0.18, 0.07 },
        face = "images/face_acorn.png",
    },
}

-- variacao de roupa para bots/jogadores (mesmo cabelo, roupa diferente)
AV.OUTFITS = {
    { shirt = { 0.12, 0.38, 0.92 }, jacket = { 0.08, 0.08, 0.1 }, pants = { 0.1, 0.1, 0.12 } },
    { shirt = { 0.95, 0.2, 0.2 }, jacket = { 0.95, 0.2, 0.2 }, pants = { 0.15, 0.2, 0.45 } },
    { shirt = { 0.2, 0.75, 0.3 }, jacket = { 0.1, 0.4, 0.15 }, pants = { 0.3, 0.25, 0.2 } },
    { shirt = { 1.0, 0.85, 0.2 }, jacket = { 0.95, 0.55, 0.1 }, pants = { 0.12, 0.12, 0.14 } },
    { shirt = { 0.6, 0.35, 0.95 }, jacket = { 0.35, 0.18, 0.6 }, pants = { 0.9, 0.9, 0.92 } },
    { shirt = { 1.0, 1.0, 1.0 }, jacket = { 0.2, 0.6, 0.95 }, pants = { 0.2, 0.3, 0.6 } },
    { shirt = { 1.0, 0.55, 0.75 }, jacket = { 0.95, 0.4, 0.62 }, pants = { 0.45, 0.35, 0.85 } },
    { shirt = { 0.1, 0.1, 0.1 }, jacket = { 0.95, 0.5, 0.1 }, pants = { 0.1, 0.1, 0.1 } },
}

local function part(parent, pos, scale, color, tex, rot, mat)
    return A.prim("cube", { parent = parent, pos = pos, scale = scale, color = color, tex = tex, rot = rot, mat = mat or { smooth = 0.35 } })
end

local function buildHair(av, st, head)
    -- a cabeca tem centro em y = 0.6 S e topo em y = 1.2 S (no espaco do pescoco)
    if av.kind == "bacon" then
        -- "bacon hair": mechas onduladas por cima, franja na testa, lados e nuca
        part(head, { 0, 1.27 * S, -0.04 * S }, { 1.3 * S, 0.22 * S, 1.3 * S }, st.hair)
        for k = 0, 6 do
            local x = (k - 3) * 0.19 * S
            local h = (0.2 + (k % 3) * 0.07) * S
            part(head, { x, 1.38 * S + h * 0.3, 0.3 * S - (k % 2) * 0.25 * S }, { 0.2 * S, h, 0.55 * S }, k % 2 == 0 and st.hair or st.hair2, nil, { 25 + (k % 3) * 10, 0, (k - 3) * 6 })
        end
        for k, x in ipairs({ -0.36, -0.05, 0.3 }) do
            part(head, { x * S, 1.12 * S, 0.6 * S }, { 0.3 * S, 0.2 * S, 0.14 * S }, k % 2 == 0 and st.hair2 or st.hair, nil, { 0, 0, (k - 2) * 14 })
        end
        for _, sx in ipairs({ -1, 1 }) do
            part(head, { sx * 0.66 * S, 0.9 * S, -0.06 * S }, { 0.14 * S, 0.62 * S, 1.12 * S }, st.hair2)
        end
        part(head, { 0, 0.82 * S, -0.66 * S }, { 1.26 * S, 0.9 * S, 0.14 * S }, st.hair2)
    else
        -- "acorn": cuia arredondada de cabelo com franja reta acima dos olhos (parece uma bolota)
        local cap = A.prim("sphere", { parent = head, pos = { 0, 1.15 * S, -0.02 * S }, scale = { 1.42 * S, 0.72 * S, 1.42 * S }, color = st.hair, mat = { smooth = 0.5 } })
        av.parts[#av.parts + 1] = cap
        part(head, { 0, 1.03 * S, 0.63 * S }, { 1.26 * S, 0.18 * S, 0.1 * S }, st.hair2)
        for _, sx in ipairs({ -1, 1 }) do
            part(head, { sx * 0.67 * S, 0.74 * S, -0.02 * S }, { 0.16 * S, 0.9 * S, 1.1 * S }, st.hair)
        end
        part(head, { 0, 0.7 * S, -0.65 * S }, { 1.28 * S, 1.1 * S, 0.16 * S }, st.hair)
        -- cabinho da bolota
        A.prim("cylinder", { parent = head, pos = { 0, 1.56 * S, -0.02 * S }, scale = { 0.12 * S, 0.1 * S, 0.12 * S }, color = st.hair2 })
        -- laco
        part(head, { 0.5 * S, 1.36 * S, 0.12 * S }, { 0.32 * S, 0.2 * S, 0.12 * S }, { 1, 0.35, 0.6 }, nil, { 0, 0, 25 })
    end
end

-- opt: kind ("bacon"|"acorn"), outfit (indice), name, parent, nameColor, local (sem cabeca/bracos)
function AV.new(opt)
    local kind = opt.kind == "acorn" and "acorn" or "bacon"
    local base = AV.STYLES[kind]
    local st = {}
    for k, v in pairs(base) do st[k] = v end
    local of = AV.OUTFITS[opt.outfit or 0]
    if of and opt.outfit ~= 1 and not (kind == "acorn" and opt.outfit == 7) then
        for k, v in pairs(of) do st[k] = v end
    end
    local av = { kind = kind, style = st, parts = {}, t = 0, anim = "idle", walkPhase = 0, pos = { 0, 0, 0 }, yaw = 0 }
    av.root = A.empty("avatar", opt.parent)
    av.hip = A.empty("hip", av.root, { 0, 2 * S, 0 })
    -- tronco: camiseta + jaqueta aberta
    av.torso = part(av.hip, { 0, S, 0 }, { 2 * S, 2 * S, 1 * S }, st.shirt)
    if st.jacket ~= st.shirt then
        for _, sx in ipairs({ -1, 1 }) do
            part(av.hip, { sx * 0.68 * S, S, 0.02 * S }, { 0.66 * S, 2.02 * S, 1.04 * S }, st.jacket)
        end
    end
    -- cabeca
    av.neck = A.empty("neck", av.hip, { 0, 2 * S, 0 })
    av.head = part(av.neck, { 0, 0.6 * S, 0 }, { 1.2 * S, 1.2 * S, 1.2 * S }, st.skin)
    av.face = A.prim("quad", { parent = av.neck, pos = { 0, 0.6 * S, 0.605 * S }, scale = { 1.1 * S, 1.1 * S, 1 }, rot = { 0, 180, 0 }, color = { 1, 1, 1 }, tex = st.face, mat = { noShadow = true } })
    buildHair(av, st, av.neck)
    -- bracos (pivo no ombro)
    av.armL = A.empty("armL", av.hip, { -1.5 * S, 1.9 * S, 0 })
    av.armR = A.empty("armR", av.hip, { 1.5 * S, 1.9 * S, 0 })
    for _, arm in ipairs({ av.armL, av.armR }) do
        part(arm, { 0, -0.6 * S, 0 }, { 1 * S, 1.3 * S, 1 * S }, st.jacket)
        part(arm, { 0, -1.55 * S, 0 }, { 0.98 * S, 0.7 * S, 0.98 * S }, st.skin)
    end
    -- pernas (pivo no quadril)
    av.legL = A.empty("legL", av.hip, { -0.5 * S, 0, 0 })
    av.legR = A.empty("legR", av.hip, { 0.5 * S, 0, 0 })
    for _, leg in ipairs({ av.legL, av.legR }) do
        part(leg, { 0, -0.85 * S, 0 }, { 0.98 * S, 1.7 * S, 1 * S }, st.pants)
        part(leg, { 0, -1.85 * S, 0.08 * S }, { 1.0 * S, 0.3 * S, 1.2 * S }, st.shoes)
    end
    -- ponto onde vai o brainrot carregado (acima da cabeca)
    av.carryPoint = A.empty("carry", av.root, { 0, 2 * S + 2 * S + 1.35 * S, 0 })
    -- item na mao direita
    av.handR = A.empty("handR", av.armR, { 0, -1.9 * S, 0.1 * S })
    if opt.name then
        av.nameTag = Tx.new({ parent = av.root, pos = { 0, 5.6 * S, 0 }, h = 0.14, color = opt.nameColor or { 1, 1, 1 }, str = opt.name })
    end
    if opt.isLocal then
        -- o proprio jogador nao ve a cabeca nem os bracos (as maos sao desenhadas a parte)
        A.setVisible(av.neck, false)
        A.setVisible(av.armL, false)
        A.setVisible(av.armR, false)
    end
    return av
end

function AV.setName(av, name, color)
    if av.nameTag then Tx.set(av.nameTag, name, color) end
end

-- coloca o avatar: pos = pes (mundo local do jogo), yaw em graus
function AV.place(av, pos, yaw)
    av.pos = pos
    av.yaw = yaw
    A.posXYZ(av.root, pos[1], pos[2], pos[3])
    A.rot(av.root, 0, yaw, 0)
end

-- nome sempre virado para quem olha
function AV.faceTag(av, viewer)
    if not av.nameTag then return end
    local d = { av.pos[1] - viewer[1], 0, av.pos[3] - viewer[3] }
    local yawW = math.atan(d[1], d[3]) * V.DEG
    A.rot(av.nameTag.root, 0, yawW - av.yaw, 0)
end

-- anim: "idle" | "walk" | "run" | "carry" | "stun" | "hold" (segurando prompt)
-- speed: velocidade horizontal (m/s); swing: 0..1 (golpe do taco)
function AV.animate(av, dt, anim, speed, swing)
    av.t = av.t + dt
    speed = speed or 0
    local moving = speed > 0.3
    if moving then av.walkPhase = av.walkPhase + dt * (4 + speed * 2.2) end
    local sw = moving and math.sin(av.walkPhase) or 0
    local amp = math.min(1, speed / 3.5)
    local legA = sw * 50 * amp
    local armA = -sw * 45 * amp
    local hipY = 2 * S + (moving and math.abs(math.cos(av.walkPhase)) * 0.04 or math.sin(av.t * 2) * 0.006)
    local hipPitch, hipRoll = 0, 0
    local aL, aR = { armA, 0, 0 }, { -armA, 0, 0 }
    if anim == "carry" then
        -- bracos para cima segurando o brainrot
        aL = { -165 + sw * 8, 0, -12 }
        aR = { -165 - sw * 8, 0, 12 }
    elseif anim == "hold" then
        aR = { -80 + math.sin(av.t * 10) * 6, 0, 0 }
        aL = { -60, 0, 0 }
    elseif anim == "stun" then
        hipPitch = -60
        hipY = 0.5
        aL = { -120, 0, -40 }
        aR = { -120, 0, 40 }
        legA = 20
    end
    if swing and swing > 0 then
        -- golpe: levanta e desce o braco direito
        local s = swing < 0.35 and (swing / 0.35) or (1 - (swing - 0.35) / 0.65)
        aR = { -150 * s - 40 * (1 - s), 0, 20 * s }
    end
    A.posXYZ(av.hip, 0, hipY, 0)
    A.rot(av.hip, hipPitch, 0, hipRoll)
    A.rot(av.legL, legA, 0, 0)
    A.rot(av.legR, -legA, 0, 0)
    A.rot(av.armL, aL[1], aL[2], aL[3])
    A.rot(av.armR, aR[1], aR[2], aR[3])
    A.rot(av.neck, 0, 0, 0)
end

function AV.setVisible(av, vis)
    A.setVisible(av.root, vis)
end

function AV.destroy(av)
    if av and av.root then A.destroy(av.root) end
end

AV.STUD = S
AV.HEIGHT = 5.2 * S

return AV
