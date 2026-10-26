-- The soundtrack: an odawg song, Arabic electronica at 124 BPM in D Hijaz,
-- 16 bars, its sections named after the scenes (the title has two: the
-- intro bar and the slam). A blip plays every keystroke of the Arabic and
-- Devanagari lines and every feature switched on in the Latin one; the
-- picture reads those hits back (timeline.lua), so each letter lands on its
-- note.
--
-- Why: oglyph's first scene shapes Arabic, so Arabic electronica after Acid
-- Arab: a real darbuka (VCSL's, fetched and pinned: the deep doum, the
-- sharp tek, the ka between) on the maqsum rhythm over a 909 kick, an acid
-- bass of our own (a saw through a resonant ladder that a short envelope
-- snaps open), a reedy lead of our own (a pulse through a nasal band-pass,
-- a slow vibrato) playing a Hijaz line (D, E-flat, F-sharp: the augmented
-- second), and a drone on D under the Devanagari scene, a tanpura's place.
-- D Hijaz: D major's chord over a phrygian scale, E-flat above it, C minor
-- and G minor below. No risers.

local LIB = "" -- rows copied into media/ from onimite's library: machines/909.json, instruments/sfx.json
local KIT = { LIB .. "machines/909.json", tone = 0.5 }

-- A degrees line in 16ths over `bars` bars with a note at each listed
-- sixteenth (0-based), climbing through `notes`.
local function at16(bars, list, notes)
  local cells, on = {}, {}
  for _, i in ipairs(list) do on[i] = true end
  local n = 0
  for i = 0, bars * 16 - 1 do
    if i > 0 and i % 16 == 0 then cells[#cells + 1] = "|" end
    if on[i] then n = n + 1; cells[#cells + 1] = tostring(notes[(n - 1) % #notes + 1]) else cells[#cells + 1] = "." end
  end
  return table.concat(cells, " ")
end

local ARABIC = {}  -- twelve keystrokes, a dotted eighth apart
for k = 0, 11 do ARABIC[#ARABIC + 1] = 2 + k * 3 end
local DEVA = { 0, 2, 4, 6, 8, 16, 18, 20, 22, 32, 34, 36, 38, 40 }  -- 5 + 4 + 5, a word a bar
local LATIN = { 4, 10, 16, 22 }  -- liga, frac, zero, smcp

local VCSL = { url = "https://raw.githubusercontent.com/sgossner/VCSL/c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e/",
  page = "https://github.com/sgossner/VCSL", licence = "CC0-1.0",
  credit = "Versilian Community Sample Library (VCSL) by Versilian Studios, CC0 1.0", pins = "pins/vcsl.pins" }
local DARBUKA = "vcsl/Membranophones/Struck Membranophones/Darbuka/"
-- a stroke: its two velocity layers, two round robins each
local function stroke(n)
  local out = {}
  for _, l in ipairs { { "vl1", 0, 80 }, { "vl2", 81, 127 } } do
    for rr = 1, 2 do
      out[#out + 1] = { file = DARBUKA .. ("Darbuka_%d_hit_%s_rr%d.wav"):format(n, l[1], rr), lo_velocity = l[2], hi_velocity = l[3] }
    end
  end
  return out
end

-- maqsum, two bars: doum tek . tek doum . tek . , the second with a fill
local MAQSUM = {
  doum = { "x.....x.x.......", "x.....x.x...x..." },
  tek = { "...x.x......x...", "...x.x.....oxox." },
  ka = { "..o.....o.o...o.", "..o.....o.o....." },
}

return song { "score", key = "D phrygian", bpm = 124, seed = 1044, swing = 0.08, swing_subdivision = "16n",
  sources = { vcsl = VCSL },
  sets = { darbuka = { pads = { doum = stroke(1), tek = stroke(3), ka = stroke(4) },
    credit = "Versilian Community Sample Library (VCSL) by Versilian Studios, CC0 1.0" } },
  instruments = { LIB .. "instruments/sfx.json", {
    -- the acid bass: a saw through a resonant ladder a short envelope snaps
    -- open (harder notes further), one voice, sliding into notes marked ~
    acid = {
      mono = true, portamento = 0.05,
      nodes = {
        saw = { "Osc", wave = "sawtooth" },
        snap = { "Decay", time = 0.14 },
        lp = { "Ladder", "saw", q = 3.4, frequency = { { 240, by = "snap", octaves = 2.6 }, { by = "velocity", octaves = 1 } } },
        drive = { "Drive", "lp", amount = 1.6, oversample = 1 },
        env = { "Env", attack = 0.002, decay = 0.2, sustain = 0.6, release = 0.05 },
        out = { "Mix", "drive", amp = "env", gain_db = -12 },
      },
      out = "out",
      options = { cutoff = "lp/frequency" },
    },
    -- the reed: a narrow pulse through a nasal band-pass and a low-pass, a
    -- slow vibrato fading in, a little breath; one voice, gliding
    reed = {
      mono = true, portamento = 0.06,
      nodes = {
        vib = { "Lfo", rate = 5.2, delay = 0.25, fade = 0.4 },
        pulse = { "Osc", wave = "pulse", width = 0.18, frequency = { by = "vib", octaves = 0.012 } },
        breath = { "Noise", gain_db = -26 },
        both = { "Mix", "pulse", "breath" },
        nose = { "Filter", "both", type = "bandpass", frequency = 1400, q = 1.6 },
        lp = { "Filter", "nose", type = "lowpass", frequency = 4200 },
        env = { "Env", attack = 0.03, decay = 0.2, sustain = 0.85, release = 0.15 },
        out = { "Mix", "lp", amp = "env", gain_db = -2 },
      },
      out = "out",
    },
    -- the drone: two saws a fifth apart, slowly beating, under a low-pass
    -- that breathes
    drone = {
      nodes = {
        root = { "Osc", wave = "fatsawtooth", count = 2, spread = 6 },
        fifth = { "Osc", wave = "sawtooth", ratio = 1.5, gain_db = -6 },
        both = { "Mix", "root", "fifth" },
        breathe = { "Lfo", rate = 0.2 },
        lp = { "Filter", "both", type = "lowpass", q = 1.2, frequency = { 700, by = "breathe", octaves = 0.6 } },
        env = { "Env", attack = 1.5, decay = 0, sustain = 1, release = 2 },
        out = { "Mix", "lp", amp = "env", gain_db = -20 },
      },
      out = "out",
    },
  } },
  sections = {
    { "title", duration = "1m", chords = "D" },
    { "slam", duration = "1m", chords = "Eb" },
    { "arabic", duration = "3m", chords = "D Cm D" },
    { "deva", duration = "3m", chords = "Gm Eb D" },
    { "latin", duration = "2m", chords = "D Cm" },
    { "weight", duration = "2m", chords = "Eb D" },
    { "proof", duration = "2m", chords = "Gm D" },
    { "outro", duration = "1m", chords = "Eb" },
    { "tail", duration = "1m", chords = "D" },
  },
  returns = { room = { { "Reverb", decay = 1.1, pre_delay = 0.008 }, { "Filter", type = "highpass", frequency = 250 } },
              echo = { { "PingPongDelay", delay_time = "8n.", feedback = 0.3, wet = 1 }, { "Filter", type = "lowpass", frequency = 3500 } } },
  parts = {
    -- the 909 under the hands: the kick from the slam, out for the
    -- Devanagari scene, a clap on two and four from the Latin one
    drums = { role = "drums", instrument = KIT, gain_db = 0, sends = { room = -20 }, play = {
      { "slam..arabic", steps = { kick = "x...x...x...x...", hat = "..x...x...x...x." }, humanize = 0.002 },
      { "latin..outro", humanize = 0.002, steps = { kick = "x...x...x...x...", hat = "..x...x...x...x.", clap = "....x.......x..." } },
      { "tail", steps = { kick = "X..............." } },
    } },
    -- the darbuka on maqsum, alone in the title, through to the outro
    hands = { role = "counter", instrument = { "Sampler", set = "darbuka" }, gain_db = 0, pan = -0.15, sends = { room = -12 }, play = {
      { "title", steps = { doum = "x.......x.......", tek = "....x.......x.x." }, velocity = 0.8, humanize = 0.006 },
      { "slam..outro", steps = MAQSUM, velocity = 0.9, humanize = 0.006 },
    } },
    -- the acid bass on the root, the half step above it, the octave
    bass = { role = "bass", instrument = "acid", gain_db = 11, sidechain = { "drums/kick", depth = 0.3 }, play = {
      { "arabic", degrees = "1 . . 1 . . 8 . 1 . 2~ 1 . . 8 .", subdivision = "16n", octave = 2, velocity = 0.85, humanize = 0.002 },
      { "latin..outro", degrees = "1 . . 1 . . 8 . 1 . 2~ 1 . . 8 .", subdivision = "16n", octave = 2, velocity = 0.9, humanize = 0.002 },
      { "tail", degrees = "1", subdivision = "1m", octave = 2, velocity = 0.7 },
    } },
    -- the reed: a Hijaz line over the Arabic scene's answers, then the
    -- weight and the proof
    lead = { role = "melody", instrument = "reed", gain_db = -3, sends = { echo = -16, room = -12 }, play = {
      { "arabic@1m", subdivision = "8n", velocity = 0.8, humanize = 0.006,
        notes = "D5 - Eb5 F#5 - G5 F#5 Eb5 | D5 - - - . . . ." },
      { "weight", subdivision = "8n", velocity = 0.85, humanize = 0.006,
        notes = "G5 - F#5 Eb5 - D5 Eb5 F#5 | A5 - G5 F#5 Eb5 - D5 -" },
      { "proof", subdivision = "8n", velocity = 0.85, humanize = 0.006,
        notes = "Bb5 - A5 G5 - F#5 G5 A5 | D5 - - - - - . ." },
    } },
    -- the drone on D under the Devanagari scene, a tanpura's place
    drone = { role = "pad", instrument = "drone", gain_db = 0, sends = { room = -10 }, play = {
      { "deva", events = { { time = 0, note = "D2", duration = "3m" }, { time = 0, note = "D3", duration = "3m", velocity = 0.6 } } },
    } },
    crash = { role = "fx", instrument = KIT, gain_db = 7, play = {
      { "arabic..latin", steps = { crash = { "X...............", "", "" } }, velocity = 0.5 },
      { "weight..proof", steps = { crash = { "X...............", "" } }, velocity = 0.5 },
      { "tail", steps = { crash = "X..............." }, velocity = 0.5 },
    } },
    -- the picture's: a blip a keystroke, a blip a feature switched on
    typing = { role = "fx", instrument = "blip", gain_db = -1, octave = 5,
      play = { { "arabic", degrees = at16(3, ARABIC, { 1, 3, 5, 3, 5, 8 }), subdivision = "16n" },
               { "deva", degrees = at16(3, DEVA, { 1, 2, 3, 5, 8 }), subdivision = "16n" } } },
    toggles = { role = "fx", instrument = "blip", gain_db = -2, octave = 6,
      play = { { "latin", degrees = at16(2, LATIN, { 1, 3, 5, 8 }), subdivision = "16n" },
               { "proof", degrees = at16(2, { 4, 16 }, { 1, 5 }), subdivision = "16n" } } },
  },
  automation = {
    -- the darbuka down where it plays alone with the drone (inspect's
    -- role_balance: 1.8 LU under the mix there)
    ["parts/hands/gain_db"] = { { "title", 0 }, { "deva", -3, "step" }, { "latin", 0, "step" } },
  },
}
