-- timeflow.lua — "O TEMPO SO ANDA QUANDO VOCE SE MOVE".
-- Mede o movimento real do jogador (cabeca, giro da cabeca, maos, locomocao) e
-- converte em escala de tempo do jogo: parado ~= 0.04, movendo rapido = 1.
-- Atirar/arremessar da um "pulso" curto de tempo, igual ao SUPERHOT.
-- Tudo que nao e o jogador (inimigos, balas, objetos voando, estilhacos) usa dt * ts.

local V = require("vec")

local TF = {}

TF.MIN = 0.045          -- tempo quase parado
TF.ts = TF.MIN          -- escala atual
TF.gameTime = 0         -- relogio do jogo (escalado)
TF.forced = nil         -- forca um valor (menus, mortes, anuncios)
TF.motion = 0

local prevHead, prevF = nil, nil
local pulseT, pulseAmt = 0, 0

-- pulso curto (ex.: tiro) — o mundo anda um pouco
function TF.pulse(amount, duration)
    pulseAmt = math.max(pulseAmt, amount or 0.9)
    pulseT = math.max(pulseT, duration or 0.12)
end

function TF.force(v) TF.forced = v end

function TF.reset()
    TF.ts = TF.MIN
    TF.gameTime = 0
    pulseT, pulseAmt = 0, 0
end

-- rig: cabeca local; hands: estados de controle (palmVel); moving: locomocao ativa
function TF.update(dt, rig, hands, moving)
    if dt <= 0 then return 0 end
    local head = rig.head
    local f = rig.headB.f
    local headSpeed, ang = 0, 0
    if prevHead then
        headSpeed = V.dist(head, prevHead) / dt
        local c = V.clamp(V.dot(f, prevF), -1, 1)
        ang = math.acos(c) * V.DEG / dt
    end
    prevHead = V.copy(head)
    prevF = V.copy(f)
    -- velocidades enormes = teletransporte/recentralizar: ignora
    if headSpeed > 8 then headSpeed = 0 end
    if ang > 900 then ang = 0 end

    local hand = 0
    for _, h in pairs(hands) do
        if h.tracked then
            local s = V.len(h.palmVel)
            if s < 12 and s > hand then hand = s end
        end
    end
    local motion = math.max(0, headSpeed - 0.06) * 1.7
        + math.max(0, hand - 0.18) * 0.6
        + math.max(0, ang - 14) / 150
    if moving then motion = motion + 0.8 end
    TF.motion = motion

    local target = V.clamp(TF.MIN + motion, TF.MIN, 1)
    if pulseT > 0 then
        pulseT = pulseT - dt
        target = math.max(target, pulseAmt)
        if pulseT <= 0 then pulseAmt = 0 end
    end
    if TF.forced then target = TF.forced end
    -- sobe rapido, desce um pouco mais devagar (fica natural)
    local rate = target > TF.ts and 16 or 7
    TF.ts = TF.ts + (target - TF.ts) * V.smoothK(rate, dt)
    local gdt = dt * TF.ts
    TF.gameTime = TF.gameTime + gdt
    return gdt
end

return TF
