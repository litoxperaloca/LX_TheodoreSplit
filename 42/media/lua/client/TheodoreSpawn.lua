-- LX_TheodoreSplit: reemplaza este archivo de Theodore por un cargador que lee el
-- ORIGINAL instalado (media/lua/client/TheodoreSpawn.lua), le aplica los cambios de pantalla
-- dividida en memoria y lo ejecuta. Si Theodore se actualiza y un fragmento deja de
-- coincidir, ese parche se omite y el codigo original corre igual.
-- Generado por gen_theodore.py - no editar a mano.
require "LXTH_Core"

LXTH.LoadPatched("media/lua/client/TheodoreSpawn.lua", {
    {  -- si te dice Mom o Dad: siempre el mismo jugador
        id = "identidad_padre", count = "*",
        find = [=[getPlayer():isFemale()]=],
        repl = [=[LXTH.owner():isFemale()]=],
    },
    {  -- los datos guardados de Theodore cuelgan siempre del mismo jugador
        id = "estado_guardado", count = "*",
        find = [=[getPlayer():getModData()]=],
        repl = [=[LXTH.owner():getModData()]=],
    },
    {  -- el menu se abre para el jugador correcto (y le da el foco del mando)
        id = "menu_del_jugador", count = "*",
        find = [=[ISContextMenu.get(0,]=],
        repl = [=[ISContextMenu.get(LXTH.playerNum(),]=],
    },
    {  -- percepcion e interaccion: el jugador local vivo mas cercano
        id = "jugador_cercano", count = "*",
        find = [=[getPlayer()]=],
        repl = [=[LXTH.near()]=],
    },
})
