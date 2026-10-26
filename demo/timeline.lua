-- Where things happen, in beats from the start of the video (4 a bar),
-- read from the song (track.lua): its sections are the scenes, its typing
-- and toggle notes the keystrokes and switches the picture shows.

local score = require("track")

local T = {}

local function at(pos) return score.beat(score.time(pos)) end
-- The song's hits of `part` in section `section`, in beats into it.
local function hits(part, section)
  local out, start = {}, at(section)
  for i, t in ipairs(score.hits { part = part, range = section }) do out[i] = score.beat(t) - start end
  return out
end

T.TITLE, T.ARABIC, T.DEVA, T.LATIN, T.WEIGHT, T.PROOF, T.OUTRO = at("title"), at("arabic"), at("deva"), at("latin"),
  at("weight"), at("proof"), at("outro")
T.END = at("tail")
T.TOTAL = score.beat(score.duration)
T.TITLE_SLAM = at("slam") - T.TITLE

T.ARABIC_KEYS = hits("typing", "arabic")   -- 12 keystrokes
T.DEVA_KEYS = hits("typing", "deva")       -- 5 + 4 + 5
T.LATIN_KEYS = hits("toggles", "latin")    -- liga, frac, zero, smcp
T.PROOF_POPS = hits("toggles", "proof")    -- HarfBuzz's layer, the count
assert(#T.ARABIC_KEYS == 12 and #T.DEVA_KEYS == 14 and #T.LATIN_KEYS == 4 and #T.PROOF_POPS == 2,
  string.format("hits: %d %d %d %d", #T.ARABIC_KEYS, #T.DEVA_KEYS, #T.LATIN_KEYS, #T.PROOF_POPS))

return T
