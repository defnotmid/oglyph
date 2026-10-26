-- Palette, type and the small parts the scenes share (the ovg demo's).

local beat = require("beat")

local M = {}

M.BG, M.PANEL, M.LINE = "#060714", "#0f1226", "#262b4d"
M.TEXT, M.DIM = "#f1f2ff", "#8188b3"
M.A, M.B, M.C = "#38e1ff", "#ff4fd8", "#ffd84a" -- cyan, magenta, yellow

M.DISPLAY, M.SANS, M.MONO = "Bebas Neue", "DM Sans", "JetBrains Mono"
M.ARABIC, M.DEVA = "Noto Naskh Arabic", "Noto Sans Devanagari"

-- "#rrggbb" between two colours.
local function rgb(c) return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16) end
function M.mix(a, b, t)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  t = beat.clamp01(t)
  return string.format("#%02x%02x%02x", math.floor(r1 + (r2 - r1) * t + 0.5), math.floor(g1 + (g2 - g1) * t + 0.5),
    math.floor(b1 + (b2 - b1) * t + 0.5))
end

-- A filled label, popping from its left edge; returns its width.
function M.chip(x, y, label, fill, ink, size, pop, font)
  size = size or 22
  font = font or M.MONO
  local w = text_width { label, font = font, size = size } + size * 1.4
  local h = size * 1.9
  group({ transform = { scale = pop or 1, origin = { x, y + h / 2 } } }, function()
    rect { x = x, y = y, w = w, h = h, rx = h / 2, fill = fill }
    text { label, x = x + size * 0.7, y = y + h / 2, baseline = "middle", font = font, size = size, fill = ink or M.BG }
  end)
  return w
end

-- The section label top left: "02 · Arabic", popping on its first beat.
function M.label(lb, n, s)
  M.chip(120, 120, string.format("%02d · %s", n, s), M.LINE, M.TEXT, 24, beat.snap(lb))
end

-- A caption at the bottom, rising in at beat `at`: a line and a small one.
function M.caption(lb, at, s, small)
  if lb < at then return end
  local p = beat.snap(lb - at)
  group({ opacity = beat.prog(lb, at, at + 0.2), transform = translate(0, (1 - p) * 30) }, function()
    text { s, x = 960, y = 930, align = "center", font = M.SANS, size = 44, fill = M.TEXT }
    if small then text { small, x = 960, y = 980, align = "center", font = M.MONO, size = 20, fill = M.DIM } end
  end)
end

return M
