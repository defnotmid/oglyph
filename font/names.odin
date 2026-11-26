package font

import "base:runtime"
import "core:strings"

// A `name` table string, for a font picker: the family (name id 1, or 16
// for the typographic one), subfamily (2, 17), full name (4), PostScript
// name (6), and fvar's names (Axis.name_id, `instance`'s subfamily id:
// "Weight", "Bold"). The Windows Unicode English record as UTF-8, else a
// Unicode record, else the Macintosh record's bytes as they are; "" when
// the face has none.
name_string :: proc(f: ^Face, name_id: u16, allocator := context.allocator) -> string {
	span := f.tables[.name]
	if span.at == 0 {
		return ""
	}
	utf16_string :: proc(raw: []u8, allocator: runtime.Allocator) -> string {
		b := strings.builder_make(allocator)
		for j := 0; j + 1 < len(raw); j += 2 {
			r := rune(read_u16(raw, j))
			// A surrogate pair is one code point.
			if r >= 0xd800 && r < 0xdc00 {
				if lo := rune(read_u16(raw, j + 2)); lo >= 0xdc00 && lo < 0xe000 {
					r = 0x10000 + (r - 0xd800) << 10 + (lo - 0xdc00)
					j += 2
				}
			}
			strings.write_rune(&b, r)
		}
		return strings.to_string(b)
	}
	d := f.data[span.at:][:span.size]
	count := int(read_u16(d, 2))
	strings_at := int(read_u16(d, 4))
	unicode: []u8
	mac := ""
	for rec := 6; rec + 12 <= len(d) && count > 0; rec, count = rec + 12, count - 1 {
		if read_u16(d, rec + 6) != name_id {
			continue
		}
		platform, encoding, language := read_u16(d, rec), read_u16(d, rec + 2), read_u16(d, rec + 4)
		length := int(read_u16(d, rec + 8))
		at := strings_at + int(read_u16(d, rec + 10))
		if at + length > len(d) {
			continue
		}
		raw := d[at:][:length]
		if platform == 3 && (encoding == 1 || encoding == 10) && (language == 0x409 || language & 0xff == 0x09) {
			return utf16_string(raw, allocator)
		}
		if platform == 0 && length > 0 && unicode == nil {
			unicode = raw
		}
		if platform == 1 && mac == "" {
			mac = string(raw)
		}
	}
	if unicode != nil {
		return utf16_string(unicode, allocator)
	}
	return strings.clone(mac, allocator) if mac != "" else ""
}

// Glyph names, for a glyph browser: post's (TrueType), the CFF charset's,
// or a Type 1 font's CharStrings'.

// Sets `out[g]` to the name of each glyph g below len(out): a slice of the
// font data or a static string, "" when the face names none (post format 3,
// a CID-keyed CFF, whose charset holds CIDs). All at once, since post's
// names are found only by walking its strings.
glyph_names :: proc(f: ^Face, out: []string) {
	for &n in out {
		n = ""
	}
	if t := &f.t1; t.program != nil {
		for &n, g in out[:min(len(out), len(t.names))] {
			n = type1_text(t, t.names[g])
		}
		return
	}
	if f.cff.table != nil {
		cff_glyph_names(&f.cff, out)
		return
	}
	post := f.tables[.post]
	d := f.data[post.at:][:post.size]
	switch read_u32(d, 0) {
	case 0x10000:
		copy(out, MAC_GLYPH_NAMES[:])
	case 0x20000:
		count := int(read_u16(d, 32))
		index := records_clamped(d, 34, count, U16)
		// Pascal strings follow the indexes: the kth is name 258 + k.
		first := 34 + 2 * count
		n := 0
		for at := first; at < len(d) && at + 1 + int(d[at]) <= len(d); at += 1 + int(d[at]) {
			n += 1
		}
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		custom := make([]string, n, context.temp_allocator)
		at := first
		for &s in custom {
			s = string(d[at + 1:][:d[at]])
			at += 1 + int(d[at])
		}
		for x, g in index[:min(len(index), len(out))] {
			if k := int(x.v); k < len(MAC_GLYPH_NAMES) {
				out[g] = MAC_GLYPH_NAMES[k]
			} else if k - len(MAC_GLYPH_NAMES) < len(custom) {
				out[g] = custom[k - len(MAC_GLYPH_NAMES)]
			}
		}
	}
}

@(private)
cff_glyph_names :: proc(c: ^Cff, out: []string) {
	if c.fontdicts != nil || len(out) == 0 {
		return
	}
	name :: proc(c: ^Cff, sid: int) -> string {
		if sid < len(CFF_STRINGS) {
			return CFF_STRINGS[sid]
		}
		return string(index_get(c.strings, sid - len(CFF_STRINGS)))
	}
	out[0] = ".notdef"
	it := charset_init(c)
	for g, sid in charset_next(&it) {
		if g >= len(out) {
			break
		}
		out[g] = name(c, sid)
	}
}

// The standard Macintosh glyph names (post formats 1 and 2).
@(private, rodata)
MAC_GLYPH_NAMES := [258]string{
	".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl", "numbersign", "dollar",
	"percent", "ampersand", "quotesingle", "parenleft", "parenright", "asterisk", "plus", "comma",
	"hyphen", "period", "slash", "zero", "one", "two", "three", "four", "five", "six", "seven",
	"eight", "nine", "colon", "semicolon", "less", "equal", "greater", "question", "at", "A", "B",
	"C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U",
	"V", "W", "X", "Y", "Z", "bracketleft", "backslash", "bracketright", "asciicircum", "underscore",
	"grave", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r",
	"s", "t", "u", "v", "w", "x", "y", "z", "braceleft", "bar", "braceright", "asciitilde",
	"Adieresis", "Aring", "Ccedilla", "Eacute", "Ntilde", "Odieresis", "Udieresis", "aacute",
	"agrave", "acircumflex", "adieresis", "atilde", "aring", "ccedilla", "eacute", "egrave",
	"ecircumflex", "edieresis", "iacute", "igrave", "icircumflex", "idieresis", "ntilde", "oacute",
	"ograve", "ocircumflex", "odieresis", "otilde", "uacute", "ugrave", "ucircumflex", "udieresis",
	"dagger", "degree", "cent", "sterling", "section", "bullet", "paragraph", "germandbls",
	"registered", "copyright", "trademark", "acute", "dieresis", "notequal", "AE", "Oslash",
	"infinity", "plusminus", "lessequal", "greaterequal", "yen", "mu", "partialdiff", "summation",
	"product", "pi", "integral", "ordfeminine", "ordmasculine", "Omega", "ae", "oslash",
	"questiondown", "exclamdown", "logicalnot", "radical", "florin", "approxequal", "Delta",
	"guillemotleft", "guillemotright", "ellipsis", "nonbreakingspace", "Agrave", "Atilde", "Otilde",
	"OE", "oe", "endash", "emdash", "quotedblleft", "quotedblright", "quoteleft", "quoteright",
	"divide", "lozenge", "ydieresis", "Ydieresis", "fraction", "currency", "guilsinglleft",
	"guilsinglright", "fi", "fl", "daggerdbl", "periodcentered", "quotesinglbase", "quotedblbase",
	"perthousand", "Acircumflex", "Ecircumflex", "Aacute", "Edieresis", "Egrave", "Iacute",
	"Icircumflex", "Idieresis", "Igrave", "Oacute", "Ocircumflex", "apple", "Ograve", "Uacute",
	"Ucircumflex", "Ugrave", "dotlessi", "circumflex", "tilde", "macron", "breve", "dotaccent",
	"ring", "cedilla", "hungarumlaut", "ogonek", "caron", "Lslash", "lslash", "Scaron", "scaron",
	"Zcaron", "zcaron", "brokenbar", "Eth", "eth", "Yacute", "yacute", "Thorn", "thorn", "minus",
	"multiply", "onesuperior", "twosuperior", "threesuperior", "onehalf", "onequarter",
	"threequarters", "franc", "Gbreve", "gbreve", "Idotaccent", "Scedilla", "scedilla", "Cacute",
	"cacute", "Ccaron", "ccaron", "dcroat",
}

// CFF's standard strings: SIDs below 391.
@(private, rodata)
CFF_STRINGS := [391]string{
	".notdef", "space", "exclam", "quotedbl", "numbersign", "dollar", "percent", "ampersand",
	"quoteright", "parenleft", "parenright", "asterisk", "plus", "comma", "hyphen", "period", "slash",
	"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "colon",
	"semicolon", "less", "equal", "greater", "question", "at", "A", "B", "C", "D", "E", "F", "G", "H",
	"I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"bracketleft", "backslash", "bracketright", "asciicircum", "underscore", "quoteleft", "a", "b",
	"c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u",
	"v", "w", "x", "y", "z", "braceleft", "bar", "braceright", "asciitilde", "exclamdown", "cent",
	"sterling", "fraction", "yen", "florin", "section", "currency", "quotesingle", "quotedblleft",
	"guillemotleft", "guilsinglleft", "guilsinglright", "fi", "fl", "endash", "dagger", "daggerdbl",
	"periodcentered", "paragraph", "bullet", "quotesinglbase", "quotedblbase", "quotedblright",
	"guillemotright", "ellipsis", "perthousand", "questiondown", "grave", "acute", "circumflex",
	"tilde", "macron", "breve", "dotaccent", "dieresis", "ring", "cedilla", "hungarumlaut", "ogonek",
	"caron", "emdash", "AE", "ordfeminine", "Lslash", "Oslash", "OE", "ordmasculine", "ae",
	"dotlessi", "lslash", "oslash", "oe", "germandbls", "onesuperior", "logicalnot", "mu",
	"trademark", "Eth", "onehalf", "plusminus", "Thorn", "onequarter", "divide", "brokenbar",
	"degree", "thorn", "threequarters", "twosuperior", "registered", "minus", "eth", "multiply",
	"threesuperior", "copyright", "Aacute", "Acircumflex", "Adieresis", "Agrave", "Aring", "Atilde",
	"Ccedilla", "Eacute", "Ecircumflex", "Edieresis", "Egrave", "Iacute", "Icircumflex", "Idieresis",
	"Igrave", "Ntilde", "Oacute", "Ocircumflex", "Odieresis", "Ograve", "Otilde", "Scaron", "Uacute",
	"Ucircumflex", "Udieresis", "Ugrave", "Yacute", "Ydieresis", "Zcaron", "aacute", "acircumflex",
	"adieresis", "agrave", "aring", "atilde", "ccedilla", "eacute", "ecircumflex", "edieresis",
	"egrave", "iacute", "icircumflex", "idieresis", "igrave", "ntilde", "oacute", "ocircumflex",
	"odieresis", "ograve", "otilde", "scaron", "uacute", "ucircumflex", "udieresis", "ugrave",
	"yacute", "ydieresis", "zcaron", "exclamsmall", "Hungarumlautsmall", "dollaroldstyle",
	"dollarsuperior", "ampersandsmall", "Acutesmall", "parenleftsuperior", "parenrightsuperior",
	"twodotenleader", "onedotenleader", "zerooldstyle", "oneoldstyle", "twooldstyle", "threeoldstyle",
	"fouroldstyle", "fiveoldstyle", "sixoldstyle", "sevenoldstyle", "eightoldstyle", "nineoldstyle",
	"commasuperior", "threequartersemdash", "periodsuperior", "questionsmall", "asuperior",
	"bsuperior", "centsuperior", "dsuperior", "esuperior", "isuperior", "lsuperior", "msuperior",
	"nsuperior", "osuperior", "rsuperior", "ssuperior", "tsuperior", "ff", "ffi", "ffl",
	"parenleftinferior", "parenrightinferior", "Circumflexsmall", "hyphensuperior", "Gravesmall",
	"Asmall", "Bsmall", "Csmall", "Dsmall", "Esmall", "Fsmall", "Gsmall", "Hsmall", "Ismall",
	"Jsmall", "Ksmall", "Lsmall", "Msmall", "Nsmall", "Osmall", "Psmall", "Qsmall", "Rsmall",
	"Ssmall", "Tsmall", "Usmall", "Vsmall", "Wsmall", "Xsmall", "Ysmall", "Zsmall", "colonmonetary",
	"onefitted", "rupiah", "Tildesmall", "exclamdownsmall", "centoldstyle", "Lslashsmall",
	"Scaronsmall", "Zcaronsmall", "Dieresissmall", "Brevesmall", "Caronsmall", "Dotaccentsmall",
	"Macronsmall", "figuredash", "hypheninferior", "Ogoneksmall", "Ringsmall", "Cedillasmall",
	"questiondownsmall", "oneeighth", "threeeighths", "fiveeighths", "seveneighths", "onethird",
	"twothirds", "zerosuperior", "foursuperior", "fivesuperior", "sixsuperior", "sevensuperior",
	"eightsuperior", "ninesuperior", "zeroinferior", "oneinferior", "twoinferior", "threeinferior",
	"fourinferior", "fiveinferior", "sixinferior", "seveninferior", "eightinferior", "nineinferior",
	"centinferior", "dollarinferior", "periodinferior", "commainferior", "Agravesmall", "Aacutesmall",
	"Acircumflexsmall", "Atildesmall", "Adieresissmall", "Aringsmall", "AEsmall", "Ccedillasmall",
	"Egravesmall", "Eacutesmall", "Ecircumflexsmall", "Edieresissmall", "Igravesmall", "Iacutesmall",
	"Icircumflexsmall", "Idieresissmall", "Ethsmall", "Ntildesmall", "Ogravesmall", "Oacutesmall",
	"Ocircumflexsmall", "Otildesmall", "Odieresissmall", "OEsmall", "Oslashsmall", "Ugravesmall",
	"Uacutesmall", "Ucircumflexsmall", "Udieresissmall", "Yacutesmall", "Thornsmall",
	"Ydieresissmall", "001.000", "001.001", "001.002", "001.003", "Black", "Bold", "Book", "Light",
	"Medium", "Regular", "Roman", "Semibold",
}
// The characters glyph name `name` stands for, by the Adobe Glyph List
// specification: the name up to its first period, each part between
// underscores mapped and the results joined. A part maps by Zapf Dingbats'
// list (aN, when `zapf_dingbats`: the font is ZapfDingbats), else by the
// Adobe Glyph List (Aacute, dalethatafpatah: one character or more), else
// as uni and groups of four uppercase hexadecimal digits (BMP, no
// surrogates), else as u and four to six digits; else to nothing. Into
// `out` as far as it reaches (nil to count); how many there are. PDF
// draws a simple TrueType font's /Differences names through them and the
// (3, 1) cmap, and extracts text by them.
glyph_name_runes :: proc(name: string, out: []rune, zapf_dingbats := false) -> int {
	emit :: proc(out: []rune, n: int, r: rune) -> int {
		if n < len(out) {
			out[n] = r
		}
		return n + 1
	}
	// Uppercase hexadecimal digits only; -1 for anything else.
	hex :: proc(s: string) -> int {
		v := 0
		for c in transmute([]u8)s {
			switch c {
			case '0' ..= '9':
				v = v << 4 | int(c - '0')
			case 'A' ..= 'F':
				v = v << 4 | int(c - 'A' + 10)
			case:
				return -1
			}
		}
		return v
	}
	rest := name
	if i := strings.index_byte(rest, '.'); i >= 0 {
		rest = rest[:i]
	}
	n := 0
	for part in strings.split_iterator(&rest, "_") {
		if zapf_dingbats && len(part) >= 2 && part[0] == 'a' {
			if k := decimal(part[1:]); k >= 0 && k < len(ZAPF_DINGBATS) && ZAPF_DINGBATS[k] != 0 {
				n = emit(out, n, rune(ZAPF_DINGBATS[k]))
				continue
			}
		}
		// The first name at or after part.
		lo, hi := 0, len(AGL_NAME_AT) - 1
		for lo < hi {
			mid := (lo + hi) / 2
			if AGL_TEXT[AGL_NAME_AT[mid]:AGL_NAME_AT[mid + 1]] < part {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		if lo < len(AGL_NAME_AT) - 1 && AGL_TEXT[AGL_NAME_AT[lo]:AGL_NAME_AT[lo + 1]] == part {
			for r in AGL_RUNES[AGL_RUNE_AT[lo]:AGL_RUNE_AT[lo + 1]] {
				n = emit(out, n, rune(r))
			}
			continue
		}
		if digits := part[3:] if strings.has_prefix(part, "uni") else ""; len(digits) > 0 && len(digits) % 4 == 0 {
			ok := true
			for i := 0; i < len(digits); i += 4 {
				if v := hex(digits[i:][:4]); v < 0 || (v >= 0xd800 && v <= 0xdfff) {
					ok = false
				}
			}
			for i := 0; ok && i < len(digits); i += 4 {
				n = emit(out, n, rune(hex(digits[i:][:4])))
			}
			if ok {
				continue
			}
		}
		if len(part) >= 5 && len(part) <= 7 && part[0] == 'u' {
			if v := hex(part[1:]); v >= 0 && (v <= 0xd7ff || (v >= 0xe000 && v <= 0x10ffff)) {
				n = emit(out, n, rune(v))
			}
		}
	}
	return n
}

// Decimal digits only, at most 0xffff; -1 for anything else.
@(private)
decimal :: proc(s: string) -> int {
	v := 0
	for c in transmute([]u8)s {
		if c < '0' || c > '9' || v > 0xffff {
			return -1
		}
		v = v * 10 + int(c - '0')
	}
	return v
}
