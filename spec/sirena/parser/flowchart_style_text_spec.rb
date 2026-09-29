# frozen_string_literal: true

require "spec_helper"
require "benchmark"

# Every verdict below matches mermaid 11.12.0: run `mermaid.parse` on
# "graph TD\nA-->B\n" followed by `<prefix> <value>`. A row that disagrees
# with that call is wrong, whatever sirena does. This file asserts against
# `FlowchartStyleText.refusal` directly — the matched text and the token
# name it returns, not just "raises" — because the end-to-end ParseError
# message intentionally hides the two internal sentinel token names
# (NO_MATCH, STATE_SWITCH); see `Builders::Flowchart.check_style_text`.
RSpec.describe Sirena::Parser::FlowchartStyleText do
  describe ".refusal for a style/classDef props value" do
    {
      "a hard NBSP between values" => "fill:#f00, stroke:#000",
      "a line separator (U+2028) between values" => "fill:#f00, stroke:#000",
      "an ideographic space (U+3000) between values" => "fill:#f00,　stroke:#000",
      "a byte-order mark (U+FEFF) between values" => "fill:#f00,﻿stroke:#000",
      "an immediately-closed quoted pair" => 'fill:""'
    }.each do |description, props|
      it "accepts #{description}" do
        expect(described_class.refusal("style", props)).to be_nil
      end
    end

    {
      "a Unicode letter mermaid's INITIAL rules cannot lex at all" => ["fill:€", "€\n", "NO_MATCH"]
    }.each do |description, (props, matched, token)|
      it "refuses #{description} with the exact matched text and token" do
        expect(described_class.refusal("style", props)).to eq([matched, token])
      end
    end
  end

  describe ".refusal for a linkStyle curve name" do
    {
      "`end` followed by a non-ASCII letter" => ["endé", "end", "end"],
      "`style` followed by a non-ASCII letter" => ["styleé", "style", "STYLE"],
      "`graph` followed by a non-ASCII letter" => ["graphé", "graph", "GRAPH"],
      "an empty quoted pair on its own" => ['""', '""', "STR"],
      "two empty quoted pairs back to back, still no token" => ['""""', '""""', "STR"]
    }.each do |description, (curve, matched, token)|
      it "refuses #{description} with the exact matched text and token" do
        expect(described_class.refusal("linkStyle", "", curve: curve)).to eq([matched, token])
      end
    end

    # mermaid refuses a curve only when it reduces to zero tokens
    # (`alphaNum` needs at least one); an empty pair that consumes no
    # token of its own is harmless next to any real token elsewhere in
    # the same curve. Regression: an earlier version of `scan` refused
    # any empty pair found anywhere in the curve, not just a wholly
    # empty one.
    {
      "a real token after the empty pair" => '""-',
      "a NODE_STRING word right after the empty pair" => '""basis',
      "a real token before the empty pair" => ':""',
      "a comma before the empty pair" => ',""',
      "a UNICODE_TEXT character after the empty pair" => '""é'
    }.each do |description, curve|
      it "accepts #{description}, which is not a zero-token curve" do
        expect(described_class.refusal("linkStyle", "", curve: curve)).to be_nil
      end
    end

    it "refuses a zero-token curve before ever looking at otherwise-valid props" do
      expect(described_class.refusal("linkStyle", "stroke:red", curve: '""')).to eq(['""', "STR"])
    end

    {
      # `v` is DOWN, allowed as a curve name (`CURVE_ALLOWED`) but not as
      # a props value (`ALLOWED`) — the split the two allowlists exist
      # for. Bare `style`/`default`/`interpolate` are grammar keywords
      # everywhere, refused in both positions, so they prove nothing about
      # the split on their own.
      "`v` (DOWN, curve-only)" => "v"
    }.each do |description, curve|
      it "accepts #{description}, which a props value would refuse" do
        expect(described_class.refusal("linkStyle", "", curve: curve)).to be_nil
        expect(described_class.refusal("style", curve)).to eq([curve, "DOWN"])
      end
    end

    {
      # `prepass` doubles the placeholder's leading degree sign for an
      # all-digit entity (`encodeEntities`'s own `isInt` branch); a bare
      # `linkStyle` curve is the one position where the substitution
      # survives to be scanned at all (`style`/`classDef` strip the
      # trailing `;` an entity needs before `prepass` ever runs — see
      # `.entity`'s spec coverage in flowchart_parser_link_style_spec.rb),
      # so it is the only place the two branches are told apart.
      "a numeric entity (doubled placeholder)" => ["#123;", "\u{B0}\u{B0}123\u{B6}\u{DF} \n"],
      "a non-numeric entity (single placeholder)" => ["#abc;", "\u{B0}abc\u{B6}\u{DF} \n"]
    }.each do |description, (curve, matched)|
      it "refuses #{description} with the exact placeholder text" do
        expect(described_class.refusal("linkStyle", "", curve: curve)).to eq([matched, "NO_MATCH"])
      end
    end
  end

  describe ".refusal, gating the direction_* rules by whether the full pattern completes" do
    # `direction_*`'s five rules are unbounded (`.*direction…`), so trying
    # them at every position is quadratic once a long value never has a
    # complete `direction <code>` — see the "scans close to linearly" spec
    # below, which proves the pruning's performance effect directly. These
    # two examples pin its correctness: the rules engage only when the
    # full pattern is reachable from the current position: `direction_reach`
    # (a `TriggerReach` bounded by `DIRECTION_LIMIT`) is checked per position.
    it "activates them once the full pattern occurs, matching the whole line as direction_tb" do
      expect(described_class.refusal("style", "fill:red direction TB"))
        .to eq(["fill:red direction TB", "direction_tb"])
    end

    it "never activates them for a bare `direction` word with no valid code after it" do
      expect(described_class.refusal("style", "fill:direction")).to be_nil
    end
  end

  describe ".refusal for a direction_* rule's leading span, broken by a JS line terminator" do
    # Each `direction_*` rule's leading span was a bare Ruby `.*`, which —
    # unlike JavaScript's `.` — crosses \r and the two Unicode line/paragraph
    # separators. Left unfixed, `"foo\rdirection TB"` matches as ONE
    # direction_tb token spanning `"foo\rdirection TB"` instead of the real
    # lexer's two tokens (`foo`, then a break, then `direction TB`), so the
    # reported match names the wrong offending text. Reverting `JS_DOT` back
    # to Ruby's `.*` here makes this example return the pre-`foo` span
    # instead of just `"direction TB"`.
    {
      "a carriage return (\\r)" => "\r",
      "a line separator (U+2028)" => " ",
      "a paragraph separator (U+2029)" => " "
    }.each do |description, sep|
      it "stops the leading span at #{description}, matching only from `direction`" do
        expect(described_class.refusal("style", "foo#{sep}direction TB"))
          .to eq(["direction TB", "direction_tb"])
      end
    end
  end

  describe ".refusal on a long value whose only tail token is `direction`" do
    # This shape contains no `@`/`-`/`=`/`~`, so it never engages
    # `LINK_ID`/`LINK`'s own `TriggerReach` at all (see the two describes
    # below for that) — what it bounds is `direction_reach`, guarding the
    # five unbounded `direction_*` rules (`#{JS_DOT}*direction…`).
    it "scans close to linearly even when direction sits right before the end" do
      small_props = "#{'a,' * 200}a direction"
      large_props = "#{'a,' * 5000}a direction"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the values; measured against the pre-fix implementation (which
      # rebuilt the active-rule set once per scan from a coarse
      # anywhere-ahead-of-scan_start check) this shape costs ~537x (best
      # of 3 small samples 0.015s -> a single 3.76s large run); the
      # position-bounded fix measured here costs ~54x (best of 3 samples
      # each side). A 150x ceiling sits above the bounded case with room
      # for a loaded machine and well below the quadratic one.
      expect(large_time).to be < small_time * 150
    end
  end

  describe ".refusal on a long value with a COMPLETE `direction` past a JS line terminator" do
    # Keep the `\r` before `direction TB`: `direction_tb`'s leading span
    # cannot cross a JS line terminator, so only this shape exercises the
    # per-position bound. Without it the unbounded code passes too.
    it "scans close to linearly, not quadratically, with a terminator before a complete direction" do
      small_props = "#{'a,' * 200}a\rdirection TB"
      large_props = "#{'a,' * 5000}a\rdirection TB"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the input: bounded scanning grows ~28x, unbounded ~259x.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal on a long value with a LINK_ID trigger at the very end" do
    # LINK_ID's own regex is `[^\s"]+@(?=[^{"])`, greedy and unbounded. A
    # trigger that fires on any `@` regardless of what follows it (the
    # pre-round-4 shape) does not bound this: an `@{`/`@"` tail can never
    # complete the match, so `TriggerReach` reported every earlier
    # position reachable anyway, and the real regex paid a full
    # backtracking search from each one. `LINK_ID_TRIGGER`'s own lookahead
    # closes that — this spec puts a never-completing `@{` at the tail,
    # where the old, looser trigger was at its worst.
    it "scans close to linearly even with an `@{` tail that can never complete LINK_ID" do
      small_props = "#{'a,' * 200}a@{"
      large_props = "#{'a,' * 20_000}a@{"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 100x the values; measured against `LINK_ID_TRIGGER = /@/` (bare,
      # no lookahead) this shape costs ~857x (best of 3 small samples
      # 0.006s -> best of 3 large samples 4.7s); the lookahead-gated
      # trigger measured here costs ~100x (best of 3 samples each side,
      # consistently 99-101x across repeated runs). A 250x ceiling sits
      # well above the linear case with room for a loaded machine and
      # well below the quadratic one.
      expect(large_time).to be < small_time * 250
    end
  end

  describe ".refusal on a value dense in link-trigger characters that never complete a token" do
    # `,-` repeated never forms a complete LINK/START_LINK token (each `-`
    # is a lone MINUS, each `,` a lone COMMA) but every `-` is a
    # `LINK_TRIGGER` hit, so this is where a broken cursor walk shows up:
    # `TriggerReach#reachable?` must advance `@trigger_cursor` forward
    # only, from wherever the previous call left it, or it degrades into
    # a full list re-walk at every position.
    it "scans close to linearly even though every other character is a link trigger" do
      small_props = "fill:red#{',-' * 200}"
      large_props = "fill:red#{',-' * 5000}"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the values; measured against a `TriggerReach#reachable?` that
      # resets `@trigger_cursor = 0` at the top of every call (undoing the
      # "walk forward only" invariant, otherwise identical) this shape
      # costs ~180-205x across repeated runs (best of 3 small samples
      # 0.007-0.008s -> best of 3 large samples 1.4-1.5s); the
      # forward-only cursor measured here costs ~25x. A 100x ceiling sits
      # above the linear case with room for a loaded machine and well
      # below the reset-cursor one.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal correctness for the LINK/START_LINK TriggerReach gate" do
    # Every LINK/START_LINK rule starts with `JS_SPACE*`, so a character it
    # would still accept as prefix text right before an arrow must not end
    # `LINK_LIMIT`'s reach either. Pins the regression directly: with
    # `LINK_LIMIT` counting a plain space as a limit, the first row below
    # returned `["--b@", "LINK_ID"]` — the space blocked LINK/START_LINK's
    # reach, so LINK_ID won at the dash instead. Every row here is one
    # member of `LINK_LIMIT`'s own exclusion class (`xo<.=~-`, plus
    # `JS_SPACE_CHARS`); dropping any single one from the regex changes at
    # least one row without failing any other spec in this file — verified
    # against mermaid-cli 11.12.0 (`mermaid.parse`), which reports
    # `got 'START_LINK'`/`got 'LINK'` for all six.
    {
      "a plain ASCII space" => ["fill:a --b@c", [" --", "START_LINK"]],
      "a tab" => ["fill:a\tx--b@c", ["\tx--", "START_LINK"]],
      "a hard NBSP" => ["fill:a x--b@c", [" x--", "START_LINK"]],
      "`x`" => ["fill:a x--b@c", [" x--", "START_LINK"]],
      "`o`" => ["fill:a o--b@c", [" o--", "START_LINK"]],
      "`<`" => ["fill:a <--b@c", [" <--", "START_LINK"]],
      "`.`" => ["fill:a .-b@c", [" .-", "LINK"]]
    }.each do |description, (props, expected)|
      it "gates #{description} before an arrow as reachable, matching mermaid's own verdict" do
        expect(described_class.refusal("style", props)).to eq(expected)
      end
    end

    # `TriggerReach#reachable?` falls through to `next_limit.nil?` only once
    # `@limits` is exhausted — every row above has a `LINK_LIMIT` character
    # ahead of its own trigger, so none exercises that branch. A value made
    # only of `JS_SPACE`/`LINK_LIMIT`-excluded characters has no limit at
    # all, so this is the one case that does: verified against mermaid-cli
    # 11.12.0, which reports `got 'LINK'` for `style A   ---   `.
    it "gates a trigger with no limit character anywhere in the value as reachable" do
      expect(described_class.refusal("style", "   ---   ")).to eq(["   ---   \n", "LINK"])
    end
  end

  describe ".refusal on a long value containing a non-ASCII character throughout" do
    # Every "space" here is non-ASCII (NBSP), the shape that made character
    # `pos` resolution the bottleneck before the byte-offset fix — see
    # `FlowchartStyleText::TriggerReach`'s class comment and `scan`'s own
    # comment on `byte_pos` for why. This spec is what proves that fix
    # holds under the worst case.
    it "scans close to linearly with NBSP standing in for every space" do
      small_props = "fill:#{'  ' * 200}"
      large_props = "fill:#{'  ' * 5000}"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the values; measured against the pre-fix implementation (which
      # called `Regexp#match?(text, pos)`/`MatchData#begin` with a
      # character `pos` throughout) this shape costs ~253x (best of 3
      # small samples 0.024s -> best of 3 large samples 6.19s); the
      # byte-offset fix measured here costs ~17x. A 100x ceiling, the same
      # one the all-ASCII sibling spec above uses for this exact growth,
      # sits well above the fixed case and well below the quadratic one.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal on a run of whitespace before a trigger that never completes" do
    # Every LINK/START_LINK rule starts with `JS_SPACE*`; at a position
    # inside a run of spaces that piece backtracks through every remaining
    # space in the run before the rest of the rule can fail. `LINK_LIMIT`
    # correctly does not count the run's own characters as ending the
    # reach (the spec above), so `TriggerReach#reachable?` stays true at
    # every position in the run once a real trigger sits anywhere ahead —
    # retried at every position, that failed backtrack was quadratic in
    # the run's length. `-a` after the run never completes LINK or
    # START_LINK (both need two dashes or a real pair), so every position
    # in the run fails, which is exactly the shape that was quadratic.
    it "scans close to linearly with an ASCII space run before an incomplete trigger" do
      small_props = "fill:a#{' ' * 200}-a"
      large_props = "fill:a#{' ' * 5000}-a"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the values; measured against the pre-round-5 implementation
      # (which retried every LINK/START_LINK regex's own `JS_SPACE*`
      # backtrack at every position in the run) this shape costs ~202x
      # (best of 3 small samples 0.0064s -> best of 3 large samples
      # 1.29s); the per-run memoized fix measured here costs ~12x. A 100x
      # ceiling sits above the linear case with room for a loaded machine
      # and well below the quadratic one.
      expect(large_time).to be < small_time * 100
    end

    it "scans close to linearly with an NBSP run before an incomplete trigger" do
      small_props = "fill:a#{' ' * 200}-a"
      large_props = "fill:a#{' ' * 5000}-a"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      # 25x the values; measured against the pre-round-5 implementation
      # this shape costs ~294x (best of 3 small samples 0.0067s -> best of
      # 3 large samples 1.96s); the fix measured here costs ~14x. Same
      # 100x ceiling as the ASCII sibling above.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal on a run of whitespace before each LINK/START_LINK prefix character" do
    # `LINK_LIMIT` excludes `xo<.=~-` precisely because every LINK/START_LINK
    # rule can lead with one of them right after its `JS_SPACE*`; each one
    # reopens the same backtracking risk the two specs above pin for a bare
    # `-`, and all seven are gated by the exact same `link_active` boolean
    # in `scan`, so this covers the whole family in one timing budget rather
    # than trusting that one character generalizes. Each tail is built from
    # `LINK_LIMIT`-excluded characters only, up to one real trigger that
    # never completes a token: `-a`/`=a`/`~a` (a lone occurrence, one short
    # of what any rule needs), `x-a`/`o-a`/`<-a` (the lead character, then
    # a lone dash), `.=a` (a lone dot, which would complete against a
    # trailing dash instead — `=` avoids that).
    it "stays close to linear for every LINK/START_LINK prefix character, not only `-`" do
      tails = %w[-a =a ~a x-a o-a <-a .=a]
      small_time = Array.new(3) do
        Benchmark.realtime { tails.each { |tail| described_class.refusal("style", "fill:a#{' ' * 200}#{tail}") } }
      end.min
      large_time = Array.new(3) do
        Benchmark.realtime { tails.each { |tail| described_class.refusal("style", "fill:a#{' ' * 5000}#{tail}") } }
      end.min

      # 25x the values, summed over all 7 shapes each side; same 100x
      # ceiling as the single-character specs above.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal on a long but entirely valid value" do
    it "returns nil without raising, however many comma-separated values there are" do
      props = "fill:#{(['red'] * 5000).join(',')}"

      expect(described_class.refusal("style", props)).to be_nil
    end

    it "scans close to linearly, not quadratically, in the value length" do
      small_props = "fill:#{(['red'] * 200).join(',')}"
      large_props = "fill:#{(['red'] * 5000).join(',')}"
      described_class.refusal("style", small_props) # warm up regexp compilation once, outside the timed run

      small = described_class.refusal("style", small_props)
      small_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", small_props) } }.min
      large_time = Array.new(3) { Benchmark.realtime { described_class.refusal("style", large_props) } }.min

      expect(small).to be_nil
      # 25x the values, measured against the pre-active_rules quadratic
      # implementation, cost ~267x (0.0042s -> 1.12s); the linear one costs
      # ~25x (0.0018s -> 0.044s). A 100x ceiling — with no additive slack,
      # which would hide the same regression by letting anything under
      # ~1s through regardless of small_time — sits above the linear case
      # with room for a loaded machine and below the quadratic one.
      expect(large_time).to be < small_time * 100
    end
  end

  describe ".refusal for a style/classDef run that a JS line terminator should break" do
    # JavaScript's `.` without the `s` flag excludes \n, \r, U+2028 and
    # U+2029; Ruby's bare `.` excludes only \n. `STYLE_RUN`/`CLASS_DEF_RUN`
    # glue a `style`/`classDef` statement's own trailing `;` onto its `#`
    # run so `encodeEntities` can find it — ported with Ruby's `.` before
    # round 4, that glue crossed \r/U+2028/U+2029 where mermaid's own
    # `.*` would not, so a `;` mermaid keeps was stripped here, and an
    # entity mermaid refuses was silently accepted. Verified against the
    # mermaid-cli 11.12.0 oracle: `style A x <sep>:#b;y` and
    # `classDef c x <sep>:#b;y` are both a parse error for every `<sep>`
    # below.
    {
      "a carriage return (\\r)" => "\r",
      "a line separator (U+2028)" => " ",
      "a paragraph separator (U+2029)" => " "
    }.each do |description, sep|
      it "keeps the `style` run's `;` in place across #{description}, refusing the entity" do
        expect(described_class.refusal("style", "x #{sep}:#b;y")).to eq(["\u{FB02}", "UNICODE_TEXT"])
      end

      it "keeps the `classDef` run's `;` in place across #{description}, refusing the entity" do
        expect(described_class.refusal("classDef", "c x #{sep}:#b;y")).to eq(["\u{FB02}", "UNICODE_TEXT"])
      end
    end
  end

  describe ".refusal for a style/classDef run's own `#...;` span, broken by a JS line terminator" do
    # The sibling describe above pins the first `JS_DOT` (between the
    # keyword and `:`); this one pins the second, between `#` and the
    # closing `;`. Reverting just that one to Ruby's bare `.` lets the glue
    # cross the terminator to reach the LATER `;` instead of stopping at
    # the one right after `#b`, which strips the wrong `;` and leaves an
    # entity mermaid's own lexer accepts as literal text. Verified against
    # the mermaid-cli 11.12.0 oracle: `style A x :#b;c<sep>;` and
    # `classDef c x :#b;c<sep>;` both parse for every `<sep>` below.
    {
      "a carriage return (\\r)" => "\r",
      "a line separator (U+2028)" => " ",
      "a paragraph separator (U+2029)" => " "
    }.each do |description, sep|
      it "stops the `style` run's `;` at the first `#...;`, accepting the value across #{description}" do
        expect(described_class.refusal("style", "x :#b;c#{sep};")).to be_nil
      end

      it "stops the `classDef` run's `;` at the first `#...;`, accepting the value across #{description}" do
        expect(described_class.refusal("classDef", "c x :#b;c#{sep};")).to be_nil
      end
    end
  end

  describe ".entity" do
    # `.entity` runs the same gluing `.prepass` does but stops one step
    # short of substituting it, so `check_link_entities` can name the exact
    # offending text in its own error message — pinned here directly since
    # end-to-end coverage of that message goes through `linkStyle`, which
    # never itself triggers the style/classDef gluing (see the comment on
    # the "look-alike text" describe in flowchart_parser_style_text_spec.rb).
    it "returns the #name; text a linkStyle value is left holding" do
      expect(described_class.entity("linkStyle 0 stroke:#f00;")).to eq("#f00;")
    end

    # Same stripping `.prepass` applies: a `style`/`classDef` run's own
    # trailing `;` is glued onto the hashed value before either method
    # goes looking for `#name;`, so it is gone by the time `.entity` looks
    # — not because there was no entity, but because gluing already ate
    # the one character that would have made it one.
    it "returns nil once style's own glued semicolon has already been stripped" do
      expect(described_class.entity("style A stroke:#f00;")).to be_nil
    end

    it "returns nil once classDef's own glued semicolon has already been stripped" do
      expect(described_class.entity("classDef c1 stroke:#f00;")).to be_nil
    end

    it "returns nil for text with no #name; entity at all" do
      expect(described_class.entity("linkStyle 0 stroke:red")).to be_nil
    end
  end

  # White-box: `TriggerReach` is `private_constant`, reached here via
  # `const_get` the same way `scan` (below) is reached via `send` — both
  # bypass Ruby privacy on purpose to pin an internal invariant no public
  # call observes directly.
  describe "TriggerReach (private) cursor advancement" do
    let(:trigger_reach_class) { described_class.send(:const_get, :TriggerReach) }

    # `@` at byte offsets 3, 7, 11; the limit regexp matches nothing, so
    # only the trigger cursor moves. Asserts the cursor's own position
    # after each call — an iteration count, not wall time — so deleting
    # the `@trigger_cursor` advance in `reachable?` leaves it at 0 and
    # this goes red deterministically, without depending on a clock.
    it "advances the trigger cursor past every occurrence behind byte_pos, and no further" do
      reach = trigger_reach_class.new("aaa@bbb@ccc@ddd", 0, /@/, /zzz/)

      reach.reachable?(0)
      expect(reach.instance_variable_get(:@trigger_cursor)).to eq(0)

      reach.reachable?(10)
      expect(reach.instance_variable_get(:@trigger_cursor)).to eq(2)

      reach.reachable?(20)
      expect(reach.instance_variable_get(:@trigger_cursor)).to eq(3)
    end
  end

  # White-box: `scan` is `private_class_method`, called here via `send`
  # rather than through `.refusal`, which always appends a trailing "\n"
  # and so can never itself pass scan an embedded newline.
  describe ".scan (private) stopping at an embedded NEWLINE" do
    # `NEWLINE` is in `ALLOWED`, so hitting it does not return early; the
    # loop instead relies on the `TERMINAL_TOKENS` break to stop before
    # trying to lex whatever comes after an EMBEDDED newline (never
    # produced by `.refusal`, only reachable by calling `scan` directly,
    # as a hostile caller of the private API would). Without that break,
    # the scan would carry on and refuse the `€` that follows instead of
    # silently stopping at the newline.
    it "stops at the first embedded NEWLINE instead of scanning past it" do
      expect(described_class.send(:scan, "a\nb€", 0, nil)).to be_nil
    end
  end
end
