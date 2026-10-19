-- i18n.lua — traducoes (English / Русский / Portugues). Ingles e o padrao.
-- Textos do menu vem daqui; placas e avisos 3D sao texturas por idioma
-- (images/<nome>_<lang>.png, geradas por tools/gen_textures.py).

local A = require("api")

local T = {}

T.LANGS = { "en", "ru", "pt" }
T.lang = "en"

local S = {
    title = { en = "RE:STEAL A BRAINROT VR", ru = "RE:STEAL A BRAINROT VR", pt = "RE:STEAL A BRAINROT VR" },
    st_offline = { en = "Offline - connecting...", ru = "Нет сети - подключение...", pt = "Offline - conectando..." },
    st_connecting = { en = "Connecting...", ru = "Подключение...", pt = "Conectando..." },
    st_online = { en = "ONLINE: room %s (%d players)", ru = "ОНЛАЙН: комната %s (%d игроков)", pt = "ONLINE: sala %s (%d jogadores)" },
    st_money = { en = "Money: $%s   Rebirths: %d", ru = "Деньги: $%s   Перерождения: %d", pt = "Dinheiro: $%s   Renascimentos: %d" },
    padSearch = { en = "Joy-Con: searching...", ru = "Joy-Con: поиск...", pt = "Joy-Con: procurando..." },
    padOn = { en = "Joy-Con: %s", ru = "Joy-Con: %s", pt = "Joy-Con: %s" },
    padOff = { en = "No Joy-Con (hand gestures work too)", ru = "Нет Joy-Con (работают жесты рук)", pt = "Sem Joy-Con (gestos das mãos funcionam)" },
    padCal = { en = "Joy-Con: calibrating...", ru = "Joy-Con: настройка...", pt = "Joy-Con: calibrando..." },
    bReconnect = { en = "Reconnect / new room", ru = "Переподключиться", pt = "Reconectar / outra sala" },
    bAvatar = { en = "Avatar: Bacon / Acorn", ru = "Аватар: Bacon / Acorn", pt = "Avatar: Bacon / Acorn" },
    bCalib = { en = "Calibrate Joy-Con", ru = "Настроить Joy-Con", pt = "Calibrar Joy-Con" },
    bLang = { en = "Language: EN", ru = "Язык: RU", pt = "Idioma: PT" },
    bRecenter = { en = "Recenter", ru = "Центрировать", pt = "Recentralizar" },
    bClose = { en = "Close menu", ru = "Закрыть меню", pt = "Fechar menu" },
    tSmooth = { en = "Smooth turn", ru = "Плавный поворот", pt = "Virar suave" },
    tWalk = { en = "Walk by pointing", ru = "Ходьба жестом", pt = "Andar com gesto" },
    tVoice = { en = "Voice chat", ru = "Голосовой чат", pt = "Chat de voz" },
    sHeight = { en = "Height", ru = "Рост", pt = "Altura" },
    sSpeed = { en = "Walk speed", ru = "Скорость", pt = "Velocidade" },
    sMusic = { en = "Music", ru = "Музыка", pt = "Música" },
    cal_right_trigger = { en = "RIGHT Joy-Con:\npress USE / SWING (ZR)", ru = "ПРАВЫЙ Joy-Con:\nнажми УДАР (ZR)", pt = "Joy-Con DIREITO:\naperte USAR / BATER (ZR)" },
    cal_right_grip = { en = "RIGHT Joy-Con:\npress HOLD / INTERACT (R)", ru = "ПРАВЫЙ Joy-Con:\nнажми ДЕЙСТВИЕ (R)", pt = "Joy-Con DIREITO:\naperte SEGURAR / INTERAGIR (R)" },
    cal_right_primary = { en = "RIGHT Joy-Con:\npress JUMP (A)", ru = "ПРАВЫЙ Joy-Con:\nнажми ПРЫЖОК (A)", pt = "Joy-Con DIREITO:\naperte PULAR (A)" },
    cal_left_trigger = { en = "LEFT Joy-Con:\npress NEXT ITEM (ZL)", ru = "ЛЕВЫЙ Joy-Con:\nнажми СЛЕД. ПРЕДМЕТ (ZL)", pt = "Joy-Con ESQUERDO:\naperte PRÓXIMO ITEM (ZL)" },
    cal_left_grip = { en = "LEFT Joy-Con:\npress HOLD / INTERACT (L)", ru = "ЛЕВЫЙ Joy-Con:\nнажми ДЕЙСТВИЕ (L)", pt = "Joy-Con ESQUERDO:\naperte SEGURAR / INTERAGIR (L)" },
    cal_left_primary = { en = "LEFT Joy-Con:\npress JUMP (down arrow)\n(optional)", ru = "ЛЕВЫЙ Joy-Con:\nнажми ПРЫЖОК (стрелка вниз)\n(необязательно)", pt = "Joy-Con ESQUERDO:\naperte PULAR (seta baixo)\n(opcional)" },
    cal_turnR = { en = "RIGHT Joy-Con:\nbutton to TURN RIGHT (X)\n(optional)", ru = "ПРАВЫЙ Joy-Con:\nкнопка ПОВОРОТ ВПРАВО (X)\n(необязательно)", pt = "Joy-Con DIREITO:\nbotão VIRAR À DIREITA (X)\n(opcional)" },
    cal_turnL = { en = "RIGHT Joy-Con:\nbutton to TURN LEFT (Y)\n(optional)", ru = "ПРАВЫЙ Joy-Con:\nкнопка ПОВОРОТ ВЛЕВО (Y)\n(необязательно)", pt = "Joy-Con DIREITO:\nbotão VIRAR À ESQUERDA (Y)\n(opcional)" },
    cal_walk = { en = "LEFT Joy-Con:\nbutton to WALK (hold)\nonly if the stick doesn't work (optional)", ru = "ЛЕВЫЙ Joy-Con:\nкнопка ХОДЬБЫ (держать)\nесли стик не работает (необязательно)", pt = "Joy-Con ESQUERDO:\nbotão ANDAR (segurar)\nsó se o analógico não funcionar (opcional)" },
    cal_menu = { en = "LEFT Joy-Con:\nMENU button (-)\n(optional)", ru = "ЛЕВЫЙ Joy-Con:\nкнопка МЕНЮ (-)\n(необязательно)", pt = "Joy-Con ESQUERDO:\nbotão MENU (-)\n(opcional)" },
    calSkip = { en = "(skipping in %d s)", ru = "(пропуск через %d с)", pt = "(pulando em %d s)" },
    calNoAccess = { en = "Joy-Con: the platform blocked gamepad access\n(CS.UnityEngine.Input).\nUse hand gestures.", ru = "Joy-Con: платформа не дала доступ к геймпаду\n(CS.UnityEngine.Input).\nИспользуй жесты рук.", pt = "Joy-Con: a plataforma não liberou o gamepad\n(CS.UnityEngine.Input).\nUse os gestos das mãos." },
    calDone = { en = "Joy-Con calibrated!\nStick = walk, R/L = hold, ZR = swing, A = jump.", ru = "Joy-Con настроен!\nСтик = ходьба, R/L = держать, ZR = удар, A = прыжок.", pt = "Joy-Con calibrado!\nAnalógico = andar, R/L = segurar, ZR = bater, A = pular." },
}

function T.t(key, ...)
    local e = S[key]
    if not e then return key end
    local s = e[T.lang] or e.en or key
    if select("#", ...) > 0 then
        local ok, r = pcall(string.format, s, ...)
        if ok then return r end
    end
    return s
end

-- caminho da textura no idioma atual
function T.tex(key)
    return "images/" .. key .. "_" .. T.lang .. ".png"
end

-- objetos 3D com textura de texto, reaplicados ao trocar de idioma
local bound = {}
function T.bindTex(obj, key)
    bound[#bound + 1] = { obj = obj, key = key }
    A.texture(obj, T.tex(key))
end

local listeners = {}
function T.onChange(fn) listeners[#listeners + 1] = fn end

function T.set(lang)
    local ok = false
    for _, l in ipairs(T.LANGS) do if l == lang then ok = true end end
    if not ok then lang = "en" end
    T.lang = lang
    A.setStr("lang", lang)
    A.save()
    for _, b in ipairs(bound) do A.texture(b.obj, T.tex(b.key)) end
    for _, fn in ipairs(listeners) do pcall(fn, lang) end
end

function T.cycle()
    local idx = 1
    for i, l in ipairs(T.LANGS) do if l == T.lang then idx = i end end
    T.set(T.LANGS[idx % #T.LANGS + 1])
end

-- idioma inicial: INGLES por padrao; so muda se o jogador escolheu outro (fica salvo)
function T.init()
    local saved = A.getStr("lang", "")
    T.lang = "en"
    for _, l in ipairs(T.LANGS) do
        if l == saved then T.lang = saved end
    end
end

return T
