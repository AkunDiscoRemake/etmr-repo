-- catalog.lua — todos os brainrots (SO os italianos), raridades e mutacoes.
-- Precos e renda baseados na wiki do Steal a Brainrot (valores aproximados).

local K = {}

-- ordem = valor crescente. w = peso de sorteio na esteira. size = altura do modelo (m)
K.RARITIES = {
    { id = "common",    w = 55,    size = 0.62, color = { 0.62, 0.64, 0.68 } },
    { id = "rare",      w = 26,    size = 0.72, color = { 0.25, 0.55, 1.00 } },
    { id = "epic",      w = 12,    size = 0.82, color = { 0.66, 0.30, 0.95 } },
    { id = "legendary", w = 5,     size = 0.95, color = { 1.00, 0.80, 0.15 } },
    { id = "mythic",    w = 1.6,   size = 1.05, color = { 1.00, 0.22, 0.22 } },
    { id = "god",       w = 0.35,  size = 1.20, color = { 1.00, 0.55, 0.95 } },
    { id = "secret",    w = 0.05,  size = 1.35, color = { 0.10, 0.10, 0.12 } },
}
K.RAR = {}
for i, r in ipairs(K.RARITIES) do r.index = i; K.RAR[r.id] = r end

-- mutacoes: multiplicador de renda
K.MUTATIONS = {
    none      = { mult = 1 },
    gold      = { mult = 1.25 },
    diamond   = { mult = 1.5 },
    halloween = { mult = 3 },
    candy     = { mult = 4 },
    lava      = { mult = 6 },
    rainbow   = { mult = 10 },
}
K.MUT_ORDER = { "gold", "diamond", "halloween", "candy", "lava", "rainbow" }

-- { id, nome, raridade, preco, renda/s }
local LIST = {
    -- COMMON
    { "noobini",      "Noobini Pizzanini",          "common", 25, 1 },
    { "lirili",       "Lirilì Larilà",              "common", 250, 3 },
    { "timcheese",    "Tim Cheese",                 "common", 500, 5 },
    { "fluriflura",   "Fluriflura",                 "common", 750, 7 },
    { "talpa",        "Talpa Di Fero",              "common", 1000, 9 },
    { "svinina",      "Svinina Bombardino",         "common", 1200, 10 },
    { "pipikiwi",     "Pipi Kiwi",                  "common", 1500, 13 },
    -- RARE
    { "trippi",       "Trippi Troppi",              "rare", 2000, 15 },
    { "footera",      "Gangster Footera",           "rare", 4000, 30 },
    { "bobritto",     "Bandito Bobritto",           "rare", 4500, 35 },
    { "cactohippo",   "Cacto Hipopotamo",           "rare", 6500, 50 },
    { "trictrac",     "Tric Trac Baraboom",         "rare", 9000, 65 },
    -- EPIC
    { "cappuccino",   "Cappuccino Assassino",       "epic", 10000, 75 },
    { "patapim",      "Brr Brr Patapim",            "epic", 15000, 100 },
    { "trulimero",    "Trulimero Trulicina",        "epic", 20000, 125 },
    { "bambini",      "Bambini Crostini",           "epic", 22500, 130 },
    { "bananita",     "Bananita Dolphinita",        "epic", 25000, 150 },
    { "perochello",   "Perochello Lemonchello",     "epic", 27500, 160 },
    { "bicus",        "Brri Brri Bicus Dicus Bombicus", "epic", 30000, 175 },
    { "avocadini",    "Avocadini Guffo",            "epic", 35000, 225 },
    { "salamino",     "Salamino Penguino",          "epic", 40000, 250 },
    -- LEGENDARY
    { "burbaloni",    "Burbaloni Loliloli",         "legendary", 35000, 200 },
    { "chimpbanana",  "Chimpanzini Bananini",       "legendary", 50000, 300 },
    { "ballerina",    "Ballerina Cappuccina",       "legendary", 100000, 500 },
    { "chefcrab",     "Chef Crabracadabra",         "legendary", 150000, 600 },
    { "lionel",       "Lionel Cactuseli",           "legendary", 175000, 650 },
    { "glorbo",       "Glorbo Fruttodrillo",        "legendary", 200000, 750 },
    { "blueberry",    "Blueberrinni Octopusini",    "legendary", 250000, 1000 },
    { "strawberry",   "Strawberelli Flamingelli",   "legendary", 275000, 1100 },
    -- MYTHIC
    { "frigo",        "Frigo Camelo",               "mythic", 300000, 1400 },
    { "orangutini",   "Orangutini Ananassini",      "mythic", 400000, 1700 },
    { "rhino",        "Rhino Toasterino",           "mythic", 450000, 2100 },
    { "bombardiro",   "Bombardiro Crocodilo",       "mythic", 500000, 2500 },
    { "spioniro",     "Spioniro Golubiro",          "mythic", 750000, 3500 },
    { "bombombini",   "Bombombini Gusini",          "mythic", 1000000, 5000 },
    { "zibra",        "Zibra Zubra Zibralini",      "mythic", 1000000, 6000 },
    { "tigrilini",    "Tigrilini Watermelini",      "mythic", 1000000, 6500 },
    { "cavallo",      "Cavallo Virtuoso",           "mythic", 2500000, 7500 },
    -- BRAINROT GOD
    { "cocofanto",    "Cocofanto Elefanto",         "god", 5000000, 10000 },
    { "girafa",       "Girafa Celestre",            "god", 7500000, 20000 },
    { "gattatino",    "Gattatino Neonino",          "god", 7500000, 35000 },
    { "tralalero",    "Tralalero Tralala",          "god", 10000000, 50000 },
    { "matteo",       "Matteo",                     "god", 10000000, 50000 },
    { "crocodillitos","Los Crocodillitos",          "god", 12500000, 55000 },
    { "odin",         "Odin Din Din Dun",           "god", 15000000, 75000 },
    { "orcalero",     "Orcalero Orcala",            "god", 15000000, 100000 },
    { "espresso",     "Espresso Signora",           "god", 25000000, 70000 },
    { "treno",        "Trenostruzzo Turbo 3000",    "god", 25000000, 150000 },
    -- SECRET
    { "vacca",        "La Vacca Saturno Saturnita", "secret", 50000000, 250000 },
    { "spiderini",    "Chimpanzini Spiderini",      "secret", 100000000, 325000 },
    { "tralaleritos", "Los Tralaleritos",           "secret", 100000000, 500000 },
    { "tralaleritas", "Las Tralaleritas",           "secret", 150000000, 650000 },
    { "graipuss",     "Graipuss Medussi",           "secret", 250000000, 1000000 },
    { "combinasion",  "La Grande Combinasion",      "secret", 1000000000, 10000000 },
    { "nuclearo",     "Nuclearo Dinossauro",        "secret", 2500000000, 15000000 },
    { "dragon",       "Dragon Cannelloni",          "secret", 10000000000, 100000000 },
}

K.list = {}
K.byId = {}
K.byRarity = {}
for i, e in ipairs(LIST) do
    local d = { id = e[1], name = e[2], rarity = e[3], price = e[4], income = e[5], index = i }
    d.rar = K.RAR[d.rarity]
    K.list[i] = d
    K.byId[d.id] = d
    local br = K.byRarity[d.rarity] or {}
    br[#br + 1] = d
    K.byRarity[d.rarity] = br
end

-- renda de um brainrot (com mutacao)
function K.income(id, mut)
    local d = K.byId[id]
    if not d then return 0 end
    local m = K.MUTATIONS[mut or "none"] or K.MUTATIONS.none
    return d.income * m.mult
end

-- preco de compra (mutacao encarece igual a renda)
function K.price(id, mut)
    local d = K.byId[id]
    if not d then return 0 end
    local m = K.MUTATIONS[mut or "none"] or K.MUTATIONS.none
    return math.floor(d.price * m.mult + 0.5)
end

-- valor de venda: metade do preco
function K.sellValue(id, mut) return math.floor(K.price(id, mut) * 0.5) end

-- Sorteio de raridade. luck >= 1 empurra o peso para raridades maiores.
function K.rollRarity(rand, luck)
    luck = luck or 1
    local total = 0
    local ws = {}
    for i, r in ipairs(K.RARITIES) do
        local w = r.w
        if i >= 2 then w = w * luck ^ (0.6 + (i - 2) * 0.25) end
        ws[i] = w
        total = total + w
    end
    local x = rand() * total
    for i, r in ipairs(K.RARITIES) do
        x = x - ws[i]
        if x <= 0 then return r.id end
    end
    return "common"
end

-- Sorteia um brainrot da raridade; dentro da raridade os mais baratos sao mais comuns.
function K.rollBrainrot(rand, luck)
    local rar = K.rollRarity(rand, luck)
    local list = K.byRarity[rar]
    local total = 0
    for i = 1, #list do total = total + 1 / i end
    local x = rand() * total
    for i = 1, #list do
        x = x - 1 / i
        if x <= 0 then return list[i].id end
    end
    return list[1].id
end

-- mutacao: chances base + bonus do evento ativo
function K.rollMutation(rand, eventMut, eventChance)
    if eventMut and rand() < (eventChance or 0) then return eventMut end
    local x = rand()
    if x < 0.003 then return "rainbow" end
    if x < 0.023 then return "diamond" end
    if x < 0.083 then return "gold" end
    return "none"
end

-- formata dinheiro: 1234 -> 1.2K, 1500000 -> 1.5M
function K.fmt(v)
    v = math.floor(v + 0.5)
    local a = math.abs(v)
    local s
    if a < 1000 then s = tostring(a)
    else
        local units = { { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
        for _, u in ipairs(units) do
            if a >= u[1] then
                local x = a / u[1]
                if x >= 100 then s = string.format("%d", math.floor(x))
                elseif x >= 10 then s = string.format("%.1f", math.floor(x * 10) / 10)
                else s = string.format("%.2f", math.floor(x * 100) / 100) end
                if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
                s = s .. u[2]
                break
            end
        end
    end
    if v < 0 then s = "-" .. s end
    return s
end

return K
