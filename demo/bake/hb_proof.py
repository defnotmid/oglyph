# HarfBuzz's side of the proof scene: hb-shape (HarfBuzz 14.6) shapes the
# proof lines oglyph shaped (glyphs.json "proof"), fontTools draws its glyphs'
# outlines (nothing of oglyph's), and every glyph id and position is compared
# with oglyph's. Writes hb.json for the video and prints the differences.
#
#     python3 -I hb_proof.py glyphs.json hb.json
import json, subprocess, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

LINES = [  # font file, text, size, hb features: as glyphs.json's proof lines
    ("/usr/share/fonts/noto/NotoNaskhArabic-Regular.ttf", "السلام عليكم", 104, ""),
    ("/usr/share/fonts/noto/NotoSansDevanagari-Regular.ttf", "हिंदी धर्म क्षमा", 104, ""),
    ("/usr/share/fonts/noto/NotoSans-Regular.ttf", "Office 2/3 0", 104, "frac[7:10],zero[11:12]"),
]

ours = json.load(open(sys.argv[1]))["proof"]
out = {"lines": [], "paths": {}}
worst, glyphs = 0.0, 0
for (file, text, size, feats), mine in zip(LINES, ours):
    font = TTFont(file)
    upem = font["head"].unitsPerEm
    s = size / upem
    cmd = ["hb-shape", "--shapers=ot", "--output-format=json", "--no-glyph-names", file, text]
    if feats:
        cmd.insert(1, "--features=" + feats)
    hb = json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)
    order, gs = font.getGlyphOrder(), font.getGlyphSet()
    paths = out["paths"].setdefault(file, {})
    pen_x, line = 0, []
    for g in hb:
        x, y = (pen_x + g["dx"]) * s, -g["dy"] * s
        line.append([g["g"], x, y])
        pen_x += g["ax"]
        if str(g["g"]) not in paths:
            p = SVGPathPen(gs)
            gs[order[g["g"]]].draw(TransformPen(p, (s, 0, 0, -s, 0, 0)))
            paths[str(g["g"])] = p.getCommands()
    mg = mine["glyphs"]
    assert [g[0] for g in mg] == [g[0] for g in line], (text, [g[0] for g in mg], [g[0] for g in line])
    d = max(max(abs(a[2] - b[1]), abs(a[3] - b[2])) / s for a, b in zip(mg, line))
    worst, glyphs = max(worst, d), glyphs + len(line)
    print(f"{text}: {len(line)} glyphs, ids identical, worst position difference {d:.4f} font units")
    out["lines"].append({"file": file, "glyphs": line})
json.dump(out, open(sys.argv[2], "w"))
print(f"{glyphs} glyphs; worst difference {worst:.4f} font units")
