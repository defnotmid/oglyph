-- The proof: oglyph's glyphs filled, HarfBuzz 14.6's for the same text
-- (hb-shape's ids and positions, fontTools' outlines) dropped on as thin
-- outlines; they land exactly on them.

local beat = require("beat")
local ui = require("ui")
local G = require("glyphs")
local T = require("timeline")

local YS = { 380, 580, 770 }

local function render(f, lb)
  ui.label(lb, 6, "checked against HarfBuzz")
  local pops = T.PROOF_POPS
  for i, st in ipairs(G.data.proof) do
    local ox = G.offset(st, 960)
    for _, g in ipairs(st.glyphs) do G.glyph(st.face, g[1], ox + g[3], YS[i] + g[4], "#4a5290") end
    if lb >= pops[1] - 0.5 then
      local p = beat.snap(lb - pops[1] - (i - 1) * 0.25)
      local line = G.hb.lines[i]
      local hp = G.hb_paths[line.file]
      group({ opacity = beat.prog(lb, pops[1] - 0.5, pops[1]), transform = translate(0, (1 - p) * -90) }, function()
        for _, g in ipairs(line.glyphs) do
          local h = hp[g[1]]
          if h then
            group({ transform = translate(ox + g[2], YS[i] + g[3]) }, function()
              path { d = h, fill = "none", stroke = ui.A, stroke_width = 2.5, line_join = "round" }
            end)
          end
        end
      end)
    end
  end
  -- the legend, top right
  rect { x = 1290, y = 128, w = 26, h = 26, rx = 4, fill = "#3a4170" }
  text { "oglyph", x = 1328, y = 150, font = ui.MONO, size = 22, fill = ui.TEXT }
  rect { x = 1470, y = 128, w = 26, h = 26, rx = 4, fill = "none", stroke = ui.A, stroke_width = 2.5 }
  text { "HarfBuzz 14.6", x = 1508, y = 150, font = ui.MONO, size = 22, fill = ui.TEXT }
  ui.caption(lb, pops[2], "0 differences from HarfBuzz 14.6 in 52,561 test cases",
    "glyph ids, clusters, advances, offsets · 1,043 curated + 27,118 feature-set + 24,400 random")
end

return { name = "Proof", start = T.PROOF, stop = T.OUTRO, render = render }
