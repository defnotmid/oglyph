-- Three Devanagari words typed key by key, a bar each: a vowel sign drawn
-- before the consonant it follows, a reph, a conjunct. Glyphs slide from
-- one layout to the next.

local beat = require("beat")
local ui = require("ui")
local G = require("glyphs")
local T = require("timeline")
local keycaps = require("scenes.keycaps")

local WORDS = G.data.devanagari
local FIRST = { 1, 6, 10 } -- each word's first keystroke
local COUNT = { 5, 4, 5 }
local CAPTION = {
  { "vowel signs reorder", "ि is typed after ह and drawn before it" },
  { "reph", "र + ् rides above the consonant after it" },
  { "conjuncts", "क + ् + ष fuse into one glyph" },
}
-- धर्म: when म is typed, र + ् become the reph over it. म is the new
-- glyph; the reph starts from the halant's place (its ink lies left of its
-- origin, so it starts over र and lifts onto म)
local OVER = { [2] = { [4] = { [2] = false, [3] = 3 } } }

local function render(f, lb)
  ui.label(lb, 3, "Devanagari · reordering, reph, conjuncts")
  local w = math.max(1, math.min(math.floor(lb / 4) + 1, 3))
  local start = (w - 1) * 4
  local keys = {}
  for i = 1, COUNT[w] do keys[i] = T.DEVA_KEYS[FIRST[w] + i - 1] - start end
  local lw = lb - start
  local enter = beat.snap(lw)
  group({ transform = translate((1 - enter) * 120, 0), opacity = beat.prog(lw, 0, 0.15) }, function()
    local k, changed, st = G.typed(WORDS[w], keys, lw, 960, 540, { ink = ui.TEXT, accent = ui.B, size = 190,
      over = OVER[w] })
    G.ids(st, changed, 960, 660, ui.B)
    keycaps(WORDS[w][#WORDS[w]].text, keys, k, lw, 730, ui.DEVA, false, ui.B)
    if k == COUNT[w] then ui.caption(lw, keys[k] + 0.25, CAPTION[w][1], CAPTION[w][2]) end
  end)
end

return { name = "Devanagari", start = T.DEVA, stop = T.LATIN, render = render }
