-- levels.lua — as 10 fases (dados). O jogador comeca em `player` olhando para +Z.
-- size = meia largura (x) e meio comprimento (z) da sala.
-- items: { tipo, x, y, z, yaw }   (y = altura da superficie onde o objeto esta)
-- spawns: { t = tempo de JOGO, x, z, w = arma ("pistol", "shotgun", "uzi", "katana", "none") }
--   se todos os inimigos vivos morrerem, o proximo spawn e adiantado.

local LV = {}

LV[1] = { -- O BAR: comece desarmado, arremesse a garrafa, pegue a arma no ar
    name = "lv1", size = { 4, 4 }, player = { 0, -3 },
    boxes = {
        { k = "counter", x = 0, z = 0.3, w = 3.2, d = 0.6 },
        { k = "stool", x = -1, z = -0.35 }, { k = "stool", x = 0, z = -0.35 }, { k = "stool", x = 1, z = -0.35 },
        { k = "table", x = -2.7, z = -2.6, w = 0.9, d = 0.9 },
        { k = "table", x = 2.7, z = -2.4, w = 0.9, d = 0.9 },
        { k = "block", x = 0, z = 3.65, w = 3.6, d = 0.6, h = 1.9 },
    },
    doors = { { wall = "n", at = -2.6 }, { wall = "e", at = 1.6 } },
    items = {
        { "bottle", -0.6, 1.05, 0.3 }, { "bottle", 0.7, 1.05, 0.3 }, { "ashtray", -2.7, 0.76, -2.6 },
        { "pistol", 2.7, 0.76, -2.4, 30 },
    },
    spawns = {
        { t = 0.4, x = -2.6, z = 3.4, w = "pistol" },
        { t = 2.5, x = 3.4, z = 1.6, w = "none" },
        { t = 5.5, x = -2.6, z = 3.4, w = "pistol" },
    },
}

LV[2] = { -- ELEVADOR: as portas abrem e eles ja estao la
    name = "lv2", size = { 5, 5 }, player = { 0, -4.2 },
    boxes = {
        { k = "block", x = -1.15, z = -4.1, w = 0.1, d = 1.8, h = 3.4 },
        { k = "block", x = 1.15, z = -4.1, w = 0.1, d = 1.8, h = 3.4 },
        { k = "stand", x = 0.75, z = -4.6 },
        { k = "pillar", x = -2.6, z = 0.6, w = 0.7 }, { k = "pillar", x = 2.6, z = 0.6, w = 0.7 },
        { k = "block", x = 0, z = 1.8, w = 1.6, d = 0.5, h = 1.0 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "w", at = 2 }, { wall = "e", at = 2 } },
    items = { { "pistol", 0.75, 0.9, -4.6, 90 }, { "ashtray", -0.4, 1.0, 1.8 } },
    spawns = {
        { t = 0.3, x = -2, z = 2.5, w = "pistol" }, { t = 0.3, x = 2, z = 2.8, w = "pistol" },
        { t = 0.6, x = 0, z = 4.4, w = "none" },
        { t = 4, x = -4.4, z = 2, w = "pistol" }, { t = 6, x = 4.4, z = 2, w = "pistol" },
    },
}

LV[3] = { -- ESCRITORIO: escopeta na mesa, telefones para arremessar
    name = "lv3", size = { 5, 5 }, player = { 0, -4 },
    boxes = {
        { k = "table", x = -2.2, z = -1.4, w = 1.4, d = 0.8 }, { k = "table", x = 2.2, z = -1.4, w = 1.4, d = 0.8 },
        { k = "table", x = -2.2, z = 1.6, w = 1.4, d = 0.8 }, { k = "table", x = 2.2, z = 1.6, w = 1.4, d = 0.8 },
        { k = "table", x = -0.9, z = -3.3, w = 0.8, d = 0.6 },
        { k = "block", x = 4.3, z = -3.5, w = 0.8, d = 1.6, h = 1.8 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "w", at = 1 }, { wall = "e", at = -1 } },
    items = {
        { "shotgun", -0.9, 0.76, -3.3, 80 }, { "phone", -2.2, 0.76, -1.4 }, { "phone", 2.2, 0.76, -1.4 },
        { "phone", -2.2, 0.76, 1.6 }, { "ashtray", 2.2, 0.76, 1.6 },
    },
    spawns = {
        { t = 0.5, x = 0, z = 4.4, w = "none" }, { t = 1.2, x = -4.4, z = 1, w = "pistol" },
        { t = 3, x = 4.4, z = -1, w = "pistol" }, { t = 5, x = 0, z = 4.4, w = "shotgun" },
        { t = 7, x = -4.4, z = 1, w = "none" },
    },
}

LV[4] = { -- CORREDOR: longo, com cobertura, uzi no comeco
    name = "lv4", size = { 1.7, 9 }, player = { 0, -8 },
    boxes = {
        { k = "stand", x = 1.1, z = -7.2 },
        { k = "block", x = -0.95, z = -3.5, w = 0.7, d = 0.7, h = 1.0 },
        { k = "block", x = 0.95, z = -0.5, w = 0.7, d = 0.7, h = 1.0 },
        { k = "block", x = -0.95, z = 2.8, w = 0.7, d = 0.7, h = 1.0 },
        { k = "block", x = 0.95, z = 5.6, w = 0.7, d = 0.7, h = 1.0 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "w", at = 4 } },
    items = { { "uzi", 1.1, 0.9, -7.2, 0 }, { "bottle", -0.95, 1.0, -3.5 }, { "bottle", 0.95, 1.0, -0.5 } },
    spawns = {
        { t = 0.5, x = 0, z = 8.4, w = "pistol" }, { t = 1.6, x = 0.8, z = 8.4, w = "pistol" },
        { t = 4, x = -1.1, z = 4, w = "uzi" }, { t = 5.5, x = 0, z = 8.4, w = "none" },
        { t = 7.5, x = 0, z = 8.4, w = "pistol" }, { t = 9, x = -1.1, z = 4, w = "none" },
    },
}

LV[5] = { -- DOJO: katana; corte as balas no ar
    name = "lv5", size = { 5, 5 }, player = { 0, -3.6 },
    boxes = {
        { k = "stand", x = 0, z = -2.6 },
        { k = "pillar", x = -3.2, z = -3.2, w = 0.5 }, { k = "pillar", x = 3.2, z = -3.2, w = 0.5 },
        { k = "pillar", x = -3.2, z = 3.2, w = 0.5 }, { k = "pillar", x = 3.2, z = 3.2, w = 0.5 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "w", at = 0 }, { wall = "e", at = 0 } },
    items = { { "katana", 0, 0.9, -2.6, 90 } },
    spawns = {
        { t = 0.5, x = -1.5, z = 4.4, w = "katana" }, { t = 1.2, x = 1.5, z = 4.4, w = "none" },
        { t = 3, x = 0, z = 4.4, w = "katana" }, { t = 5, x = -4.4, z = 0, w = "pistol" },
        { t = 6, x = 4.4, z = 0, w = "pistol" }, { t = 8, x = 0, z = 4.4, w = "katana" },
    },
}

LV[6] = { -- METRO: vagao estreito, inimigos dos dois lados
    name = "lv6", size = { 1.6, 8 }, player = { 0, -1 },
    boxes = {
        { k = "bench", x = -1.3, z = -4.5, w = 0.45, d = 3, back = -0.18, bw = 0.08, bd = 3 },
        { k = "bench", x = 1.3, z = -4.5, w = 0.45, d = 3, back = 0.18, bw = 0.08, bd = 3 },
        { k = "bench", x = -1.3, z = 2.5, w = 0.45, d = 3, back = -0.18, bw = 0.08, bd = 3 },
        { k = "bench", x = 1.3, z = 2.5, w = 0.45, d = 3, back = 0.18, bw = 0.08, bd = 3 },
        { k = "pole", x = -0.55, z = -3 }, { k = "pole", x = 0.55, z = 0.5 }, { k = "pole", x = -0.55, z = 4 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "s", at = 0 } },
    items = { { "pistol", 1.3, 0.45, -1.2, 0 }, { "bottle", -1.3, 0.45, 0.2 }, { "phone", 1.3, 0.45, 2.5 } },
    spawns = {
        { t = 0.5, x = 0, z = 7.4, w = "pistol" }, { t = 2.2, x = 0.6, z = 7.4, w = "pistol" },
        { t = 4, x = 0, z = -7.4, w = "none" }, { t = 6, x = 0, z = 7.4, w = "uzi" },
        { t = 7.5, x = 0, z = -7.4, w = "pistol" }, { t = 9, x = 0, z = 7.4, w = "katana" },
    },
}

LV[7] = { -- GALERIA: pedestais e escopetas
    name = "lv7", size = { 6, 6 }, player = { 0, -5 },
    boxes = {
        { k = "stand", x = -0.9, z = -4.2 },
        { k = "stand", x = -3, z = -1.5 }, { k = "stand", x = 3, z = -1.5 }, { k = "stand", x = 0, z = 0.8 },
        { k = "stand", x = -3, z = 3 }, { k = "stand", x = 3, z = 3 },
        { k = "block", x = -3, z = -1.5, w = 0.32, d = 0.32, h = 0.32, y0 = 0.9 },
        { k = "block", x = 3, z = 3, w = 0.25, d = 0.25, h = 0.55, y0 = 0.9 },
        { k = "block", x = 0, z = 4.6, w = 4, d = 0.3, h = 2.4 },
    },
    doors = { { wall = "n", at = -4 }, { wall = "n", at = 4 }, { wall = "w", at = 1 }, { wall = "e", at = 1 } },
    items = { { "shotgun", -0.9, 0.9, -4.2, 70 }, { "ashtray", 0, 0.9, 0.8 }, { "bottle", 3, 0.9, -1.5 } },
    spawns = {
        { t = 0.5, x = -4, z = 5.4, w = "shotgun" }, { t = 1, x = 4, z = 5.4, w = "pistol" },
        { t = 3, x = -5.4, z = 1, w = "none" }, { t = 4.5, x = 5.4, z = 1, w = "shotgun" },
        { t = 6.5, x = -4, z = 5.4, w = "pistol" }, { t = 8, x = 4, z = 5.4, w = "katana" },
    },
}

LV[8] = { -- ESTACIONAMENTO: carros como cobertura, uzis
    name = "lv8", size = { 7, 7 }, player = { 0, -6 },
    boxes = {
        { k = "car", x = -3.2, z = -2, yaw = 90 }, { k = "car", x = 3.4, z = 1.2, yaw = 90 },
        { k = "car", x = -2.8, z = 4, yaw = 90 },
        { k = "pillar", x = 0, z = 0, w = 0.8 }, { k = "pillar", x = -5, z = -4.5, w = 0.8 }, { k = "pillar", x = 5, z = -4.5, w = 0.8 },
        { k = "stand", x = 1, z = -5.2 },
    },
    doors = { { wall = "n", at = 0 }, { wall = "w", at = 2 }, { wall = "e", at = -2 } },
    items = { { "uzi", 1, 0.9, -5.2, 0 }, { "pistol", -1.7, 0.75, -2, 90 }, { "bottle", 4.9, 0.75, 1.2 } },
    spawns = {
        { t = 0.5, x = 0, z = 6.4, w = "uzi" }, { t = 1.5, x = -6.4, z = 2, w = "pistol" },
        { t = 3.5, x = 6.4, z = -2, w = "pistol" }, { t = 5, x = 0, z = 6.4, w = "none" },
        { t = 6.5, x = -6.4, z = 2, w = "uzi" }, { t = 8, x = 6.4, z = -2, w = "shotgun" },
        { t = 10, x = 0, z = 6.4, w = "katana" },
    },
}

LV[9] = { -- SALA DE SERVIDORES: corredores entre racks
    name = "lv9", size = { 5, 6 }, player = { 0, -5 },
    boxes = {
        { k = "rack", x = -3.2, z = 0.5, w = 0.7, d = 5 }, { k = "rack", x = -1.1, z = 0.5, w = 0.7, d = 5 },
        { k = "rack", x = 1.1, z = 0.5, w = 0.7, d = 5 }, { k = "rack", x = 3.2, z = 0.5, w = 0.7, d = 5 },
        { k = "stand", x = -0.8, z = -4.3 },
        { k = "table", x = 1.6, z = -4.2, w = 1, d = 0.6 },
    },
    doors = { { wall = "n", at = -2.1 }, { wall = "n", at = 2.1 }, { wall = "w", at = -3.5 }, { wall = "e", at = -3.5 } },
    items = { { "katana", -0.8, 0.9, -4.3, 90 }, { "pistol", 1.6, 0.76, -4.2, 20 }, { "phone", 1.9, 0.76, -4.2 } },
    spawns = {
        { t = 0.5, x = -2.1, z = 5.4, w = "pistol" }, { t = 1, x = 2.1, z = 5.4, w = "katana" },
        { t = 3, x = -4.4, z = -3.5, w = "none" }, { t = 4.5, x = 4.4, z = -3.5, w = "pistol" },
        { t = 6, x = -2.1, z = 5.4, w = "uzi" }, { t = 7.5, x = 2.1, z = 5.4, w = "shotgun" },
        { t = 9, x = 0, z = 5.4, w = "katana" },
    },
}

LV[10] = { -- O NUCLEO: arena final, todas as armas
    name = "lv10", size = { 6, 6 }, player = { 0, -4.6 },
    boxes = {
        { k = "pillar", x = 0, z = 0.8, w = 1.4 },
        { k = "block", x = -3, z = -1, w = 1.2, d = 0.5, h = 1 }, { k = "block", x = 3, z = -1, w = 1.2, d = 0.5, h = 1 },
        { k = "block", x = -3, z = 3, w = 0.5, d = 1.2, h = 1 }, { k = "block", x = 3, z = 3, w = 0.5, d = 1.2, h = 1 },
        { k = "stand", x = -1, z = -4 }, { k = "stand", x = 1, z = -4 },
    },
    doors = { { wall = "n", at = -3.5 }, { wall = "n", at = 3.5 }, { wall = "w", at = 0 }, { wall = "e", at = 0 }, { wall = "s", at = 3.5 } },
    items = {
        { "katana", -1, 0.9, -4, 90 }, { "shotgun", 1, 0.9, -4, 80 }, { "pistol", -3, 1.0, -1, 10 },
        { "uzi", 3, 1.0, -1, -10 }, { "bottle", -3, 1.0, 3 }, { "bottle", 3, 1.0, 3 },
    },
    spawns = {
        { t = 0.5, x = -3.5, z = 5.4, w = "pistol" }, { t = 0.8, x = 3.5, z = 5.4, w = "pistol" },
        { t = 2.5, x = -5.4, z = 0, w = "katana" }, { t = 3.5, x = 5.4, z = 0, w = "uzi" },
        { t = 5, x = -3.5, z = 5.4, w = "shotgun" }, { t = 6, x = 3.5, z = -5.4, w = "none" },
        { t = 7.5, x = 5.4, z = 0, w = "pistol" }, { t = 8.5, x = -5.4, z = 0, w = "uzi" },
        { t = 10, x = 3.5, z = 5.4, w = "katana" }, { t = 11, x = -3.5, z = 5.4, w = "shotgun" },
    },
}

LV.count = 10

-- portas da arena do modo infinito (usa o layout da fase 10)
LV.endlessDoors = { { -3.5, 5.4 }, { 3.5, 5.4 }, { -5.4, 0 }, { 5.4, 0 }, { 3.5, -5.4 } }

return LV
