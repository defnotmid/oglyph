-- The end card.

local beat = require("beat")
local ui = require("ui")
local T = require("timeline")

local function render(f, lb)
  local p = beat.soft(lb)
  local out = beat.prog(lb, 6.5, 8)
  group({ opacity = 1 - out }, function()
    local W = text_width { "oglyph", font = ui.SANS, weight = 700, size = 200 }
    group({ transform = { scale = 0.8 + 0.2 * p, origin = { 960, 470 } } }, function()
      text { "oglyph", x = 960, y = 520, align = "center", font = ui.SANS, weight = 700, size = 200,
        fill = linear_gradient { x1 = 960 - W / 2, y1 = 0, x2 = 960 + W / 2, y2 = 0,
          stops = { { 0, ui.A }, { 0.5, ui.B }, { 1, ui.C } } } }
    end)
    local q = beat.snap(lb - 1)
    group({ opacity = beat.prog(lb, 1, 1.2), transform = translate(0, (1 - q) * 30) }, function()
      text { "oglyph · MIT · github.com/defnotmid/oglyph", x = 960, y = 640, align = "center", font = ui.MONO,
        size = 34, fill = ui.TEXT }
    end)
    group({ opacity = beat.prog(lb, 2, 2.3) }, function()
      text { "drawn with ovg", x = 960, y = 700, align = "center", font = ui.MONO, size = 22, fill = ui.DIM }
    end)
  end)
end

return { name = "Outro", start = T.OUTRO, stop = T.TOTAL, render = render }
