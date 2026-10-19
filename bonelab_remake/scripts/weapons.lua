-- weapons.lua — armas: definicoes, modelos 3D (montados com primitivos), tiro, recuo,
-- pente, ferrolho/slide, bomba da escopeta e o taco (corpo a corpo).
--
-- Mecanica estilo BONELAB:
--   * a arma tem pente (magCount) + bala na camara (chamber)
--   * acabou o pente -> slide trava atras; colocar pente novo libera o slide
--   * Joy-Con: botao A solta o pente. Gestos: pente vazio cai sozinho
--   * pente novo: leve a mao livre ate a bolsa no quadril e feche a mao
--   * escopeta: bombear com a mao de apoio (ou bombeia sozinha se usar uma mao so)

local V = require("vec")
local A = require("api")
local P = require("poses")
local Seg = require("segdisplay")

local W = {}
local G

-- cores/materiais
local GUNMETAL = { 0.16, 0.17, 0.19 }
local POLY = { 0.07, 0.07, 0.08 }
local ORANGE = { 1.0, 0.45, 0.08 }
local BRASS = { 0.85, 0.65, 0.22 }
local MAT_METAL = { metal = 0.9, smooth = 0.65 }
local MAT_POLY = { metal = 0.1, smooth = 0.35 }
local MAT_ORANGE = { metal = 0.3, smooth = 0.6, emit = { 0.35, 0.12, 0.0 } }
local MAT_GLOW = { emit = { 2.5, 0.9, 0.1 }, noShadow = true }

W.defs = {
    pistol = {
        name = "Pistola", kind = "gun", auto = false, magSize = 12, damage = 34, pellets = 1,
        spread = 0.6, rate = 0.11, recoil = 0.55, force = 3, sound = "sounds/pistol.wav",
        muzzle = { 0, 0.028, 0.15 }, ejectPort = { 0.014, 0.034, 0.05 },
        magWell = { 0, -0.1, -0.022 }, magTilt = 15,
        grabs = { grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.11 } },
        restR = 0.016, mass = 1, oneHand = true,
    },
    smg = {
        name = "SMG", kind = "gun", auto = true, magSize = 30, damage = 19, pellets = 1,
        spread = 1.4, rate = 0.085, recoil = 0.28, force = 2.5, sound = "sounds/smg.wav",
        muzzle = { 0, 0.035, 0.36 }, ejectPort = { 0.02, 0.045, 0.1 },
        magWell = { 0, -0.12, 0.08 }, magTilt = -8,
        grabs = {
            grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.11 },
            fore = { pose = "support", at = { 0, 0.012, 0.2 }, r = 0.1 },
        },
        restR = 0.022, mass = 2.5,
    },
    shotgun = {
        name = "Escopeta", kind = "gun", auto = false, magSize = 6, damage = 13, pellets = 9,
        spread = 5.5, rate = 0.3, recoil = 1.0, force = 5, sound = "sounds/shotgun.wav", pump = true,
        muzzle = { 0, 0.045, 0.62 }, ejectPort = { 0.02, 0.05, 0.08 },
        magWell = { 0, -0.11, 0.075 }, magTilt = 0,
        grabs = {
            grip = { pose = "pistol", at = { 0, 0, 0 }, main = true, r = 0.11 },
            fore = { pose = "support", at = { 0, 0.014, 0.3 }, r = 0.11 },
        },
        restR = 0.024, mass = 3.2,
    },
    bat = {
        name = "Taco", kind = "melee", damage = 30,
        grabs = { grip = { pose = "fist", at = { 0, 0, 0 }, main = true, r = 0.12 } },
        blade = { { 0, 0.16, 0 }, { 0, 0.78, 0 } }, bladeR = 0.06,
        restR = 0.04, mass = 1,
    },
    mag = {
        name = "Pente", kind = "mag",
        grabs = { grip = { pose = "mag", at = { 0, 0, 0 }, main = true, r = 0.1 } },
        restR = 0.012, mass = 0.3,
    },
}

---------------------------------------------------------------------------
-- Construcao dos modelos
---------------------------------------------------------------------------
-- com textura, a cor multiplica a textura: usa tons mais claros para ela aparecer
local TEX_METAL = { 0.62, 0.64, 0.7 }
local TEX_POLY = { 0.5, 0.5, 0.54 }

local function part(it, name, kind, pos, scale, color, mat, rot, tex)
    if tex then
        if color == GUNMETAL then color = TEX_METAL elseif color == POLY then color = TEX_POLY end
    end
    local o = A.prim(kind, { parent = it.root, pos = pos, scale = scale, color = color, mat = mat, rot = rot, tex = tex })
    it.parts[name] = o
    it.base = it.base or {}
    it.base[name] = { pos = pos, rot = rot or { 0, 0, 0 }, scale = scale }
    return o
end

local builders = {}

function builders.pistol(it)
    part(it, "slide", "cube", { 0, 0.025, 0.045 }, { 0.026, 0.03, 0.19 }, GUNMETAL, MAT_METAL, nil, "images/gun_slide.png")
    part(it, "barrel", "cylinder", { 0, 0.028, 0.141 }, { 0.013, 0.005, 0.013 }, { 0.3, 0.3, 0.32 }, MAT_METAL, { 90, 0, 0 })
    part(it, "frame", "cube", { 0, 0.003, 0.04 }, { 0.024, 0.016, 0.16 }, POLY, MAT_POLY)
    part(it, "rail", "cube", { 0, -0.008, 0.088 }, { 0.02, 0.008, 0.06 }, POLY, MAT_POLY)
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, POLY, MAT_POLY)
    part(it, "guardF", "cube", { 0, -0.014, 0.054 }, { 0.008, 0.02, 0.004 }, POLY, MAT_POLY)
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, { 0.25, 0.25, 0.27 }, MAT_METAL, { 20, 0, 0 })
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, POLY, MAT_POLY, { 15, 0, 0 }, "images/grip.png")
    part(it, "tail", "cube", { 0, -0.004, -0.042 }, { 0.026, 0.012, 0.02 }, POLY, MAT_POLY)
    part(it, "magbase", "cube", { 0, -0.103, -0.026 }, { 0.027, 0.012, 0.046 }, ORANGE, MAT_ORANGE, { 15, 0, 0 })
    part(it, "sightF", "cube", { 0, 0.043, 0.13 }, { 0.004, 0.007, 0.006 }, ORANGE, MAT_GLOW)
    part(it, "sightR", "cube", { 0, 0.043, -0.042 }, { 0.022, 0.007, 0.006 }, POLY, MAT_POLY)
    part(it, "dotL", "cube", { -0.006, 0.046, -0.046 }, { 0.003, 0.003, 0.002 }, { 0.2, 1, 0.4 }, { emit = { 0.3, 2, 0.6 } })
    part(it, "dotR", "cube", { 0.006, 0.046, -0.046 }, { 0.003, 0.003, 0.002 }, { 0.2, 1, 0.4 }, { emit = { 0.3, 2, 0.6 } })
    part(it, "stripe", "cube", { 0, 0.025, 0.12 }, { 0.027, 0.006, 0.012 }, ORANGE, MAT_ORANGE)
    it.display = Seg.new({ parent = it.root, center = { 0, 0.016, -0.0535 }, n = 2, size = 0.013, on = { 0.2, 1, 0.5 } })
end

function builders.smg(it)
    part(it, "body", "cube", { 0, 0.035, 0.085 }, { 0.034, 0.05, 0.27 }, GUNMETAL, MAT_METAL, nil, "images/gun_metal.png")
    part(it, "top", "cube", { 0, 0.064, 0.085 }, { 0.022, 0.008, 0.2 }, POLY, MAT_POLY)
    part(it, "barrel", "cylinder", { 0, 0.035, 0.29 }, { 0.017, 0.045, 0.017 }, { 0.2, 0.2, 0.22 }, MAT_METAL, { 90, 0, 0 })
    part(it, "muzzleD", "cylinder", { 0, 0.035, 0.345 }, { 0.024, 0.012, 0.024 }, POLY, MAT_POLY, { 90, 0, 0 })
    part(it, "hand", "cube", { 0, 0.014, 0.2 }, { 0.042, 0.038, 0.12 }, POLY, MAT_POLY, nil, "images/grip.png")
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, POLY, MAT_POLY, { 15, 0, 0 }, "images/grip.png")
    part(it, "lower", "cube", { 0, 0.004, 0.02 }, { 0.03, 0.02, 0.1 }, POLY, MAT_POLY)
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, POLY, MAT_POLY)
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, { 0.25, 0.25, 0.27 }, MAT_METAL, { 20, 0, 0 })
    part(it, "mag", "cube", { 0, -0.06, 0.08 }, { 0.022, 0.12, 0.036 }, POLY, MAT_POLY, { -8, 0, 0 })
    part(it, "magbase", "cube", { 0, -0.118, 0.088 }, { 0.026, 0.01, 0.042 }, ORANGE, MAT_ORANGE, { -8, 0, 0 })
    part(it, "stock", "cube", { 0, 0.03, -0.12 }, { 0.026, 0.03, 0.14 }, POLY, MAT_POLY)
    part(it, "butt", "cube", { 0, 0.005, -0.195 }, { 0.036, 0.1, 0.022 }, ORANGE, MAT_ORANGE)
    part(it, "sightR", "cylinder", { 0, 0.074, -0.02 }, { 0.022, 0.006, 0.022 }, POLY, MAT_POLY, { 90, 0, 0 })
    part(it, "sightF", "cube", { 0, 0.074, 0.25 }, { 0.004, 0.014, 0.006 }, ORANGE, MAT_GLOW)
    part(it, "handle", "cube", { -0.024, 0.05, 0.19 }, { 0.016, 0.008, 0.022 }, { 0.3, 0.3, 0.32 }, MAT_METAL)
    part(it, "stripe", "cube", { 0, 0.036, 0.15 }, { 0.035, 0.008, 0.016 }, ORANGE, MAT_ORANGE)
    it.display = Seg.new({ parent = it.root, center = { 0, 0.035, -0.052 }, n = 2, size = 0.018, on = { 0.2, 1, 0.5 } })
end

function builders.shotgun(it)
    part(it, "body", "cube", { 0, 0.03, 0.06 }, { 0.038, 0.058, 0.17 }, GUNMETAL, MAT_METAL, nil, "images/gun_metal.png")
    part(it, "barrel", "cylinder", { 0, 0.045, 0.385 }, { 0.024, 0.24, 0.024 }, { 0.12, 0.12, 0.13 }, MAT_METAL, { 90, 0, 0 })
    part(it, "tube", "cylinder", { 0, 0.016, 0.34 }, { 0.021, 0.2, 0.021 }, { 0.2, 0.2, 0.22 }, MAT_METAL, { 90, 0, 0 })
    part(it, "pump", "cylinder", { 0, 0.014, 0.3 }, { 0.045, 0.075, 0.045 }, POLY, MAT_POLY, { 90, 0, 0 }, "images/grip.png")
    part(it, "grip", "cube", { 0, -0.05, -0.012 }, { 0.028, 0.1, 0.046 }, POLY, MAT_POLY, { 15, 0, 0 }, "images/grip.png")
    part(it, "guard", "cube", { 0, -0.022, 0.03 }, { 0.008, 0.004, 0.05 }, POLY, MAT_POLY)
    part(it, "trigger", "cube", { 0, -0.011, 0.031 }, { 0.006, 0.018, 0.006 }, { 0.25, 0.25, 0.27 }, MAT_METAL, { 20, 0, 0 })
    part(it, "mag", "cube", { 0, -0.055, 0.075 }, { 0.03, 0.1, 0.05 }, POLY, MAT_POLY)
    part(it, "magbase", "cube", { 0, -0.107, 0.075 }, { 0.034, 0.012, 0.056 }, ORANGE, MAT_ORANGE)
    part(it, "stock", "cube", { 0, 0.014, -0.15 }, { 0.034, 0.05, 0.2 }, POLY, MAT_POLY)
    part(it, "butt", "cube", { 0, -0.004, -0.26 }, { 0.04, 0.11, 0.025 }, ORANGE, MAT_ORANGE)
    part(it, "rib", "cube", { 0, 0.059, 0.36 }, { 0.008, 0.004, 0.46 }, { 0.3, 0.3, 0.32 }, MAT_METAL)
    part(it, "bead", "sphere", { 0, 0.064, 0.6 }, { 0.006, 0.006, 0.006 }, ORANGE, MAT_GLOW)
    part(it, "stripe", "cube", { 0, 0.03, 0.135 }, { 0.039, 0.01, 0.014 }, ORANGE, MAT_ORANGE)
    it.display = Seg.new({ parent = it.root, center = { 0, 0.04, -0.054 }, n = 2, size = 0.02, on = { 0.2, 1, 0.5 } })
end

function builders.bat(it)
    part(it, "handle", "cylinder", { 0, 0.02, 0 }, { 0.033, 0.12, 0.033 }, { 0.1, 0.1, 0.11 }, MAT_POLY, nil, "images/grip.png")
    part(it, "knob", "cylinder", { 0, -0.105, 0 }, { 0.046, 0.008, 0.046 }, ORANGE, MAT_ORANGE)
    part(it, "taper", "cylinder", { 0, 0.2, 0 }, { 0.042, 0.07, 0.042 }, { 0.75, 0.76, 0.78 }, MAT_METAL)
    part(it, "barrelB", "cylinder", { 0, 0.48, 0 }, { 0.062, 0.24, 0.062 }, { 0.78, 0.79, 0.82 }, MAT_METAL, nil, "images/bat.png")
    part(it, "cap", "sphere", { 0, 0.72, 0 }, { 0.062, 0.03, 0.062 }, { 0.78, 0.79, 0.82 }, MAT_METAL)
    part(it, "band", "cylinder", { 0, 0.3, 0 }, { 0.064, 0.01, 0.064 }, ORANGE, MAT_ORANGE)
end

function builders.mag(it)
    local gt = it.gunType or "pistol"
    if gt == "smg" then
        part(it, "body", "cube", { 0, -0.03, 0 }, { 0.022, 0.12, 0.036 }, POLY, MAT_POLY)
        part(it, "base", "cube", { 0, -0.088, 0 }, { 0.026, 0.01, 0.042 }, ORANGE, MAT_ORANGE)
    elseif gt == "shotgun" then
        part(it, "body", "cube", { 0, -0.02, 0 }, { 0.03, 0.1, 0.05 }, POLY, MAT_POLY)
        part(it, "base", "cube", { 0, -0.072, 0 }, { 0.034, 0.012, 0.056 }, ORANGE, MAT_ORANGE)
    else
        part(it, "body", "cube", { 0, -0.02, 0 }, { 0.022, 0.09, 0.04 }, GUNMETAL, MAT_METAL)
        part(it, "base", "cube", { 0, -0.068, 0 }, { 0.026, 0.012, 0.046 }, ORANGE, MAT_ORANGE)
    end
    part(it, "round", "capsule", { 0, 0.03, 0.004 }, { 0.009, 0.012, 0.009 }, BRASS, { metal = 0.9, smooth = 0.8 }, { 90, 0, 0 })
end

function W.build(it)
    it.parts = {}
    it.base = {}
    it.root = A.empty("item_" .. it.type, G.rig.world)
    builders[it.type](it)
    if it.def.kind == "gun" then
        it.magCount = it.magCount or it.def.magSize
        if it.chamber == nil then it.chamber = true end
        it.slide = 0
        it.locked = false
        it.cooldown = 0
        it.recoil = 0
        it.pumpState = 0
        it.lastTrig = 0
        W.refreshMagVisual(it)
        W.updateDisplay(it)
    end
end

---------------------------------------------------------------------------
-- Municao / visual
---------------------------------------------------------------------------
function W.ammoTotal(it)
    return (it.magCount or 0) + (it.chamber and 1 or 0)
end

function W.updateDisplay(it)
    if not it.display then return end
    local n = W.ammoTotal(it)
    if G.infiniteAmmo then
        it.display:set("--")
    else
        it.display:set(n, "0")
    end
    local low = n <= 3
    if low ~= it.displayLow then
        it.displayLow = low
        it.display:setColor(low and { 1, 0.2, 0.1 } or { 0.2, 1, 0.5 })
    end
end

function W.refreshMagVisual(it)
    local has = it.magCount ~= nil
    for _, n in ipairs({ "mag", "magbase" }) do
        local o = it.parts[n]
        if o then
            local sc = it.base[n].scale
            A.setVisible(o, has, sc[1], sc[2], sc[3])
        end
    end
end

-- posicao/rotacao locais de uma peca relativas a base (para animar slide, gatilho, bomba)
local function partOffset(it, name, dz, rotX)
    local o = it.parts[name]
    if not o then return end
    local b = it.base[name]
    A.posXYZ(o, b.pos[1], b.pos[2], b.pos[3] + (dz or 0))
    if rotX then A.rot(o, b.rot[1] + rotX, b.rot[2], b.rot[3]) end
end

---------------------------------------------------------------------------
-- Tiro
---------------------------------------------------------------------------
local function spreadDir(B, deg)
    if deg <= 0 then return V.copy(B.f) end
    local t = math.tan(deg * V.RAD)
    -- distribuicao em disco
    local a = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * t
    return V.norm(V.add(B.f, V.add(V.scale(B.r, math.cos(a) * r), V.scale(B.u, math.sin(a) * r))))
end

function W.fire(it, side)
    local def = it.def
    local muzzle = V.poseApply(it.pos, it.B, def.muzzle)
    local aimB = it.B
    -- assistencia de mira leve (tracking de celular treme)
    if G.aimAssist and G.bots then
        local d = G.bots.aimAssist(muzzle, it.B.f, def.pellets > 1 and 4 or 3.2)
        if d then aimB = V.basis(d, it.B.u) end
    end
    for _ = 1, def.pellets do
        local dir = spreadDir(aimB, def.spread)
        local hit = G.combat.raycast(muzzle, dir, 80)
        local endP
        if hit then
            endP = hit.point
            G.combat.applyHit(hit, def.damage, dir, def.force, "bullet")
        else
            endP = V.madd(muzzle, dir, 60)
        end
        G.fx.tracer(muzzle, endP)
    end
    G.fx.muzzle(muzzle, it.B, def.pellets > 1)
    local port = V.poseApply(it.pos, it.B, def.ejectPort)
    local ev = V.add(V.mulMV(it.B, { 1.3 + math.random() * 0.4, 1.2 + math.random() * 0.5, -0.3 }), { 0, 0, 0 })
    if not def.pump then G.fx.shell(port, ev) end
    A.sound3D(def.sound, muzzle, 1, 0.94 + math.random() * 0.12)
    it.recoil = math.min(1.6, it.recoil + def.recoil)
    it.slide = 1
    G.stats.shots = G.stats.shots + 1
    if G.bots then G.bots.noise(muzzle, 18) end

    -- ciclo da municao
    it.chamber = false
    if G.infiniteAmmo then
        it.chamber = true
    elseif def.pump then
        it.needPump = true
    elseif it.magCount and it.magCount > 0 then
        it.magCount = it.magCount - 1
        it.chamber = true
    else
        it.locked = true      -- slide trava atras
    end
    W.updateDisplay(it)
end

local function chamberFromMag(it)
    if it.magCount and it.magCount > 0 then
        it.magCount = it.magCount - 1
        it.chamber = true
        return true
    end
    return false
end

function W.ejectMag(it)
    if it.magCount == nil then return end
    local count = it.magCount
    it.magCount = nil
    W.refreshMagVisual(it)
    W.updateDisplay(it)
    local wellP = V.poseApply(it.pos, it.B, it.def.magWell)
    local mag = G.items.spawn("mag", wellP, it.B, { gunType = it.type, count = count })
    if mag then
        G.items.drop(mag, V.add(V.scale(it.B.u, -1.2), it.vel or { 0, 0, 0 }))
    end
    A.sound3D("sounds/mag_out.wav", wellP, 0.9)
end

function W.insertMag(it, mag)
    it.magCount = mag.count or it.def.magSize
    W.refreshMagVisual(it)
    local wellP = V.poseApply(it.pos, it.B, it.def.magWell)
    A.sound3D("sounds/mag_in.wav", wellP, 1)
    if not it.chamber and (it.locked or it.def.pump) then
        if it.def.pump then
            -- escopeta: precisa bombear (ou bombeia sozinha com 1 mao)
            it.needPump = true
        else
            it.locked = false
            chamberFromMag(it)
            it.slide = 1
            A.sound3D("sounds/slide.wav", wellP, 0.9)
        end
    end
    W.updateDisplay(it)
end

-- distancia do pente segurado ate o encaixe da arma
function W.magWellPos(it)
    return V.poseApply(it.pos, it.B, it.def.magWell)
end

---------------------------------------------------------------------------
-- Atualizacao de uma arma segurada
-- h = estado de entrada da mao principal; sh = mao de apoio (ou nil)
---------------------------------------------------------------------------
function W.updateHeld(it, dt, h, sh)
    local def = it.def
    it.cooldown = math.max(0, it.cooldown - dt)
    it.recoil = it.recoil * math.exp(-dt * 11)
    it.slide = it.slide * math.exp(-dt * 25)

    if def.kind == "melee" then return end

    -- gatilho
    local wantFire = def.auto and h.trigHeld or h.trigDown
    if wantFire and it.cooldown <= 0 then
        if it.chamber then
            W.fire(it, h.side)
            it.cooldown = def.rate
        elseif h.trigDown then
            A.sound3D("sounds/empty.wav", it.pos, 0.8)
            it.cooldown = 0.15
            -- gestos: pente vazio cai sozinho
            if not h.usingPad and it.magCount ~= nil and it.magCount == 0 then W.ejectMag(it) end
        end
    end

    -- botao A (Joy-Con) solta o pente
    if h.primaryDown then W.ejectMag(it) end

    -- bomba da escopeta
    if def.pump and it.needPump then
        if sh then
            -- mao de apoio puxa a bomba para tras e volta
            local local_ = V.poseInverseApply(it.pos, it.B, sh.palm)
            local z = local_[3]
            if it.pumpState == 0 and z < 0.23 then
                it.pumpState = 1
                A.sound3D("sounds/pump_back.wav", it.pos, 0.9)
            elseif it.pumpState == 1 and z > 0.27 then
                it.pumpState = 0
                it.needPump = false
                chamberFromMag(it)
                A.sound3D("sounds/pump_fwd.wav", it.pos, 0.9)
                W.updateDisplay(it)
            end
            it.pumpVis = V.clamp((0.3 - z) / 0.08, 0, 1)
        else
            it.autoPump = (it.autoPump or 0) + dt
            if it.autoPump > 0.35 then
                it.autoPump = 0
                it.needPump = false
                if chamberFromMag(it) then A.sound3D("sounds/pump_fwd.wav", it.pos, 0.9) end
                W.updateDisplay(it)
            end
            it.pumpVis = 0
        end
    else
        it.pumpVis = (it.pumpVis or 0) * math.exp(-dt * 12)
    end
end

-- animacoes das pecas moveis (chamado depois de posicionar a arma)
function W.animate(it, trig)
    if it.def.kind ~= "gun" then return end
    local slideBack = it.locked and 1 or it.slide
    if it.parts.slide then partOffset(it, "slide", -0.032 * slideBack) end
    if it.parts.handle then partOffset(it, "handle", -0.04 * slideBack) end
    if it.parts.pump then partOffset(it, "pump", -0.07 * (it.pumpVis or 0)) end
    if it.parts.trigger then
        local t = trig or 0
        if math.abs(t - (it.lastTrig or 0)) > 0.05 then
            it.lastTrig = t
            partOffset(it, "trigger", 0, -18 * t)
        end
    end
end

-- Pose final da arma com recuo aplicado
function W.recoilPose(it, pos, B)
    local rc = it.recoil or 0
    if rc < 0.001 then return pos, B end
    local kickB = V.mulMM(B, V.axisAngle({ 1, 0, 0 }, -14 * rc))
    local kickP = V.poseApply(pos, B, { 0, 0.008 * rc, -0.035 * rc })
    return kickP, kickB
end

---------------------------------------------------------------------------
-- Corpo a corpo (taco)
---------------------------------------------------------------------------
function W.updateMelee(it, dt)
    local def = it.def
    local a = V.poseApply(it.pos, it.B, def.blade[1])
    local b = V.poseApply(it.pos, it.B, def.blade[2])
    local prevB = it.prevTip or b
    local speed = V.dist(b, prevB) / math.max(dt, 1e-3)
    local vel = V.scale(V.sub(b, prevB), 1 / math.max(dt, 1e-3))
    it.prevTip = b
    it.swingSpeed = speed
    if speed > 2.2 and G.bots then
        G.bots.meleeSweep(a, b, def.bladeR, vel, def.damage + speed * 9, it)
    end
    if speed > 2.2 and G.props then
        G.props.meleeSweep(a, b, def.bladeR, vel)
    end
end

function W.init(ctx)
    G = ctx
end

return W
