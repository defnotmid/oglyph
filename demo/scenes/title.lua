-- Three scripts float in, one a beat (oglyph's proof lines, drawn from
-- their glyphs), then the wordmark slams in on the slam.

local beat = require("beat")
local ui = require("ui")
local G = require("glyphs")
local T = require("timeline")
local prog, snap, soft, pulse, expo_out = beat.prog, beat.snap, beat.soft, beat.pulse, beat.expo_out

local SAMPLES = { { 1, 520, 360 }, { 2, 1380, 420 }, { 3, 900, 760 } } -- proof line, x, y

local function render(f, lb)
  local slam = T.TITLE_SLAM
  local a = lb * 0.6
  rect { x = 0, y = 0, w = 1920, h = 1080, fill = radial_gradient { cx = 960, cy = 540, r = 900,
    fx = 960 + math.cos(a) * 380, fy = 540 + math.sin(a) * 220,
    stops = { { 0, "#1b1f5c" }, { 0.5, "#0b0d2a" }, { 1, ui.BG } } } }

  if lb < slam + 0.5 then
    local out = expo_out(prog(lb, slam - 0.25, slam + 0.5))
    for i, s in ipairs(SAMPLES) do
      local p = expo_out(prog(lb, i - 1, i + 0.4))
      group({ opacity = p * (1 - out) * 0.9, transform = { translate = { 0, (1 - p) * 40 }, scale = 1 - out * 0.4,
        origin = { s[2], s[3] } } }, function()
        G.draw(G.data.proof[s[1]], s[2], s[3], ({ ui.A, ui.B, ui.C })[i])
      end)
    end
  end

  if lb >= slam then
    local s = 1 + 0.35 * (1 - soft(lb - slam)) + 0.02 * pulse(lb, 8)
    local W = text_width { "oglyph", font = ui.SANS, weight = 700, size = 300 }
    group({ transform = { scale = s, origin = { 960, 470 } },
      filter = {
        { "drop_shadow", dx = 0, dy = 18, std = 14, color = "#000000", opacity = 0.7, result = "d" },
        { "blur", std = 26, input = "SourceGraphic", result = "g" },
        { "color_matrix", type = "hueRotate", values = lb * 40, input = "g", result = "h" },
        { "merge", "h", "d" },
      } }, function()
      text { "oglyph", x = 960, y = 560, align = "center", font = ui.SANS, weight = 700, size = 300,
        fill = linear_gradient { x1 = 960 - W / 2, y1 = 0, x2 = 960 + W / 2, y2 = 0, spread = "reflect",
          transform = translate(math.sin(lb * 0.8) * 300, 0), stops = { { 0, ui.A }, { 0.5, ui.B }, { 1, ui.C } } } }
    end)
    local p = snap(lb - slam - 1)
    group({ opacity = prog(lb, slam + 1, slam + 1.2), transform = translate(0, (1 - p) * 30) }, function()
      text { "OpenType text shaping in pure Odin", x = 960, y = 700, align = "center", font = ui.SANS, size = 50,
        fill = ui.TEXT }
    end)
    if lb >= slam + 2 then
      local label = "HarfBuzz's rules · Arabic · Indic · OpenType features · variable fonts"
      local w = text_width { label, font = ui.MONO, size = 22 } + 31
      ui.chip(960 - w / 2, 770, label, ui.LINE, ui.A, 22, snap(lb - slam - 2))
    end
  end
end

return { name = "Title", start = T.TITLE, stop = T.ARABIC, render = render }
