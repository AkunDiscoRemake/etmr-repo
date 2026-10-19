-- text3d.lua — texto dinamico no mundo 3D feito com quads de letras (images/font/*.png).
-- Cada letra e uma textura branca com contorno (fundo transparente com shader unlit;
-- sem ele, fundo escuro). A cor e aplicada com SetColor.
-- O quad da Unity e visivel pelo lado -Z: o texto le certo para quem esta em -Z olhando +Z.

local A = require("api")

local T = {}

local NAMES = {
    ["$"] = "dollar", ["."] = "dot", [","] = "comma", [":"] = "colon", ["/"] = "slash",
    ["+"] = "plus", ["-"] = "minus", ["_"] = "under", ["!"] = "excl", ["?"] = "quest",
    ["x"] = "x", ["%"] = "pct", ["#"] = "hash", ["("] = "lpar", [")"] = "rpar", [" "] = "space",
}
T.CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ$.,:/+-_!?x%#() "

function T.glyphFile(ch)
    local n = NAMES[ch]
    if n == nil then
        if ch:match("%d") then n = ch
        elseif ch:match("%a") then n = ch:upper() end
    end
    return "images/font/" .. (n or "quest") .. ".png"
end

-- normaliza: maiusculas, menos o "x" de multiplicador; troca o que nao existe por "?"
local function norm(str)
    local out = {}
    for ch in tostring(str):gmatch(".") do
        local c = ch
        if c ~= "x" then c = c:upper() end
        if not T.CHARSET:find(c, 1, true) then c = "?" end
        out[#out + 1] = c
    end
    return out
end

-- opt: parent, pos, h (altura da letra), color, align ("center"|"left"|"right"), bg (cor do fundo extra)
function T.new(opt)
    local t = {
        root = A.empty("text", opt.parent, opt.pos),
        h = opt.h or 0.2, color = opt.color or { 1, 1, 1 }, align = opt.align or "center",
        quads = {}, str = nil, n = 0,
    }
    if opt.str then T.set(t, opt.str) end
    return t
end

function T.set(t, str, color)
    str = tostring(str)
    if color then t.color = color end
    if str == t.str and not color then return end
    t.str = str
    local chars = norm(str)
    local n = #chars
    local w = t.h * 0.62
    local total = n * w
    local x0
    if t.align == "left" then x0 = w / 2
    elseif t.align == "right" then x0 = -total + w / 2
    else x0 = -total / 2 + w / 2 end
    for i = 1, n do
        local q = t.quads[i]
        if not q then
            q = { o = A.prim("quad", { parent = t.root, scale = { w, t.h, 1 } }) }
            A.uiQuad(q.o)
            t.quads[i] = q
        end
        if q.hidden then A.setVisible(q.o, true, w, t.h, 1); q.hidden = false end
        A.posXYZ(q.o, x0 + (i - 1) * w, 0, 0)
        if q.ch ~= chars[i] then
            q.ch = chars[i]
            A.texture(q.o, T.glyphFile(chars[i]))
        end
        if q.col ~= t.color then
            q.col = t.color
            A.color(q.o, t.color)
        end
    end
    for i = n + 1, #t.quads do
        local q = t.quads[i]
        if not q.hidden then A.setVisible(q.o, false); q.hidden = true end
    end
    t.n = n
    t.width = total
end

function T.setColor(t, color)
    t.color = color
    for i = 1, t.n do
        local q = t.quads[i]
        if q.col ~= color then q.col = color; A.color(q.o, color) end
    end
end

function T.destroy(t) if t and t.root then A.destroy(t.root) end end

return T
