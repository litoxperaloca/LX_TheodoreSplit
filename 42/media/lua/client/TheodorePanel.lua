-- LX_TheodoreSplit: reemplaza este archivo de Theodore por un cargador que lee el
-- ORIGINAL instalado (media/lua/client/TheodorePanel.lua), le aplica los cambios de
-- pantalla dividida y mando en memoria, y lo ejecuta.
--
-- Este archivo NO lo genera gen_theodore.py: ademas de las sustituciones mecanicas
-- lleva parches propios de la interfaz, escritos a mano contra fragmentos exactos.
-- Si Theodore cambia alguno, ese parche se omite con aviso en console.txt y el resto
-- del panel sigue funcionando como el original.
require "LXTH_Core"

LXTH.LoadPatched("media/lua/client/TheodorePanel.lua", {
    {  -- el menu se abre para el jugador correcto (y le da el foco del mando)
        id = "menu_del_jugador", count = 2,
        find = [=[ISContextMenu.get(0,]=],
        repl = [=[ISContextMenu.get(LXTH.playerNum(),]=],
    },

    {  -- el boton flotante se guarda y restaura dentro de la mitad del jugador,
       -- no contra la ventana entera
        id = "boton_en_su_pantalla", count = 1,
        find = [=[  if saved and saved.x then
    b:setX(math.max(0, math.min(saved.x, sw - BUTTON_SIZE)))
    b:setY(math.max(0, math.min(saved.y, sh - BUTTON_SIZE)))
    return
  end]=],
        repl = [=[  if saved and saved.x then
    b:setX(LXTH.clampX(saved.x, BUTTON_SIZE))
    b:setY(LXTH.clampY(saved.y, BUTTON_SIZE))
    return
  end]=],
    },

    {  -- arrastrando el boton no se lo puede sacar de su propia pantalla
        id = "arrastre_en_su_pantalla", count = 1,
        find = [=[  if self.dragging then
    self:setX(self.startPos[1] + mx - self.downAt[1])
    self:setY(self.startPos[2] + my - self.downAt[2])
  end]=],
        repl = [=[  if self.dragging then
    self:setX(LXTH.clampX(self.startPos[1] + mx - self.downAt[1], self.width))
    self:setY(LXTH.clampY(self.startPos[2] + my - self.downAt[2], self.height))
  end]=],
    },

    {  -- el panel se abre dentro de la mitad del jugador, y queda navegable con
       -- mando (cruceta recorre, A activa, B cierra). Si ese jugador no tiene
       -- mando asignado, makeJoypadReady no toca nada.
        id = "panel_en_su_pantalla_y_mando", count = 1,
        find = [=[    local p = TheoPanel:new(bx, math.max(10, math.min(by, sh - 520)))
    p:initialise()
    p:addToUIManager()]=],
        repl = [=[    local p = TheoPanel:new(LXTH.clampX(bx, PANEL_W), LXTH.clampY(by, 520))
    p:initialise()
    LXTH.makeJoypadReady(p)
    p:addToUIManager()]=],
    },

    {  -- al cerrar el panel se suelta el foco del mando: un panel que se lo queda
       -- deja al jugador sin control
        id = "soltar_mando_al_cerrar", count = 1,
        find = [=[  self:removeFromUIManager()
  if panel == self then panel = nil end]=],
        repl = [=[  LXTH.releaseJoypad(self)
  self:removeFromUIManager()
  if panel == self then panel = nil end]=],
    },

    {  -- percepcion e interaccion: el jugador local vivo mas cercano
        id = "jugador_cercano", count = "*",
        find = [=[getPlayer()]=],
        repl = [=[LXTH.near()]=],
    },
})
