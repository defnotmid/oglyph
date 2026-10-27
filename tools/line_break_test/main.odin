// Checks oglyph/shape's line breaks against Unicode's conformance test for
// the UCD version the tables come from (LineBreakTest.txt):
//
//   odin run tools/line_break_test -o:speed -- LineBreakTest.txt
//
// Each case lists its code points with ÷ where a break is allowed and ×
// where none is; prints the cases that differ and the count.
package line_break_test

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import sh "../../shape"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: line_break_test LineBreakTest.txt")
		os.exit(2)
	}
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil {
		fmt.eprintln("can't read", os.args[1], err)
		os.exit(2)
	}
	text: [dynamic]rune
	want: [dynamic]bool
	got: [dynamic]sh.Line_Break
	cases, failed := 0, 0
	content := string(data)
	for line in strings.split_lines_iterator(&content) {
		body := line
		if hash := strings.index_byte(body, '#'); hash >= 0 {
			body = body[:hash]
		}
		if strings.trim_space(body) == "" {
			continue
		}
		clear(&text)
		clear(&want)
		fields := strings.fields(body, context.temp_allocator)
		// ×/÷ before each code point and after the last: the first is sot's.
		for f, i in fields {
			switch f {
			case "÷", "×":
				if i > 0 {
					append(&want, f == "÷")
				}
			case:
				cp, ok := strconv.parse_uint(f, 16)
				if !ok {
					fmt.eprintln("bad code point", f, "in", line)
					os.exit(2)
				}
				append(&text, rune(cp))
			}
		}
		resize(&got, len(text))
		sh.line_breaks(text[:], got[:])
		cases += 1
		for w, i in want {
			if w != (got[i] != .None) {
				failed += 1
				if failed <= 40 {
					fmt.printfln("at %d: %s", i, line)
				}
				break
			}
		}
		free_all(context.temp_allocator)
	}
	fmt.printfln("%d/%d cases match (Unicode %s)", cases - failed, cases, sh.UNICODE_VERSION)
	if failed > 0 {
		os.exit(1)
	}
}
