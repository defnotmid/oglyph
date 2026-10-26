-- "Variable fonts" in Adwaita Sans from wght 100 to 900 and back: each
-- frame draws the nearest of 97 real instances, made by oglyph from the
-- variable font (its gvar deltas; nothing interpolated between outlines) and
-- drawn live through ovg (`variations`; the font: fetch.sh).

local beat = require("beat")
local ui = require("ui")
local T = require("timeline")

local STEPS = 97 -- wght 100, 108.3, ... 900
local FONT, SIZE = "Adwaita Sans", 210

local function render(f, lb)
  ui.label(lb, 5, "Variable fonts · real instances")
  local s = (1 - math.cos(2 * math.pi * beat.clamp01(lb / 8))) / 2
  local wght = 100 + 800 * math.floor(s * (STEPS - 1) + 0.5) / (STEPS - 1)
  local w = text_width { "Variable fonts", font = FONT, size = SIZE, variations = { wght = wght } }
  -- one gradient across the line
  text { "Variable fonts", x = 960, y = 560, align = "center", font = FONT, size = SIZE, variations = { wght = wght },
    fill = linear_gradient { x1 = 960 - w / 2, y1 = 0, x2 = 960 + w / 2, y2 = 0,
      stops = { { 0, ui.A }, { 0.5, ui.B }, { 1, ui.C } } } }
  -- the axis: a track, the instance's knob and its value
  rect { x = 660, y = 700, w = 600, h = 4, rx = 2, fill = ui.LINE }
  local kx = 660 + 600 * (wght - 100) / 800
  if kx > 661 then rect { x = 660, y = 700, w = kx - 660, h = 4, rx = 2, fill = ui.A } end
  circle { cx = kx, cy = 702, r = 12, fill = ui.TEXT }
  text { "100", x = 640, y = 710, align = "right", font = ui.MONO, size = 20, fill = ui.DIM }
  text { "900", x = 1280, y = 710, font = ui.MONO, size = 20, fill = ui.DIM }
  text { string.format("wght %d", math.floor(wght + 0.5)), x = 960, y = 780, align = "center", font = ui.MONO,
    size = 34, fill = ui.TEXT }
  ui.caption(lb, 1, "real instances, outlined and shaped by oglyph", "Adwaita Sans · wght 100–900 · 97 instances, none interpolated")
end

return { name = "Weight", start = T.WEIGHT, stop = T.PROOF, render = render }
