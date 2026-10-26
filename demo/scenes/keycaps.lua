-- The keys typed so far, as key caps: each codepoint alone (a lone mark on
-- the dotted circle, as shapers draw one), the newest popping in.

local beat = require("beat")
local ui = require("ui")

local function chars(s)
  local out = {}
  for _, c in utf8.codes(s) do out[#out + 1] = utf8.char(c) end
  return out
end

return function(str, keys, k, lb, y, font, rtl, accent)
  local cs = chars(str)
  local CAP, GAP = 76, 12
  local n = #cs
  local total = n * CAP + (n - 1) * GAP
  for i = 1, k do
    local slot = rtl and (n - i) or (i - 1)
    local x = 960 - total / 2 + slot * (CAP + GAP)
    local pop = beat.snap(lb - keys[i])
    local fresh = beat.prog(lb - keys[i], 0.2, 1.2)
    group({ transform = { scale = 0.6 + 0.4 * pop, origin = { x + CAP / 2, y + CAP / 2 } } }, function()
      rect { x = x, y = y, w = CAP, h = CAP, rx = 14, fill = ui.PANEL, stroke = ui.mix(accent, ui.LINE, fresh),
        stroke_width = 2 }
      if cs[i] == " " then
        text { "spc", x = x + CAP / 2, y = y + CAP / 2, align = "center", baseline = "middle", font = ui.MONO,
          size = 18, fill = ui.DIM }
      else
        text { cs[i], x = x + CAP / 2, y = y + CAP * 0.62, align = "center", font = font, size = 40, fill = ui.TEXT }
      end
    end)
  end
end
