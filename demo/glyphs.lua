-- oglyph's shaping, baked (bake/main.odin -> media/glyphs.json): each
-- typing state, feature set, weight instance and proof line as glyph ids,
-- clusters and positions, with every glyph's outline. Drawn here glyph by
-- glyph, so a change of state can move, reshape and flash single glyphs.

local beat = require("beat")
local ui = require("ui")

local G = {}

local function read_json(name)
  local fh = assert(io.open(SCRIPT_DIR .. "/media/" .. name))
  local v = json_decode(fh:read("a"))
  fh:close()
  return v
end

G.data = read_json("glyphs.json")
G.hb = read_json("hb.json")

-- Path handles by face ("naskh@150": a face at a size) and glyph id, made
-- once at load.
local paths = {}
for key, face in pairs(G.data.paths) do
  local t = {}
  for id, d in pairs(face.glyphs) do
    if d ~= "" then t[tonumber(id)] = path_data(d) end
  end
  paths[key] = t
end
G.hb_paths = {}
for file, glyphs in pairs(G.hb.paths) do
  local t = {}
  for id, d in pairs(glyphs) do
    if d ~= "" then t[tonumber(id)] = path_data(d) end
  end
  G.hb_paths[file] = t
end

-- One glyph of face `face` with its origin at (x, y); `fill` may be a
-- function of x giving the paint in the glyph's own space.
function G.glyph(face, id, x, y, fill, opacity, scale, oy)
  local h = paths[face][id]
  if not h or (opacity or 1) <= 0 then return end
  if type(fill) == "function" then fill = fill(x, y) end
  group({ opacity = opacity or 1, transform = { translate = { x, y }, scale = scale or 1, origin = { 0, oy or 0 } } },
    function() path { d = h, fill = fill } end)
end

-- The x that centres state `st` on `cx`.
function G.offset(st, cx) return cx - (st.min[1] + st.max[1]) / 2 end

-- Where each glyph of `new` comes from in `old`: the same glyph of the same
-- cluster, else another glyph of its cluster (reshaped), else nothing (it
-- was typed). `over` names some outright: new index -> old index, or false
-- for typed. Returns from (new -> old) and used (old indices taken).
function G.match(old, new, over)
  local from, used = {}, {}
  for i, j in pairs(over or {}) do
    from[i] = j
    if j then used[j] = true end
  end
  for pass = 1, 2 do
    for i, g in ipairs(new.glyphs) do
      if from[i] == nil then
        for j, o in ipairs(old.glyphs) do
          if not used[j] and o[2] == g[2] and (pass == 2 or o[1] == g[1]) then
            from[i], used[j] = j, true
            break
          end
        end
      end
    end
  end
  return from, used
end

-- Line `states` typed one keystroke at a time: states[k + 1] is the line
-- after keystroke k, struck at beat keys[k] (lb is this scene's beat).
-- Kept glyphs slide to their new places, reshaped ones flash `accent`,
-- typed ones slide in from the caret, dropped ones fade. Returns the
-- keystrokes so far and, per glyph of the state shown, whether it changed.
function G.typed(states, keys, lb, cx, y, o)
  local k = 0
  for i, t in ipairs(keys) do if lb >= t then k = i end end
  local new, old = states[k + 1], states[k]
  local t = k > 0 and lb - keys[k] or 99
  local p = beat.snap(t)
  local no = G.offset(new, cx)
  local oo = old and G.offset(old, cx) or no
  local from, used = {}, {}
  if old then from, used = G.match(old, new, o.over and o.over[k]) end
  -- the caret: where the old line ended, in reading order
  local caret = old and (o.rtl and oo + old.min[1] or oo + old.max[1]) or cx
  local growth = old and (new.max[1] - new.min[1]) - (old.max[1] - old.min[1]) or 0
  if old then
    for j, g in ipairs(old.glyphs) do
      if not used[j] then G.glyph(old.face, g[1], oo + g[3], y + g[4], o.ink, 1 - beat.prog(t, 0, 0.3)) end
    end
  end
  local changed = {}
  for i, g in ipairs(new.glyphs) do
    local tx, ty = no + g[3], y + g[4]
    local x, yy, fill, scale, op = tx, ty, o.ink, 1, 1
    local j = from[i]
    if old and j then
      local og = old.glyphs[j]
      x, yy = beat.lerp(oo + og[3], tx, p), beat.lerp(y + og[4], ty, p)
      if og[1] ~= g[1] then
        changed[i] = true
        fill = ui.mix(o.accent, o.ink, beat.prog(t, 0.3, 1.6))
      end
    elseif old then
      changed[i] = true
      local sx = o.rtl and caret - growth or caret
      x = beat.lerp(sx + (g[3] - new.min[1]) * (o.rtl and 1 or 0), tx, p)
      scale, op = 0.6 + 0.4 * p, beat.prog(t, 0, 0.12)
      fill = ui.mix(o.accent, o.ink, beat.prog(t, 0.3, 1.6))
    end
    G.glyph(new.face, g[1], x, yy, fill, op, scale, -o.size * 0.35)
  end
  -- the caret blinks at the line's end
  local cx2 = o.rtl and no + new.min[1] or no + new.max[1]
  if o.caret ~= false then
    rect { x = cx2 + (o.rtl and -10 or 6), y = y - o.size * 0.8, w = 4, h = o.size * 1.0, fill = o.accent,
      opacity = 0.35 + 0.65 * (math.floor(lb * 2) % 2 == 0 and 1 or 0.2) }
  end
  return k, changed, new
end

-- The glyph ids of a state in visual order, centred under the line: the
-- changed ones in `accent`.
function G.ids(st, changed, cx, y, accent, size)
  size = size or 22
  local parts, widths, total = {}, {}, 0
  for i, g in ipairs(st.glyphs) do
    parts[i] = tostring(g[1])
    widths[i] = text_width { parts[i], font = ui.MONO, size = size }
    total = total + widths[i] + (i > 1 and size * 0.9 or 0)
  end
  local x = cx - total / 2
  for i, s in ipairs(parts) do
    text { s, x = x, y = y, font = ui.MONO, size = size, fill = changed[i] and accent or ui.DIM }
    x = x + widths[i] + size * 0.9
  end
end

-- A state drawn in place, unanimated.
function G.draw(st, cx, y, fill, opacity)
  local ox = G.offset(st, cx)
  for _, g in ipairs(st.glyphs) do G.glyph(st.face, g[1], ox + g[3], y + g[4], fill, opacity) end
end

return G
