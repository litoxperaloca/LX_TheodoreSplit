--[[
    LX_TheodoreSplit - nucleo.

    Theodore esta escrito para un solo jugador: llama a getPlayer() en 166 lugares,
    y en pantalla dividida esa funcion devuelve un unico jugador. El resultado es que
    Theodore solo percibe a uno de los jugadores locales y el resto no existe para el.

    Aca se resuelve separando dos ideas que el original mezcla en la misma llamada:

      LXTH.owner()  - el jugador "padre/madre": SIEMPRE el mismo (slot 0).
                      De el cuelgan los datos guardados de Theodore y si te dice
                      "Mom" o "Dad". Tiene que ser estable o las partidas se rompen.

      LXTH.near()   - el jugador local vivo mas cercano a Theodore.
                      Lo usa todo lo demas: distancias, hablar, mirar, reaccionar.

    Nada de este mod vive dentro de la carpeta de Theodore: los archivos originales se
    leen de la copia instalada, se parchean en memoria y se ejecutan desde ahi. Si
    Theodore se actualiza y un fragmento deja de coincidir, ese parche se omite, se
    avisa en console.txt y el archivo original sigue funcionando igual que siempre.
]]

LXTH = LXTH or {}
LXTH.TARGET_MOD = "Theodore"
LXTH.report = LXTH.report or {}

local function log(msg) print("[LX_TheodoreSplit] " .. tostring(msg)) end
LXTH.log = log

-- =====================================================================
-- Jugadores
-- =====================================================================

-- Jugadores locales existentes (los slots 0..3 pueden tener huecos).
function LXTH.localPlayers()
    local list = {}
    if type(getSpecificPlayer) ~= "function" then return list end
    for i = 0, 3 do
        local ok, p = pcall(getSpecificPlayer, i)
        if ok and p ~= nil then list[#list + 1] = p end
    end
    return list
end

local function alive(p)
    if p == nil then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and dead ~= true
end

-- El "padre": siempre el slot 0 mientras exista. De aca cuelgan los datos guardados
-- de Theodore, asi que no puede ir cambiando entre jugadores.
function LXTH.owner()
    local ok, p = pcall(getSpecificPlayer, 0)
    if ok and p ~= nil then return p end
    local list = LXTH.localPlayers()
    return list[1]
end

-- El cuerpo de Theodore, si ya aparecio.
function LXTH.body()
    if type(Theodore) ~= "table" or type(Theodore.getBody) ~= "function" then return nil end
    local ok, b = pcall(Theodore.getBody)
    if ok then return b end
    return nil
end

-- El jugador local vivo mas cercano a Theodore. Si todavia no aparecio, o no se puede
-- medir, cae al owner: nunca devuelve nil si hay algun jugador.
function LXTH.near()
    local list = LXTH.localPlayers()
    if #list <= 1 then return list[1] or LXTH.owner() end

    local body = LXTH.body()
    if body == nil then
        for _, p in ipairs(list) do
            if alive(p) then return p end
        end
        return LXTH.owner()
    end

    local best, bestD = nil, math.huge
    for _, p in ipairs(list) do
        if alive(p) then
            local ok, d = pcall(function() return body:DistTo(p) end)
            if ok and type(d) == "number" and d < bestD then best, bestD = p, d end
        end
    end
    return best or LXTH.owner()
end

-- Indice (0..3) del jugador que tiene que recibir el menu contextual. El original
-- lo tenia fijo en 0, asi que el jugador 2 no podia abrirlo ni con mouse ni con mando:
-- el menu de PZ se liga a un jugador y de ahi saca el foco del joypad.
function LXTH.playerNum()
    local p = LXTH.near()
    if p ~= nil then
        local ok, n = pcall(function() return p:getPlayerNum() end)
        if ok and type(n) == "number" and n >= 0 and n <= 3 then return n end
    end
    return 0
end

-- =====================================================================
-- Cargador de parches de texto
-- =====================================================================

local function readModFile(modId, rel)
    local ok, reader = pcall(getModFileReader, modId, rel, false)
    if not ok or not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return table.concat(lines, "\n") .. "\n"
end

local function escapePattern(s)
    return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", function(c) return "%" .. c end))
end

-- Reemplazo literal (sin patrones). Devuelve texto nuevo y cantidad de reemplazos.
local function plainReplace(src, find, repl)
    local pat = escapePattern(find)
    local parts, pos, count = {}, 1, 0
    while true do
        local s, e = string.find(src, pat, pos)
        if not s then break end
        parts[#parts + 1] = string.sub(src, pos, s - 1)
        parts[#parts + 1] = repl
        pos = e + 1
        count = count + 1
    end
    parts[#parts + 1] = string.sub(src, pos)
    return table.concat(parts), count
end

local function countOccurrences(src, find)
    local _, n = plainReplace(src, find, "")
    return n
end

LXTH._plainReplace = plainReplace -- expuesto para las pruebas

--[[
    rel     : ruta dentro del mod Theodore (p.ej. "media/lua/client/TheodoreNeeds.lua")
    patches : lista de { id=, find=, repl=, count= }
              count = numero exacto esperado, o "*" para "todas las que haya"
              (se usa "*" en las sustituciones mecanicas, que cambian de cantidad
              con cada version del mod pero siempre significan lo mismo)
]]
function LXTH.LoadPatched(rel, patches)
    local src = readModFile(LXTH.TARGET_MOD, rel)
    if not src then
        log("ERROR: no pude leer " .. rel .. " de " .. LXTH.TARGET_MOD ..
            ". Theodore activo? (archivo NO cargado)")
        return false
    end

    local applied, skipped, total = {}, {}, 0
    local patched = src
    for _, p in ipairs(patches) do
        local n = countOccurrences(patched, p.find)
        local ok
        if p.count == "*" then
            ok = n > 0
        else
            ok = (n == (p.count or 1))
        end
        if ok then
            patched = plainReplace(patched, p.find, p.repl)
            applied[#applied + 1] = p.id
            total = total + n
        elseif p.count == "*" and n == 0 then
            -- nada que cambiar en este archivo: no es un error
            applied[#applied + 1] = p.id .. "(0)"
        else
            skipped[#skipped + 1] = p.id .. " (encontrado " .. n .. ", esperado " .. tostring(p.count) .. ")"
        end
    end

    local chunk, err = loadstring(patched, "@Theodore/" .. rel)
    if not chunk then
        log("ERROR compilando " .. rel .. " parcheado: " .. tostring(err) ..
            " -> uso el ORIGINAL sin parches")
        chunk, err = loadstring(src, "@Theodore/" .. rel)
        applied, total = {}, 0
        if not chunk then
            log("ERROR compilando original " .. rel .. ": " .. tostring(err))
            return false
        end
    end

    LXTH.report[rel] = { applied = applied, skipped = skipped, changes = total }
    if #skipped > 0 then
        log(rel .. ": " .. total .. " cambios, OMITIDOS: " .. table.concat(skipped, "; "))
    end

    if LXTH.DRY_RUN then return true end -- usado solo por el test offline
    chunk()
    return true
end

-- Resumen al iniciar la partida (queda en console.txt)
if Events ~= nil and Events.OnGameStart ~= nil then
    Events.OnGameStart.Add(function()
        local files, changes, bad = 0, 0, 0
        for _, r in pairs(LXTH.report or {}) do
            files = files + 1
            changes = changes + (r.changes or 0)
            bad = bad + #r.skipped
        end
        log("pantalla dividida: " .. changes .. " cambios en " .. files .. " archivos" ..
            (bad > 0 and (", " .. bad .. " parches omitidos") or ""))
    end)
end

-- =====================================================================
-- Mitad de pantalla del jugador (interfaz)
-- =====================================================================
-- Theodore ubica su panel y su boton flotante contra la ventana ENTERA. En
-- pantalla dividida eso los manda a la mitad del otro jugador, o directamente
-- fuera de su vista. Aca se recortan contra el viewport del jugador que esta
-- usando la interfaz. Fuera de pantalla dividida el viewport ES la ventana
-- entera, asi que esto no cambia nada para quien juega solo.

-- Devuelve left, top, width, height del viewport del jugador.
function LXTH.viewport()
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    if type(getPlayerScreenWidth) ~= "function" then return 0, 0, sw, sh end

    local n = LXTH.playerNum()
    local okW, w = pcall(getPlayerScreenWidth, n)
    local okH, h = pcall(getPlayerScreenHeight, n)
    local okL, l = pcall(getPlayerScreenLeft, n)
    local okT, t = pcall(getPlayerScreenTop, n)
    if not (okW and okH and okL and okT) then return 0, 0, sw, sh end
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
        return 0, 0, sw, sh
    end
    return l or 0, t or 0, w, h
end

local function clamp(v, lo, hi)
    if hi < lo then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Deja un elemento de ancho w (alto h) dentro del viewport del jugador.
function LXTH.clampX(x, w)
    local l, _, vw, _ = LXTH.viewport()
    return math.floor(clamp(tonumber(x) or l, l, l + vw - (tonumber(w) or 0)))
end

function LXTH.clampY(y, h)
    local _, t, _, vh = LXTH.viewport()
    return math.floor(clamp(tonumber(y) or t, t, t + vh - (tonumber(h) or 0)))
end

-- =====================================================================
-- Navegacion del panel con mando
-- =====================================================================
-- El panel de Theodore son ISButton sueltos: con mouse andan, con mando no hay
-- forma de llegar a ellos. Aca se le agrega al panel, en caliente, un manejo de
-- joypad: arriba/abajo recorre los botones, A activa, B cierra.
--
-- Solo se toma el foco del mando si ese jugador REALMENTE tiene uno asignado:
-- si juega con teclado y mouse, el panel queda exactamente como estaba.

local function buttonsOf(panel)
    local list = {}
    local ok, kids = pcall(function() return panel:getChildren() end)
    if not ok or type(kids) ~= "table" then return list end
    for _, c in pairs(kids) do
        if type(c) == "table" and type(c.onclick) == "function"
                and type(c.getY) == "function" then
            local enabled = true
            if c.enable ~= nil then enabled = (c.enable == true) end
            if enabled then list[#list + 1] = c end
        end
    end
    table.sort(list, function(a, b)
        local ay, by = a:getY(), b:getY()
        if ay == by then return a:getX() < b:getX() end
        return ay < by
    end)
    return list
end

local function highlight(panel, list, index)
    for i, b in ipairs(list) do
        pcall(function()
            if i == index then
                b:setBorderRGBA(1.0, 0.82, 0.25, 1.0)
            else
                b:setBorderRGBA(0.45, 0.62, 0.80, 0.45)
            end
        end)
    end
    panel.lxthIndex = index
end

function LXTH.releaseJoypad(panel)
    pcall(function()
        if panel and panel.lxthJoypad ~= nil and type(setJoypadFocus) == "function" then
            setJoypadFocus(panel.lxthJoypad, nil)
        end
    end)
    if panel then panel.lxthJoypad = nil end
end

function LXTH.makeJoypadReady(panel)
    if panel == nil or panel.lxthJoypadReady then return end
    panel.lxthJoypadReady = true

    local n = LXTH.playerNum()
    -- Sin mando asignado a este jugador no tocamos nada.
    if type(getJoypadData) ~= "function" then return end
    local okJ, jd = pcall(getJoypadData, n)
    if not okJ or jd == nil then return end

    panel.playerNum = n
    panel.lxthJoypad = n
    panel.lxthIndex = 1

    function panel:onJoypadDown(button, joypadData)
        local ok, err = pcall(function()
            if Joypad == nil then return end
            local list = buttonsOf(self)
            if #list == 0 then
                if button == Joypad.BButton then
                    LXTH.releaseJoypad(self)
                    pcall(function() self:hide() end)
                end
                return
            end
            local i = clamp(self.lxthIndex or 1, 1, #list)

            if button == Joypad.DPadUp then
                highlight(self, list, i > 1 and i - 1 or #list)
            elseif button == Joypad.DPadDown then
                highlight(self, list, i < #list and i + 1 or 1)
            elseif button == Joypad.AButton then
                local b = list[i]
                if b then pcall(function() b.onclick(b.target, b) end) end
            elseif button == Joypad.BButton then
                LXTH.releaseJoypad(self)
                pcall(function() self:hide() end)
            end
        end)
        -- Ante cualquier problema soltamos el mando: un panel que se queda con el
        -- foco deja al jugador sin control, que es peor que no tener navegacion.
        if not ok then
            log("panel con mando: " .. tostring(err))
            LXTH.releaseJoypad(self)
        end
    end

    pcall(function() highlight(panel, buttonsOf(panel), 1) end)
    pcall(function()
        if type(setJoypadFocus) == "function" then setJoypadFocus(n, panel) end
    end)
end
