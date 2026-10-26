-- السلام عليكم typed a letter a beat and laid out again on every key: the
-- letter before each new one takes its joining form, lam + alef their
-- joined pair; reshaped and new glyphs flash cyan, their ids below.

local beat = require("beat")
local ui = require("ui")
local G = require("glyphs")
local T = require("timeline")
local keycaps = require("scenes.keycaps")

local STATES = G.data.arabic
local KEYS = T.ARABIC_KEYS

local function render(f, lb)
  ui.label(lb, 2, "Arabic · letters join as you type")
  local k, changed, st = G.typed(STATES, KEYS, lb, 960, 520, { rtl = true, ink = ui.TEXT, accent = ui.A,
    size = 150 })
  G.ids(st, changed, 960, 660, ui.A)
  keycaps(STATES[#STATES].text, KEYS, k, lb, 730, ui.ARABIC, true, ui.A)
  if k >= 2 and k < 5 then
    ui.caption(lb, KEYS[2], "each key reshapes the letter before it", "isolated → final, initial → medial")
  elseif k >= 5 and k < 12 then
    ui.caption(lb, KEYS[5], "lam + alef take their joined forms", "the shaper picks them from the font's rules (GSUB)")
  elseif k == 12 then
    ui.caption(lb, KEYS[12], "a new layout on every keystroke", "glyph ids from oglyph: cyan = reshaped or new")
  end
end

return { name = "Arabic", start = T.ARABIC, stop = T.DEVA, render = render }
