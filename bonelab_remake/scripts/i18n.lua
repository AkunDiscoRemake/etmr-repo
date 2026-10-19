-- i18n.lua — traducoes (English / Русский / Portugues).
-- Textos de UI vem daqui; texturas com texto existem em uma versao por idioma
-- (images/<nome>_<lang>.png). Trocar de idioma reaplica tudo na hora.

local A = require("api")

local T = {}

T.LANGS = { "en", "ru", "pt" }
T.lang = "en"

local S = {
    -- mensagens (painel de status + placa grande)
    welcome = { en = "WELCOME TO THE LAB", ru = "ДОБРО ПОЖАЛОВАТЬ В ЛАБОРАТОРИЮ", pt = "BEM-VINDO AO LAB" },
    hub = { en = "LABORATORY", ru = "ЛАБОРАТОРИЯ", pt = "LABORATÓRIO" },
    sandbox = { en = "SANDBOX: press GRUNT/GUNNER/CRAB on the console", ru = "ПЕСОЧНИЦА: жми ГРАНТ/СТРЕЛОК/КРАБ на пульте", pt = "SANDBOX: aperte GRUNT/ATIRADOR/CRAB no console" },
    wave = { en = "WAVE %d", ru = "ВОЛНА %d", pt = "ONDA %d" },
    clear = { en = "WAVE CLEARED!", ru = "ВОЛНА ПРОЙДЕНА!", pt = "ONDA COMPLETA!" },
    record = { en = "NEW RECORD!", ru = "НОВЫЙ РЕКОРД!", pt = "NOVO RECORDE!" },
    gameover = { en = "YOU DIED - GAME OVER", ru = "ТЫ ПОГИБ - ИГРА ОКОНЧЕНА", pt = "VOCÊ MORREU - FIM DE JOGO" },
    dead = { en = "YOU DIED", ru = "ТЫ ПОГИБ", pt = "VOCÊ MORREU" },
    crab = { en = "PULL THE CRAB OFF YOUR FACE!", ru = "СОРВИ КРАБА С ЛИЦА!", pt = "ARRANQUE O CRAB DO ROSTO!" },
    calib = { en = "CALIBRATING JOY-CON", ru = "НАСТРОЙКА JOY-CON", pt = "CALIBRANDO JOY-CON" },
    padFound = { en = "Joy-Con detected! Press JOY-CON on the console", ru = "Найден Joy-Con! Нажми JOY-CON на пульте", pt = "Joy-Con detectado! Aperte JOY-CON no console" },
    langSet = { en = "Language: English", ru = "Язык: Русский", pt = "Idioma: Português" },

    -- painel de UI
    title = { en = "BONELAB REMAKE  |  LAB", ru = "BONELAB REMAKE  |  ЛАБОРАТОРИЯ", pt = "BONELAB REMAKE  |  LAB" },
    intro = { en = "Grab a gun from the table. Press the console buttons with your finger.", ru = "Возьми оружие со стола. Нажимай кнопки пульта пальцем.", pt = "Pegue uma arma na mesa. Aperte os botões do console com o dedo." },
    padSearch = { en = "Joy-Con: searching...", ru = "Joy-Con: поиск...", pt = "Joy-Con: procurando..." },
    padOn = { en = "Joy-Con connected: %s", ru = "Joy-Con подключён: %s", pt = "Joy-Con conectado: %s" },
    padOff = { en = "No Joy-Con: using hand gestures", ru = "Нет Joy-Con: управление жестами", pt = "Sem Joy-Con: usando gestos das mãos" },
    padCal = { en = "Joy-Con: calibrating...", ru = "Joy-Con: настройка...", pt = "Joy-Con: calibrando..." },
    bWaves = { en = "WAVES mode", ru = "Режим ВОЛН", pt = "Modo ONDAS" },
    bSandbox = { en = "SANDBOX", ru = "ПЕСОЧНИЦА", pt = "SANDBOX" },
    bCalib = { en = "Calibrate Joy-Con", ru = "Настроить Joy-Con", pt = "Calibrar Joy-Con" },
    bRecenter = { en = "Recenter", ru = "Центрировать", pt = "Recentralizar" },
    bLang = { en = "Language: EN", ru = "Язык: RU", pt = "Idioma: PT" },
    bClose = { en = "Close menu", ru = "Закрыть меню", pt = "Fechar menu" },
    tAim = { en = "Aim assist", ru = "Помощь в прицеливании", pt = "Mira assistida" },
    tWalk = { en = "Walk by pointing", ru = "Ходьба жестом", pt = "Andar com gesto" },
    tMR = { en = "See my room (MR)", ru = "Видеть комнату (MR)", pt = "Ver o quarto (MR)" },
    tSmooth = { en = "Smooth turn", ru = "Плавный поворот", pt = "Virar suave" },
    tSticky = { en = "Toggle grab (stays in hand)", ru = "Хват-переключатель", pt = "Pegar alternado (fica na mão)" },
    sHeight = { en = "Height (m)", ru = "Рост (м)", pt = "Altura (m)" },
    sSpeed = { en = "Speed", ru = "Скорость", pt = "Velocidade" },
    sMusic = { en = "Music", ru = "Музыка", pt = "Música" },

    -- calibracao do Joy-Con
    cal_right_trigger = { en = "RIGHT Joy-Con:\npress the TRIGGER (ZR)", ru = "ПРАВЫЙ Joy-Con:\nнажми КУРОК (ZR)", pt = "Joy-Con DIREITO:\naperte o GATILHO (ZR)" },
    cal_right_grip = { en = "RIGHT Joy-Con:\npress the GRAB button (R)", ru = "ПРАВЫЙ Joy-Con:\nнажми кнопку ХВАТА (R)", pt = "Joy-Con DIREITO:\naperte o botão de PEGAR (R)" },
    cal_right_primary = { en = "RIGHT Joy-Con:\npress MAGAZINE RELEASE (A)", ru = "ПРАВЫЙ Joy-Con:\nнажми СБРОС МАГАЗИНА (A)", pt = "Joy-Con DIREITO:\naperte SOLTAR O PENTE (A)" },
    cal_left_trigger = { en = "LEFT Joy-Con:\npress the TRIGGER (ZL)", ru = "ЛЕВЫЙ Joy-Con:\nнажми КУРОК (ZL)", pt = "Joy-Con ESQUERDO:\naperte o GATILHO (ZL)" },
    cal_left_grip = { en = "LEFT Joy-Con:\npress the GRAB button (L)", ru = "ЛЕВЫЙ Joy-Con:\nнажми кнопку ХВАТА (L)", pt = "Joy-Con ESQUERDO:\naperte o botão de PEGAR (L)" },
    cal_left_primary = { en = "LEFT Joy-Con:\npress the SECONDARY button (down arrow)", ru = "ЛЕВЫЙ Joy-Con:\nнажми ДОП. кнопку (стрелка вниз)", pt = "Joy-Con ESQUERDO:\naperte o botão SECUNDÁRIO (seta baixo)" },
    cal_turnR = { en = "RIGHT Joy-Con:\nbutton to TURN RIGHT (X)\n(optional)", ru = "ПРАВЫЙ Joy-Con:\nкнопка ПОВОРОТ ВПРАВО (X)\n(необязательно)", pt = "Joy-Con DIREITO:\nbotão para VIRAR À DIREITA (X)\n(opcional)" },
    cal_turnL = { en = "RIGHT Joy-Con:\nbutton to TURN LEFT (Y)\n(optional)", ru = "ПРАВЫЙ Joy-Con:\nкнопка ПОВОРОТ ВЛЕВО (Y)\n(необязательно)", pt = "Joy-Con DIREITO:\nbotão para VIRAR À ESQUERDA (Y)\n(opcional)" },
    cal_walk = { en = "LEFT Joy-Con:\nbutton to WALK (hold)\nonly if the stick doesn't work (optional)", ru = "ЛЕВЫЙ Joy-Con:\nкнопка ХОДЬБЫ (держать)\nесли стик не работает (необязательно)", pt = "Joy-Con ESQUERDO:\nbotão para ANDAR (segurar)\nsó se o analógico não funcionar (opcional)" },
    cal_menu = { en = "LEFT Joy-Con:\nMENU button (-)\n(optional)", ru = "ЛЕВЫЙ Joy-Con:\nкнопка МЕНЮ (-)\n(необязательно)", pt = "Joy-Con ESQUERDO:\nbotão de MENU (-)\n(opcional)" },
    calSkip = { en = "(skips in %ds)", ru = "(пропуск через %d с)", pt = "(pula em %ds)" },
    calNoAccess = { en = "Joy-Con: the platform blocked gamepad access\n(CS.UnityEngine.Input).\nUse hand gestures.", ru = "Joy-Con: платформа не дала доступ к геймпаду\n(CS.UnityEngine.Input).\nИспользуй жесты рук.", pt = "Joy-Con: a plataforma não liberou acesso\nao gamepad (CS.UnityEngine.Input).\nUse os gestos das mãos." },
    calDone = { en = "Joy-Con calibrated!\nTrigger = shoot, Grab = hold.\nStick = walk.", ru = "Joy-Con настроен!\nКурок = стрелять, Хват = держать.\nСтик = ходьба.", pt = "Joy-Con calibrado!\nGatilho = atirar, Pegar = segurar.\nAnalógico = andar." },
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

-- idioma inicial: escolha salva > idioma do teclado da plataforma > ingles
function T.init()
    local saved = A.getStr("lang", "")
    if saved ~= "" then
        T.lang = saved
        return
    end
    local ok, kb = pcall(function() return EMRAPI.Keyboard:GetLanguage() end)
    if ok and (kb == "ru" or kb == "en") then T.lang = kb else T.lang = "en" end
end

return T
