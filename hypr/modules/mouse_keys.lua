-- Control del raton con el teclado (mouse keys).
--
-- Hyprland no tiene modo de raton por teclado, asi que el movimiento lo hace
-- ydotool: crea un dispositivo virtual via uinput, asi que funciona en
-- cualquier compositor. Requiere el demonio ydotoold, que scripts/session-start
-- levanta al arrancar la sesion.
--
--   SUPER + ALT + h/j/k/l        mueve el cursor (20 px, se repite al mantener)
--   SUPER + ALT + SHIFT + h/j/k/l  mueve rapido (100 px)
--   SUPER + ALT + u              click izquierdo
--   SUPER + ALT + i              click derecho

local mod = "SUPER + ALT"

local function move(dx, dy)
	return hl.dsp.exec_cmd(("ydotool mousemove -- %d %d"):format(dx, dy))
end

local slow, fast = 20, 100

hl.bind(mod .. " + h", move(-slow, 0),  { repeating = true })
hl.bind(mod .. " + l", move( slow, 0),  { repeating = true })
hl.bind(mod .. " + k", move(0, -slow),  { repeating = true })
hl.bind(mod .. " + j", move(0,  slow),  { repeating = true })

hl.bind(mod .. " + SHIFT + h", move(-fast, 0), { repeating = true })
hl.bind(mod .. " + SHIFT + l", move( fast, 0), { repeating = true })
hl.bind(mod .. " + SHIFT + k", move(0, -fast), { repeating = true })
hl.bind(mod .. " + SHIFT + j", move(0,  fast), { repeating = true })

-- Codigos de ydotool click: 0xC0 = izquierdo (press+release), 0xC1 = derecho.
hl.bind(mod .. " + u", hl.dsp.exec_cmd("ydotool click 0xC0"))
hl.bind(mod .. " + i", hl.dsp.exec_cmd("ydotool click 0xC1"))
