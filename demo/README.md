# oglyph demo

A 31 second showcase of oglyph, music included: 1920x1080, 60 fps, Arabic electronica at
124 BPM. It is an [onimite](https://github.com/defnotmid/onimite) script (Odin + Lua video
framework, whose text is shaped by oglyph through ovg), not part of oglyph's build.

With onimite's release binary (`onimite update` keeps it current), from oglyph's root:

```sh
sh demo/fetch.sh                                         # once: Adwaita Sans, SHA-256 checked
onimite render demo/video.lua -o demo/demo.mp4 --qp 22   # render
onimite preview demo/video.lua                           # play, hot reload on save
```

`fetch.sh` downloads Adwaita Sans (a variable font, 880 KB, OFL) from GNOME's repository at
a pinned tag; the first render fetches the darbuka's samples (VCSL, pinned in
`media/pins/vcsl.pins`). After that it renders offline.

| bars | scene | what |
| --- | --- | --- |
| 1-2 | Title | the wordmark, slammed in on the second bar |
| 3-5 | Arabic | an Arabic line typed a keystroke at a time, each state shaped by oglyph (joining forms change as letters arrive), a blip on each key |
| 6-8 | Devanagari | three Devanagari words typed in, conjuncts and reordered vowel signs forming as they're shaped |
| 9-10 | Features | a Latin line with `liga`, `frac`, `zero` and `smcp` switched on one at a time |
| 11-12 | Variable fonts | Adwaita Sans from weight 100 to 900 and back: 97 real instances, outlined and shaped by oglyph (its gvar deltas), none interpolated, drawn live (onimite's `text{ variations = { wght = ... } }`) |
| 13-14 | Proof | the proof lines shaped by oglyph with HarfBuzz's outlines laid over them: the same glyph ids within 0.001 font units |
| 15-16 | Outro | the wordmark |

## Files

- `video.lua`, `beat.lua`, `timeline.lua`, `ui.lua`, `scenes/`: the video, its clock and
  springs on the song's beat (`beat.FPS`), where everything happens (read from the song),
  the shared drawing, a file per scene.
- `glyphs.lua` reads `media/glyphs.json` (86 KB): oglyph's shaping (glyph ids, clusters,
  positions) of the typing, feature and proof lines and each glyph's outline, baked once by
  `bake/main.odin` through ovg's `text_layout` (`odin run demo/bake -collection:deps=.. --
  out.json`). `media/hb.json` is HarfBuzz's side of the proof, from `bake/hb_proof.py`
  (hb-shape and fontTools). Both read the system's Noto fonts, so they're baked data kept in
  the repository. The weight scene isn't baked: it draws the variable font live.
- `track.lua`: the soundtrack, an odawg `song{}`. Arabic electronica after Acid Arab, in D
  Hijaz: a real darbuka (VCSL's doum, tek and ka, two velocity layers and round robins) on
  maqsum over a 909 kick, an acid bass and a reedy lead of its own (a Hijaz line, with D,
  E-flat and F-sharp's augmented second), a drone under the Devanagari scene, a blip on each
  keystroke and feature that the picture reads back. Every part has a `role`.
- `media/`: the two Noto fonts the scenes set (OFL, `media/OFL.txt`), the baked data, the
  pins, the rows copied from onimite's skill library (`machines/909.json`,
  `instruments/sfx.json`) so the demo needs no onimite checkout, and `.gitignore` for what
  `fetch.sh` downloads.

Mix (`onimite audio analyze demo/video.lua`): about -14.5 LUFS integrated, -2.0 dBTP; the
Devanagari scene dips to the drone and the hands.

## Credits

- Darbuka samples: the Versilian Community Sample Library (VCSL) by Versilian Studios, CC0 1.0.
- Fonts: Noto Naskh Arabic and Noto Sans Devanagari (The Noto Project Authors, SIL OFL 1.1);
  Adwaita Sans (GNOME, from Inter; SIL OFL 1.1), fetched; Noto Sans, read from the system by
  the bake.
- Proof: HarfBuzz 14.6 and fontTools, run by `bake/hb_proof.py`.

Made with onimite; music by odawg.
