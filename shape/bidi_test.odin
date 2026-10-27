package shape

import "core:testing"
import "core:unicode/utf8"

// Bidi levels in a left-to-right paragraph, each character's class from the
// UCD.
@(test)
test_bidi_levels :: proc(t: ^testing.T) {
	levels :: proc(text: string) -> string {
		runes := utf8.string_to_runes(text, context.temp_allocator)
		cls := make([]Bidi_Class, len(runes), context.temp_allocator)
		lv := make([]u8, len(runes), context.temp_allocator)
		for r, i in runes {
			cls[i] = char_bidi_class(r)
		}
		bidi_levels(cls, lv)
		out := make([]u8, len(lv), context.temp_allocator)
		for l, i in lv {
			out[i] = '0' + l
		}
		return string(out)
	}
	cases := [?]struct {
		text, want: string,
	} {
		{"abc", "000"},
		// Trailing neutrals after R take the paragraph's direction.
		{"ab سلم!", "0001110"},
		// Neutrals between R take R; a space before L text does not.
		{"ab سلم سلم cd", "0001111111000"},
		// Numbers after R: level 2, with the separator joining them.
		{"سلم 12.5", "11112222"},
		{"سلم-12", "111122"},
		// Arabic-Indic digits are AN, after R or L.
		{"ab ١٢", "00022"},
		// Numbers after L text are L, with their terminator.
		{"ab 12%", "000000"},
		// Brackets around R text inside L text keep the paragraph's direction.
		{"a (سلم) b", "000111000"},
		// An emoji after R text at the end of the line goes right.
		{"سلم 👍", "11100"},
		// Arabic punctuation is an Arabic letter's class (AL), Hebrew's R.
		{"ab سلم؟ cd", "0001111000"},
		{"שלום׃", "11111"},
		// An embedding control is ignored (X9), an isolate neutral.
		{"a\u202Bb", "000"},
		{"سلم\u2067ab", "111000"},
	}
	for c in cases {
		testing.expectf(t, levels(c.text) == c.want, "%q: got %s, want %s", c.text, levels(c.text), c.want)
	}
}
