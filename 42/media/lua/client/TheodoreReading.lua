-- LX_TheodoreSplit: reemplaza este archivo de Theodore por un cargador que lee el
-- ORIGINAL instalado (media/lua/client/TheodoreReading.lua), le aplica los cambios de pantalla
-- dividida en memoria y lo ejecuta. Si Theodore se actualiza y un fragmento deja de
-- coincidir, ese parche se omite y el codigo original corre igual.
-- Generado por gen_theodore.py - no editar a mano.
require "LXTH_Core"

LXTH.LoadPatched("media/lua/client/TheodoreReading.lua", {
    {  -- si te dice Mom o Dad: siempre el mismo jugador
        id = "identidad_padre", count = "*",
        find = [=[getPlayer():isFemale()]=],
        repl = [=[LXTH.owner():isFemale()]=],
    },
    {  -- percepcion e interaccion: el jugador local vivo mas cercano
        id = "jugador_cercano", count = "*",
        find = [=[getPlayer()]=],
        repl = [=[LXTH.near()]=],
    },
})
