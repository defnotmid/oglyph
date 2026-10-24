# Third-party notices

oglyph is MIT licensed ([LICENSE](LICENSE)). Every license it carries is a
separate file in [LICENSES/](LICENSES).

| Component | Where | License file |
| --- | --- | --- |
| HarfBuzz 14.6 | `shape/`: the shapers, lookup application and fallbacks follow its code, and `shape/syllable_data.odin` and the Indic and USE categories in `shape/unicode_data.odin` are generated from its tables | `LICENSES/HarfBuzz-MIT.txt` |
| Unicode Character Database 17.0.0 | `shape/unicode_data.odin`: generated from its data files (`tools/shape_unicode/gen.pl`) | `LICENSES/Unicode-3.0.txt` |
| Bitstream Vera Sans | `assets/Vera.ttf`: the tests' font | `LICENSES/Bitstream-Vera.txt` |
| JetBrains Mono, Noto Sans Arabic | `assets/JetBrainsMono-Regular.ttf`, `assets/NotoSansArabic-Bold.ttf`: the tests' fonts (SIL Open Font License 1.1) | `LICENSES/OFL-1.1.txt` |
