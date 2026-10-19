-- segdisplay.lua — display de 7 segmentos feito de cubos (placar, municao, vida).
-- Funciona em qualquer lugar do mundo e ate preso numa arma, sem depender de UI.

local V = require("vec")
local A = require("api")

local D = {}
D.__index = D

local DIGITS = {
    ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abdeg", ["3"] = "abcdg", ["4"] = "bcfg",
    ["5"] = "acdfg", ["6"] = "acdefg", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg",
    ["-"] = "g", [" "] = "", ["E"] = "adefg", ["r"] = "eg", ["P"] = "abefg", ["L"] = "def",
    ["H"] = "bcefg", ["A"] = "abcefg", ["C"] = "adef", ["o"] = "cdeg", ["n"] = "ceg", ["d"] = "bcdeg",
}

-- posicoes dos segmentos (x, y) num digito de largura 0.6 e altura 1, e se e horizontal
local SEG = {
    a = { 0, 0.5, true }, g = { 0, 0, true }, d = { 0, -0.5, true },
    b = { 0.3, 0.25, false }, c = { 0.3, -0.25, false },
    f = { -0.3, 0.25, false }, e = { -0.3, -0.25, false },
}
local ORDER = { "a", "b", "c", "d", "e", "f", "g" }

-- opt: parent, center, basis (r = direita de quem le, u = cima, f = direcao do olhar de quem le),
--      n (digitos), size (altura), on, off, back
function D.new(opt)
    local self = setmetatable({}, D)
    self.n = opt.n or 3
    self.size = opt.size or 0.1
    self.on = opt.on or { 1, 0.45, 0.08 }
    self.off = opt.off or { 0.09, 0.07, 0.06 }
    self.basis = opt.basis or V.identity()
    self.center = opt.center or { 0, 0, 0 }
    self.parent = opt.parent
    self.root = A.empty("seg", opt.parent, self.center)
    A.rotBasis(self.root, self.basis)
    self.segs = {}
    self.value = nil
    local s = self.size
    local spacing = s * 0.85
    if opt.back ~= false then
        A.prim("cube", {
            parent = self.root, pos = { 0, 0, s * 0.05 },
            scale = { spacing * self.n + s * 0.3, s * 1.35, s * 0.08 },
            color = opt.backColor or { 0.04, 0.04, 0.05 }, mat = { metal = 0.4, smooth = 0.7 },
        })
    end
    for i = 1, self.n do
        local cx = (i - (self.n + 1) / 2) * spacing
        local dig = {}
        for _, k in ipairs(ORDER) do
            local sg = SEG[k]
            local sx, sy = sg[3] and s * 0.5 or s * 0.11, sg[3] and s * 0.11 or s * 0.42
            local o = A.prim("cube", {
                parent = self.root, pos = { cx + sg[1] * s, sg[2] * s, -s * 0.02 },
                scale = { sx, sy, s * 0.05 }, color = self.off, mat = { noShadow = true },
            })
            dig[k] = { obj = o, lit = false }
        end
        self.segs[i] = dig
    end
    return self
end

function D:set(v, pad)
    local str
    if type(v) == "number" then
        str = tostring(math.floor(v + 0.5))
    else
        str = tostring(v)
    end
    if #str > self.n then str = string.rep("9", self.n) end
    if pad then
        str = string.rep(pad, self.n - #str) .. str
    else
        str = string.rep(" ", self.n - #str) .. str
    end
    if str == self.value then return end
    self.value = str
    for i = 1, self.n do
        local ch = str:sub(i, i)
        local lit = DIGITS[ch] or ""
        for _, k in ipairs(ORDER) do
            local sg = self.segs[i][k]
            local want = lit:find(k, 1, true) ~= nil
            if want ~= sg.lit then
                sg.lit = want
                A.color(sg.obj, want and self.on or self.off)
                if want then A.material(sg.obj, { emit = { self.on[1] * 1.8, self.on[2] * 1.8, self.on[3] * 1.8 } })
                else A.material(sg.obj, { emit = { 0, 0, 0 } }) end
            end
        end
    end
end

function D:setColor(c)
    self.on = c
    local v = self.value
    self.value = nil
    -- forca redesenho
    for i = 1, self.n do for _, k in ipairs(ORDER) do self.segs[i][k].lit = false; A.color(self.segs[i][k].obj, self.off) end end
    if v then self:set(v) end
end

-- reposiciona (para displays presos em objetos que se movem)
function D:place(pos, basis)
    A.pos(self.root, pos)
    A.rotBasis(self.root, basis)
end

function D:destroy()
    A.destroy(self.root)
end

return D
