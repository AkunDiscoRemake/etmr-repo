-- combat.lua — raycast unificado (bots, plasma, props, cenario) e aplicacao de dano.

local V = require("vec")
local A = require("api")

local Cb = {}
local G

-- Retorna { t, point, normal, kind = "bot"|"proj"|"prop"|"static", bot, zone, prop, proj, mat }
function Cb.raycast(o, d, maxDist)
    local best = maxDist or 80
    local hit = nil
    local ts, n, mat = G.level.raycast(o, d, best)
    if ts then
        best = ts
        hit = { t = ts, normal = n, kind = "static", mat = mat }
    end
    local tb, bot, zone = G.bots.raycast(o, d, best)
    if tb then
        best = tb
        hit = { t = tb, kind = "bot", bot = bot, zone = zone }
    end
    local tp, proj = G.bots.raycastProjectiles(o, d, best)
    if tp then
        best = tp
        hit = { t = tp, kind = "proj", proj = proj }
    end
    local tr, prop = G.props.raycast(o, d, best)
    if tr then
        best = tr
        hit = { t = tr, kind = "prop", prop = prop }
    end
    if hit then
        hit.point = V.madd(o, d, hit.t)
        if not hit.normal then hit.normal = V.scale(d, -1) end
    end
    return hit
end

function Cb.applyHit(hit, dmg, dir, force, kind)
    if hit.kind == "bot" then
        G.bots.damage(hit.bot, hit.zone, dmg, dir, hit.point, kind)
    elseif hit.kind == "proj" then
        G.bots.popProjectile(hit.proj, true)
    elseif hit.kind == "prop" then
        G.props.hit(hit.prop, dir, force, dmg, kind)
        G.fx.sparks(hit.point, 4, hit.normal, { 1, 0.8, 0.4 }, 2)
        A.sound3D("sounds/impact_metal.wav", hit.point, 0.6, 0.9 + math.random() * 0.2)
    else
        G.fx.sparks(hit.point, 5, hit.normal, nil, 2.2)
        G.fx.hole(hit.point, hit.normal)
        if math.random() < 0.5 then
            A.sound3D(hit.mat == "concrete" and "sounds/impact_concrete.wav" or "sounds/impact_metal.wav", hit.point, 0.5, 0.85 + math.random() * 0.3)
        end
    end
end

-- Explosao: dano em area nos bots e no jogador + empurrao fisico
function Cb.explode(c, radius, dmg)
    G.fx.explosion(c, radius * 0.45)
    A.sound3D("sounds/explosion.wav", c, 1)
    for _, bot in ipairs(G.bots.list) do
        if not bot.dead then
            local bc = V.add(bot.pos, { 0, bot.boundY, 0 })
            local dist = V.dist(bc, c)
            if dist < radius and G.level.lineClear(c, bc) then
                local k = 1 - dist / radius
                local dir = V.norm(V.add(V.sub(bc, c), { 0, 0.5, 0 }))
                G.bots.damage(bot, "torso", dmg * k, dir, bc, "explosion")
            end
        end
    end
    for _, p in ipairs(G.bots.projectiles) do
        if not p.dead and V.dist(p.pos, c) < radius then G.bots.popProjectile(p, false) end
    end
    local hd = V.dist(G.rig.head, c)
    if hd < radius then
        G.player.damage(dmg * 0.35 * (1 - hd / radius), c)
    end
    G.props.blast(c, radius, 9)
    if G.game then G.game.shake = math.max(G.game.shake or 0, 1 - hd / 12) end
end

function Cb.init(ctx)
    G = ctx
end

return Cb
