-- weapons.lua — armas e objetos do SUPERHOT. Tudo que da pra pegar e PRETO.
--   * sem recarga: acabou a municao -> ARREMESSE a arma (acerta = inimigo larga a arma dele)
--   * cada tiro "empurra" o tempo um pouquinho (pulso)
--   * katana: mata no contato e CORTA balas no ar
--   * garrafa, cinzeiro, telefone: arremesse para desarmar/derrubar

local V = require("vec")
local A = require("api")
local Seg = require("segdisplay")

local W = {}
local G

local BLACK = { 0.06, 0.06, 0.07 }
local DARK = { 0.13, 0.13, 0.15 }
local GLOSS = { metal = 0.35, smooth = 0.92 }
local MATTE = { metal = 0.1, smooth = 0.55 }

W.defs = {
    pistol = {
        kind = "gun", ammo = 6, auto = false, pellets = 1, spread = 0.4, rate = 0.16, speed = 16,
        sound = "sounds/pistol.wav", muzzle = { 0, 0.028, 0.15 }, recoil = 0.6,
        grabs = { grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.16 } }, restR = 0.016,
    },
    shotgun = {
        kind = "gun", ammo = 2, auto = false, pellets = 7, spread = 6, rate = 0.45, speed = 14,
        sound = "sounds/shotgun.wav", muzzle = { 0, 0.04, 0.58 }, recoil = 1.1,
        grabs = {
            grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.16 },
            fore = { pose = "support", at = { 0, 0.016, 0.3 }, r = 0.15 },
        }, restR = 0.024,
    },
    uzi = {
        kind = "gun", ammo = 18, auto = true, pellets = 1, spread = 2.2, rate = 0.09, speed = 15,
        sound = "sounds/uzi.wav", muzzle = { 0, 0.03, 0.2 }, recoil = 0.3,
        grabs = { grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.16 } }, restR = 0.02,
    },
    katana = {
        kind = "melee",
        grabs = { grip = { pose = "fist", at = { 0, 0, 0 }, main = true, r = 0.17 } },
        blade = { { 0, 0.14, 0 }, { 0, 0.98, 0 } }, bladeR = 0.05, restR = 0.02,
    },
    bottle = {
        kind = "throw", grabs = { grip = { pose = "fist", at = { 0, 0, 0 }, main = true, r = 0.16 } },
        restR = 0.035, breaks = true, hitR = 0.07,
    },
    ashtray = {
        kind = "throw", grabs = { grip = { pose = "mag", at = { 0, 0, 0 }, main = true, r = 0.16 } },
        restR = 0.02, hitR = 0.07,
    },
    phone = {
        kind = "throw", grabs = { grip = { pose = "mag", at = { 0, 0, 0 }, main = true, r = 0.16 } },
        restR = 0.012, hitR = 0.07,
    },
}

---------------------------------------------------------------------------
-- Modelos
---------------------------------------------------------------------------
local function part(it, name, kind, pos, scale, color, mat, rot)
    local o = A.prim(kind, { parent = it.root, pos = pos, scale = scale, color = color, mat = mat, rot = rot })
    it.parts[name] = o
    it.base[name] = { pos = pos, rot = rot or { 0, 0, 0 }, scale = scale }
    return o
end

local B = {}

function B.pistol(it)
    part(it, "slide", "cube", { 0, 0.025, 0.045 }, { 0.026, 0.03, 0.19 }, BLACK, GLOSS)
    part(it, "frame", "cube", { 0, 0.003, 0.04 }, { 0.024, 0.016, 0.16 }, DARK, MATTE)
    part(it, "barrel", "cylinder", { 0, 0.028, 0.141 }, { 0.012, 0.005, 0.012 }, DARK, GLOSS, { 90, 0, 0 })
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, BLACK, MATTE)
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, DARK, GLOSS, { 20, 0, 0 })
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, BLACK, MATTE, { 15, 0, 0 })
    part(it, "sight", "cube", { 0, 0.043, 0.13 }, { 0.004, 0.007, 0.006 }, DARK, GLOSS)
end

function B.shotgun(it)
    part(it, "body", "cube", { 0, 0.03, 0.06 }, { 0.038, 0.056, 0.17 }, BLACK, GLOSS)
    part(it, "barrelL", "cylinder", { -0.011, 0.045, 0.36 }, { 0.021, 0.22, 0.021 }, DARK, GLOSS, { 90, 0, 0 })
    part(it, "barrelR", "cylinder", { 0.011, 0.045, 0.36 }, { 0.021, 0.22, 0.021 }, DARK, GLOSS, { 90, 0, 0 })
    part(it, "fore", "cube", { 0, 0.018, 0.3 }, { 0.044, 0.03, 0.15 }, BLACK, MATTE)
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, BLACK, MATTE, { 15, 0, 0 })
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, DARK, GLOSS, { 20, 0, 0 })
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, BLACK, MATTE)
    part(it, "stock", "cube", { 0, 0.012, -0.15 }, { 0.034, 0.05, 0.2 }, BLACK, MATTE)
end

function B.uzi(it)
    part(it, "body", "cube", { 0, 0.03, 0.06 }, { 0.034, 0.05, 0.2 }, BLACK, GLOSS)
    part(it, "barrel", "cylinder", { 0, 0.032, 0.18 }, { 0.014, 0.025, 0.014 }, DARK, GLOSS, { 90, 0, 0 })
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, BLACK, MATTE, { 15, 0, 0 })
    part(it, "mag", "cube", { 0, -0.12, -0.03 }, { 0.022, 0.06, 0.03 }, DARK, MATTE, { 15, 0, 0 })
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, DARK, GLOSS, { 20, 0, 0 })
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, BLACK, MATTE)
    part(it, "stock", "cube", { 0, 0.04, -0.06 }, { 0.012, 0.012, 0.09 }, DARK, GLOSS)
end

function B.katana(it)
    part(it, "handle", "cylinder", { 0, 0.02, 0 }, { 0.032, 0.13, 0.026 }, BLACK, MATTE)
    part(it, "guard", "cylinder", { 0, 0.16, 0 }, { 0.075, 0.008, 0.06 }, DARK, GLOSS)
    part(it, "blade", "cube", { 0, 0.58, 0.004 }, { 0.006, 0.82, 0.032 }, BLACK, { metal = 0.6, smooth = 0.97 })
    part(it, "edge", "cube", { 0, 0.58, 0.021 }, { 0.002, 0.82, 0.006 }, { 0.25, 0.25, 0.28 }, { metal = 0.9, smooth = 1 })
    part(it, "tip", "cube", { 0, 1.0, 0.008 }, { 0.006, 0.05, 0.024 }, BLACK, GLOSS, { 25, 0, 0 })
    part(it, "pommel", "cylinder", { 0, -0.115, 0 }, { 0.038, 0.01, 0.034 }, DARK, GLOSS)
end

function B.bottle(it)
    part(it, "neck", "cylinder", { 0, 0.03, 0 }, { 0.026, 0.05, 0.026 }, BLACK, GLOSS)
    part(it, "shoulder", "sphere", { 0, -0.03, 0 }, { 0.07, 0.06, 0.07 }, BLACK, GLOSS)
    part(it, "body", "cylinder", { 0, -0.12, 0 }, { 0.07, 0.09, 0.07 }, BLACK, GLOSS)
end

function B.ashtray(it)
    part(it, "base", "cylinder", { 0, -0.02, 0.02 }, { 0.11, 0.018, 0.11 }, BLACK, GLOSS)
    part(it, "rim", "cylinder", { 0, -0.003, 0.02 }, { 0.12, 0.006, 0.12 }, DARK, GLOSS)
end

function B.phone(it)
    part(it, "body", "cube", { 0, -0.02, 0.01 }, { 0.07, 0.14, 0.012 }, BLACK, GLOSS)
    part(it, "screen", "cube", { 0, -0.02, 0.017 }, { 0.062, 0.122, 0.002 }, DARK, { metal = 0.2, smooth = 1 })
end

function W.build(it)
    it.parts, it.base = {}, {}
    it.root = A.empty("item_" .. it.type, G.rig.world)
    B[it.type](it)
    if it.def.kind == "gun" then
        if it.ammo == nil then it.ammo = it.def.ammo end
        it.cooldown = 0
        it.recoil = 0
        it.slide = 0
        it.lastTrig = 0
    end
end

---------------------------------------------------------------------------
-- Tiro
---------------------------------------------------------------------------
local function spreadDir(Bm, deg)
    if deg <= 0 then return V.copy(Bm.f) end
    local t = math.tan(deg * V.RAD)
    local a = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * t
    return V.norm(V.add(Bm.f, V.add(V.scale(Bm.r, math.cos(a) * r), V.scale(Bm.u, math.sin(a) * r))))
end
W.spreadDir = spreadDir

function W.fire(it)
    local def = it.def
    local muzzle = V.poseApply(it.pos, it.B, def.muzzle)
    local aimB = it.B
    if G.aimAssist and G.enemies then
        local d = G.enemies.aimAssist(muzzle, it.B.f, def.pellets > 1 and 4 or 3)
        if d then aimB = V.basis(d, it.B.u) end
    end
    for _ = 1, def.pellets do
        G.bullets.fire(muzzle, spreadDir(aimB, def.spread), def.speed, "player")
    end
    G.fx.muzzle(muzzle, it.B, def.pellets > 1)
    G.sound3D(def.sound, muzzle, 1)
    it.recoil = math.min(1.6, it.recoil + def.recoil)
    it.slide = 1
    it.ammo = it.ammo - 1
    G.time.pulse(0.95, 0.13)
    G.stats.shots = G.stats.shots + 1
    if it.display then it.display:set(it.ammo, "0") end
end

-- arma segurada (h = mao principal). Cooldown corre no tempo do JOGO, como no SUPERHOT.
function W.updateHeld(it, dt, gdt, h)
    local def = it.def
    it.recoil = it.recoil * math.exp(-dt * 11)
    it.slide = it.slide * math.exp(-dt * 25)
    if def.kind ~= "gun" then return end
    it.cooldown = math.max(0, it.cooldown - gdt)
    local want = def.auto and h.trigHeld or h.trigDown
    if want then
        if it.ammo > 0 then
            if it.cooldown <= 0 then
                W.fire(it)
                it.cooldown = def.rate
            end
        elseif h.trigDown then
            G.sound3D("sounds/empty.wav", it.pos, 0.8)
            G.game.hintThrow()
        end
    end
end

function W.animate(it, trig)
    if it.def.kind ~= "gun" then return end
    local s = it.parts.slide
    if s then
        local b = it.base.slide
        A.posXYZ(s, b.pos[1], b.pos[2], b.pos[3] - 0.03 * (it.ammo <= 0 and 1 or it.slide))
    end
    local tr = it.parts.trigger
    if tr and math.abs((trig or 0) - (it.lastTrig or 0)) > 0.05 then
        it.lastTrig = trig
        local b = it.base.trigger
        A.rot(tr, b.rot[1] - 18 * trig, b.rot[2], b.rot[3])
    end
end

function W.recoilPose(it, pos, Bm)
    local rc = it.recoil or 0
    if rc < 0.001 then return pos, Bm end
    return V.poseApply(pos, Bm, { 0, 0.008 * rc, -0.035 * rc }), V.mulMM(Bm, V.axisAngle({ 1, 0, 0 }, -14 * rc))
end

-- katana: varredura da lamina (velocidade REAL da mao)
function W.updateMelee(it, dt)
    local def = it.def
    local a = V.poseApply(it.pos, it.B, def.blade[1])
    local b = V.poseApply(it.pos, it.B, def.blade[2])
    local prev = it.prevTip or b
    local speed = V.dist(b, prev) / math.max(dt, 1e-3)
    it.prevTip = b
    if speed > 1.4 then
        local vel = V.scale(V.sub(b, prev), 1 / math.max(dt, 1e-3))
        G.enemies.slash(a, b, def.bladeR, vel)
        if speed > 2.5 and not it.whoosh then
            it.whoosh = true
            G.sound3D("sounds/swing.wav", b, 0.6)
        end
    else
        it.whoosh = false
    end
    -- a lamina corta balas mesmo parada (bloqueio)
    G.bullets.sliceSegment(a, b, def.bladeR + 0.02)
end

function W.init(ctx) G = ctx end

return W
