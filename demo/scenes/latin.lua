-- One Latin line, its OpenType features switched on one a beat (each on
-- its own words): the ffi ligature, a fraction, a slashed zero, small caps.

local beat = require("beat")
local ui = require("ui")
local G = require("glyphs")
local T = require("timeline")

local STATES = G.data.latin
local KEYS = T.LATIN_KEYS
local TAGS = { { "liga", "f f i → ffi" }, { "frac", "2/3 → a fraction" }, { "zero", "0 → slashed zero" },
  { "smcp", "Small Caps → small caps" } }

local function render(f, lb)
  ui.label(lb, 4, "Latin · OpenType features")
  local k, changed = G.typed(STATES, KEYS, lb, 960, 520, { ink = ui.TEXT, accent = ui.C, size = 92,
    caret = false })
  -- the four tags, lit as each switches on
  local W = 150
  for i, t in ipairs(TAGS) do
    local x = 960 - 2 * (W + 20) + (i - 1) * (W + 20) + 10
    local on = k >= i
    local pop = on and beat.snap(lb - KEYS[i]) or 1
    group({ transform = { scale = 0.8 + 0.2 * pop, origin = { x + W / 2, 680 } } }, function()
      rect { x = x, y = 652, w = W, h = 56, rx = 28, fill = on and ui.mix(ui.C, ui.LINE, beat.prog(lb - KEYS[i], 0.5, 3)) or ui.PANEL }
      text { t[1], x = x + W / 2, y = 680, align = "center", baseline = "middle", font = ui.MONO, size = 26,
        fill = on and ui.TEXT or ui.DIM }
    end)
  end
  text { "features = { " .. (k >= 1 and '"' .. TAGS[k][1] .. '" … ' or "") .. "}", x = 960, y = 790, align = "center",
    font = ui.MONO, size = 22, fill = ui.DIM }
  if k >= 1 then ui.caption(lb, KEYS[k], TAGS[k][2], "the same text, laid out again with the feature on") end
end

return { name = "Latin", start = T.LATIN, stop = T.WEIGHT, render = render }
