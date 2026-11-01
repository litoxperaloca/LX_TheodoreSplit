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
