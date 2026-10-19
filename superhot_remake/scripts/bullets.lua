-- bullets.lua — balas LENTAS e visiveis (andam no tempo do jogo).
--  * bala do jogador mata inimigo; bala inimiga mata o jogador E outros inimigos (fogo amigo)
--  * bala contra bala = as duas somem; a katana corta; objeto arremessado bloqueia
--  * assobio quando uma bala passa perto da sua cabeca

local V = require("vec")
local A = require("api")

local Bu = {}
local G

Bu.list = {}
local pool = {}

local function make()
    local o = table.remove(pool)
    if o then
        A.setVisible(o.body, true); A.setVisible(o.trail, true)
        return o
    end
    local body = A.prim("capsule", { parent = G.rig.world, color = { 0.04, 0.04, 0.05 }, mat = { metal = 0.6, smooth = 0.95, noShadow = true } })
    A.scale(body, 0.012, 0.022, 0.012)
    local trail = A.prim("cube", { parent = G.rig.world, color = { 0.55, 0.55, 0.6 }, mat = { smooth = 0.3, noShadow = true } })
    return { body = body, trail = trail }
end

local function free(b)
    if b.dead then return end
    b.dead = true
    A.setVisible(b.o.body, false)
    A.setVisible(b.o.trail, false)
    pool[#pool + 1] = b.o
end

function Bu.fire(from, dir, speed, owner, shooter)
    local b = {
        pos = V.copy(from), start = V.copy(from), dir = V.norm(dir), speed = speed, owner = owner,
        shooter = shooter, t = 0, o = make(), whizzed = false,
    }
    Bu.list[#Bu.list + 1] = b
    local ex, ey, ez = V.eulerAlongY(b.dir)
    A.rot(b.o.body, ex, ey, ez)
    A.rot(b.o.trail, ex, ey, ez)
    A.pos(b.o.body, from)
    A.scale(b.o.trail, 0.004, 0.001, 0.004)
    return b
end

function Bu.destroy(b, effect)
    if b.dead then return end
    if effect then
        G.fx.sparks(b.pos, 6, nil, { 1, 1, 1 }, 1.6)
        G.sound3D("sounds/ping.wav", b.pos, 0.8)
    end
    free(b)
end

-- katana / objetos: corta as balas inimigas perto do segmento a-b
function Bu.sliceSegment(a, b, r)
    for _, bl in ipairs(Bu.list) do
        if not bl.dead and bl.owner == "enemy" then
            local d = V.pointSegDist(bl.pos, a, b)
            if d < r then
                Bu.destroy(bl, true)
                G.stats.sliced = (G.stats.sliced or 0) + 1
            end
        end
    end
end

-- bloqueio por esfera (objetos arremessados, maos)
function Bu.blockSphere(c, r)
    local hit = false
    for _, bl in ipairs(Bu.list) do
        if not bl.dead and bl.owner == "enemy" and V.dist(bl.pos, c) < r then
            Bu.destroy(bl, true)
            hit = true
        end
    end
    return hit
end

local function playerHit(a, b)
    local head = G.rig.head
    if V.pointSegDist(head, a, b) < 0.13 then return true end
    -- tronco: capsula abaixo da cabeca (segue o corpo)
    local c1 = V.add(head, { 0, -0.3, 0 })
    local c2 = V.add(head, { 0, -0.95, 0 })
    -- amostra o segmento da bala
    for i = 0, 3 do
        local p = V.lerp(a, b, i / 3)
        if V.pointSegDist(p, c1, c2) < 0.19 then return true end
    end
    return false
end

function Bu.update(gdt)
    local L = G.level
    local i = 1
    while i <= #Bu.list do
        local b = Bu.list[i]
        if not b.dead then
            b.t = b.t + gdt
            local step = b.speed * gdt
            local a = b.pos
            local nb = V.madd(a, b.dir, step)
            local done = false
            -- parede / cenario
            local t, n = L.raycast(a, b.dir, step + 0.01)
            if t then
                local p = V.madd(a, b.dir, t)
                G.fx.sparks(p, 4, n, { 0.2, 0.2, 0.22 }, 1.4)
                G.fx.hole(p, n)
                if math.random() < 0.5 then G.sound3D("sounds/impact.wav", p, 0.5) end
                Bu.destroy(b)
                done = true
            end
            -- inimigos (do jogador sempre; de inimigo = fogo amigo, menos no proprio atirador)
            if not done then
                local en, zone, hp = G.enemies.hitSegment(a, nb, b.owner == "enemy" and b.shooter or nil)
                if en then
                    G.enemies.kill(en, b.dir, 3.5, hp, b.owner == "enemy" and "friendly" or "bullet")
                    Bu.destroy(b)
                    done = true
                end
            end
            -- jogador
            if not done and b.owner == "enemy" then
                if not b.whizzed and V.pointSegDist(G.rig.head, a, nb) < 0.5 then
                    b.whizzed = true
                    G.sound3D("sounds/whiz.wav", nb, 0.8)
                end
                if playerHit(a, nb) then
                    G.player.die(b.dir)
                    Bu.destroy(b)
                    done = true
                end
            end
            -- bala contra bala
            if not done then
                for _, o in ipairs(Bu.list) do
                    if o ~= b and not o.dead and o.owner ~= b.owner and V.pointSegDist(o.pos, a, nb) < 0.06 then
                        Bu.destroy(o, true)
                        Bu.destroy(b, false)
                        done = true
                        break
                    end
                end
            end
            -- objetos voando bloqueiam balas inimigas
            if not done and b.owner == "enemy" and G.items then
                local it = G.items.sphereAt(nb, 0.05)
                if it then
                    Bu.destroy(b, true)
                    done = true
                end
            end
            if not done then
                b.pos = nb
                A.pos(b.o.body, nb)
                -- rastro: ate 0.9 m atras da bala
                local trailLen = math.min(0.9, V.dist(nb, b.start))
                A.pos(b.o.trail, V.madd(nb, b.dir, -trailLen * 0.5 - 0.02))
                A.scale(b.o.trail, 0.005, trailLen, 0.005)   -- cubo: escala Y = comprimento
                if b.t > 12 then Bu.destroy(b) end
            end
        end
        if b.dead then table.remove(Bu.list, i) else i = i + 1 end
    end
end

function Bu.clear()
    for _, b in ipairs(Bu.list) do free(b) end
    Bu.list = {}
end

function Bu.init(ctx) G = ctx end

return Bu
