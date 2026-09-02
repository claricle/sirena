# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe Sirena::Source do
  describe ".split" do
    it "separates a frontmatter block from the body" do
      result = described_class.split(
        "---\ntitle: My Chart\n---\nflowchart LR\n  A-->B\n"
      )

      expect(result[:frontmatter]).to eq("title: My Chart\n")
      expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
    end

    it "separates a %%{init}%% directive from the body" do
      result = described_class.split(
        %(%%{init: {"theme":"base"}}%%\nsequenceDiagram\n  A->>B: m\n)
      )

      expect(result[:directives])
        .to eq([%(%%{init: {"theme":"base"}}%%)])
      expect(result[:body]).to eq("sequenceDiagram\n  A->>B: m\n")
    end

    it "reads a directive as a directive, not as a %% comment" do
      # `%%{` also opens a valid `%%` comment, so a comment rule without its
      # negative lookahead swallows every directive. The body still parses
      # either way, which is why this asserts on :directives rather than on
      # the render succeeding.
      result = described_class.split("%%{init: {}}%%\nflowchart LR\n  A-->B\n")

      expect(result[:directives]).to eq(["%%{init: {}}%%"])
    end

    it "handles a directive spanning several lines" do
      source = "%%{init: {\n  \"theme\": \"base\"\n}}%%\nflowchart LR\n  A-->B\n"

      result = described_class.split(source)

      expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
    end

    it "strips leading %% comment lines" do
      result = described_class.split("%% a note\nclassDiagram\n  class C1\n")

      expect(result[:body]).to eq("classDiagram\n  class C1\n")
    end

    it "takes all three together" do
      source = "---\ntitle: T\n---\n%%{init: {}}%%\n%% note\nflowchart LR\n  A-->B\n"

      result = described_class.split(source)

      expect(result[:frontmatter]).to eq("title: T\n")
      expect(result[:directives]).to eq(["%%{init: {}}%%"])
      expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
    end

    it "leaves a source with no preamble untouched" do
      source = "flowchart LR\n  A-->B\n"

      expect(described_class.split(source)[:body]).to eq(source)
    end

    context "when the body itself contains preamble-looking text" do
      it "does not treat a --- later in the body as a fence" do
        source = "flowchart LR\n  A-->B\n---\n"

        expect(described_class.split(source)[:body]).to eq(source)
      end

      it "does not treat %% inside a quoted label as a comment" do
        source = %(flowchart LR\n  A["100%% done"]-->B\n)

        expect(described_class.split(source)[:body]).to eq(source)
      end
    end

    context "with CRLF line endings" do
      # mmdc renders these; the LF-only patterns left them unsplit, so they
      # died at detection.
      it "splits frontmatter and normalises the endings" do
        # Carriage returns are stripped once, here, rather than left to leak
        # into labels and geometry downstream — they broke every passing
        # user_journey case when a source used CRLF.
        result = described_class.split(
          "---\r\ntitle: T\r\n---\r\nflowchart LR\r\n  A-->B\r\n"
        )

        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end

      it "normalises a lone carriage return too" do
        result = described_class.split("%% note\rflowchart LR\r  A-->B\r")

        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end

      it "splits a directive" do
        result = described_class.split(
          "%%{init: {}}%%\r\nflowchart LR\r\n  A-->B\r\n"
        )

        expect(result[:directives]).to eq(["%%{init: {}}%%"])
      end
    end

    # A bare `%%` and a directive with no header are not universally
    # invalid. Each of the 23 types was probed with all four degenerate
    # forms: eight refuse them, fifteen render them. Refusing them in the
    # split — before the type is even known — rejected the fifteen.
    context "with a degenerate preamble item" do
      {
        "a bare marker" => "%%",
        "an empty directive" => "%%{}%%",
        "a whitespace directive" => "%%{  }%%",
        "a directive with no header" => "%%{!}%%"
      }.each do |label, preamble|
        it "refuses #{label} before a flowchart" do
          source = "#{preamble}\nflowchart LR\n  A-->B\n"

          expect { Sirena::Engine.new.render(source) }
            .to raise_error(Sirena::Engine::PipelineError, /does not accept/)
        end

        it "renders #{label} before a sequence diagram" do
          source = "#{preamble}\nsequenceDiagram\n  A->>B: hi\n"

          expect { Sirena::Engine.new.render(source) }.not_to raise_error
        end
      end

      # stateDiagram sits between the two: it draws a bare marker and
      # refuses a headerless directive.
      it "renders a bare marker before a state diagram" do
        source = "%%\nstateDiagram-v2\n  [*] --> S\n"

        expect { Sirena::Engine.new.render(source) }.not_to raise_error
      end

      it "refuses a headerless directive before a state diagram" do
        source = "%%{}%%\nstateDiagram-v2\n  [*] --> S\n"

        expect { Sirena::Engine.new.render(source) }
          .to raise_error(Sirena::Engine::PipelineError, /does not accept/)
      end

      it "leaves an ordinary comment alone for every type" do
        expect { Sirena::Engine.new.render("%% note\nflowchart LR\n  A-->B\n") }
          .not_to raise_error
      end

      it "reports the item back from the split" do
        result = described_class.split("%%\n%%{}%%\nflowchart LR\n")

        expect(result[:degenerate]).to contain_exactly(:comment, :directive)
      end

      # Trailing whitespace makes it an ordinary comment: mmdc renders
      # `%% ` and `%%\t` in front of a flowchart and refuses a bare `%%`.
      it "does not call a marker with trailing whitespace bare" do
        expect(described_class.split("%% \nflowchart LR\n")[:degenerate])
          .to be_empty
        expect(described_class.split("%%\t\nflowchart LR\n")[:degenerate])
          .to be_empty
      end

      it "reports nothing for an ordinary preamble" do
        result = described_class.split("%% note\n%%{init: {}}%%\nflowchart LR\n")

        expect(result[:degenerate]).to be_empty
      end
    end

    context "with an empty frontmatter block" do
      it "is refused, as mermaid refuses it" do
        expect { Sirena::Engine.new.render("---\n---\nflowchart LR\n  A-->B\n") }
          .to raise_error(Sirena::Engine::DiagramTypeError)
      end
    end

    context "with blank lines between preamble items" do
      # mmdc renders all of these. Left unconsumed, a blank line ended the
      # preamble scan and whatever followed stayed in the body, so the
      # source died at detection.
      {
        "between two comments" => "%% one\n\n%% two\nflowchart LR\n  A-->B\n",
        "before the body" => "%% one\n\n\nflowchart LR\n  A-->B\n",
        "after frontmatter" =>
          "---\ntitle: T\n---\n\n\nflowchart LR\n  A-->B\n"
      }.each do |label, source|
        it "consumes a blank line #{label}" do
          expect(described_class.split(source)[:body])
            .to eq("flowchart LR\n  A-->B\n")
        end
      end

      it "keeps both directives when a blank line separates them" do
        source = "%%{init: {}}%%\n\n%%{init: {}}%%\nflowchart LR\n  A-->B\n"

        expect(described_class.split(source)[:directives].size).to eq(2)
      end
    end

    context "with a directive terminator" do
      # Mermaid's terminator is a raw token: the FIRST `}%%` ends the
      # directive, quotes and all. Brace balancing got this backwards in
      # both directions — it rejected an unterminated quote mermaid takes,
      # and accepted a quoted `}%%` mermaid refuses.
      it "ends at the first }%% even inside a quoted value" do
        source = %(%%{init: {"a":"x}%%y"}}%%\nflowchart LR\n  A-->B\n)

        result = described_class.split(source)

        expect(result[:directives]).to eq([%(%%{init: {"a":"x}%%)])
        expect(result[:body]).to start_with(%(y"}}%%))
      end

      it "does not run past it on an unterminated quote" do
        source = %(%%{init: {"a":"unterminated}}%%\nflowchart LR\n  A-->B\n)

        result = described_class.split(source)

        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end

      it "takes a body on the same line as the terminator" do
        result = described_class.split("%%{init: {}}%%flowchart LR\n  A-->B\n")

        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end

      it "refuses an empty directive" do
        result = described_class.split("%%{}%%\nflowchart LR\n  A-->B\n")

        expect(result[:directives]).to be_empty
      end

      it "refuses one holding only whitespace" do
        result = described_class.split("%%{   }%%\nflowchart LR\n  A-->B\n")

        expect(result[:directives]).to be_empty
      end

      # A headerless `%%{` is a comment line to mermaid, never a
      # directive, so its comment pass eats the whole LINE rather than
      # stopping at `}%%`. Stopping at the terminator handed the body
      # back intact and rendered two shapes mmdc refuses for all 23
      # types, sequenceDiagram included.
      it "eats the rest of a headerless directive's line" do
        result = described_class.split("%%{}%%flowchart LR\n  A-->B\n")

        expect(result[:body]).to eq("  A-->B\n")
      end

      it "strands a terminator that sits on a later line" do
        result = described_class.split("%%{\n}%%\nflowchart LR\n  A-->B\n")

        expect(result[:body]).to eq("}%%\nflowchart LR\n  A-->B\n")
      end

      # The consume has to reach the end of a file with no trailing
      # newline. If it only ever matched up to a `\n` the scan would take
      # nothing here, and the loop that calls it would spin forever on a
      # source someone typed. Timed, because a hang is not a failure.
      it "terminates on one that ends the file" do
        result = Timeout.timeout(2) { described_class.split("%%{}%%") }

        expect(result[:body]).to eq("")
        expect(result[:degenerate]).to eq([:directive])
      end

      # A `%%{` mermaid's directive scan will not take is a comment line,
      # terminator or no terminator. Waiting for a `}%%` that never comes
      # left the `%%{` in the body and killed a source mmdc renders.
      it "eats a headerless line that never closes" do
        result = described_class.split("%%{}\nsequenceDiagram\n  A->>B: m\n")

        expect(result[:body]).to eq("sequenceDiagram\n  A->>B: m\n")
        expect(result[:degenerate]).to eq([:directive])
      end

      it "resumes the scan after one" do
        result = described_class.split("%%{}\n%% note\nsequenceDiagram\n")

        expect(result[:body]).to eq("sequenceDiagram\n")
      end

      # The terminator is optional once a header word is there, and the
      # directive swallows what it matched. `%%{init: {}` takes the diagram
      # with it, which is why mmdc refuses this source.
      it "swallows the rest when a blob value never closes" do
        result = described_class.split("%%{init: {}\nflowchart LR\n  A-->B\n")

        expect(result[:body]).to eq("")
      end

      # A bare-word value ends the directive where the word ends, so it
      # neither swallows the diagram nor reaches forward for a `}%%`.
      it "ends a bare-word value at the word" do
        result = described_class.split("%%{init: x\nflowchart LR\n  A-->B\n")

        expect(result[:directives]).to eq(["%%{init: x"])
        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end

      it "does not let a bare-word value borrow a later terminator" do
        source = "%%{init: x\nsequenceDiagram\n  A->>B: m\n}%%\nflowchart LR\n"

        expect(described_class.split(source)[:body])
          .to start_with("sequenceDiagram")
      end

      it "still lets a blob value borrow one" do
        source = "%%{init: {}\nsequenceDiagram\n  A->>B: m\n}%%\nflowchart LR\n"

        expect(described_class.split(source)[:body]).to eq("flowchart LR\n")
      end

      it "still takes a directive that genuinely spans lines" do
        source = %(%%{init: {\n  "theme": "base"\n}}%%\nflowchart LR\n  A-->B\n)

        expect(described_class.split(source)[:body])
          .to eq("flowchart LR\n  A-->B\n")
      end
    end

    context "with indented fences" do
      it "accepts a matching indent and dedents the yaml" do
        # mmdc takes this. The 44 damaged corpus cases are the MISMATCHED
        # shape, not this one — checked: 44 unequal, 1 equal.
        result = described_class.split(
          "  ---\n  title: T\n  ---\n  flowchart LR\n  A --> B\n"
        )

        expect(result[:frontmatter]).to eq("title: T\n")
        expect(result[:body]).to eq("  flowchart LR\n  A --> B\n")
      end
    end

    context "with a quoted brace inside a directive" do
      it "does not close early or run to the end" do
        source = %(%%{init: {"a": "b}c"}}%%\nflowchart LR\n  A-->B\n)

        result = described_class.split(source)

        expect(result[:directives]).to eq([%(%%{init: {"a": "b}c"}}%%)])
        expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
      end
    end

    # Mermaid looks for frontmatter at the very start of the file and
    # nowhere else. A fence behind anything at all is not frontmatter to
    # it — the lines stay in the text and the diagram's own parser meets
    # them. Seventeen types stop there and six skip the lines, so the
    # split lifts the fence off the body, reads no title from it, and
    # marks it for `Engine` to judge.
    context "with a frontmatter fence behind another preamble item" do
      {
        "a comment" => "%% a\n",
        "a blank line" => "\n",
        "a directive" => "%%{init: {}}%%\n",
        "a byte order mark" => "\uFEFF"
      }.each do |label, before|
        it "strips it, reads no title and marks it behind #{label}" do
          source = "#{before}---\ntitle: T\n---\nflowchart LR\n  A-->B\n"

          result = described_class.split(source)

          expect(result[:frontmatter]).to be_nil
          expect(result[:body]).to eq("flowchart LR\n  A-->B\n")
          expect(result[:degenerate]).to include(:frontmatter)
        end
      end

      it "does not parse a block it would otherwise refuse" do
        # Never read, so `title: [` is not an error here. Pie is one of
        # the six that skip the lines, and mmdc draws the pie.
        source = %(%% a\n---\ntitle: [\n---\npie\n  "A" : 10\n)

        expect { Sirena::Engine.new.render(source) }.not_to raise_error
      end

      it "keeps scanning the preamble after it" do
        source = "%% a\n---\ntitle: T\n---\n%% b\nflowchart LR\n  A-->B\n"

        expect(described_class.split(source)[:body])
          .to eq("flowchart LR\n  A-->B\n")
      end

      it "still reads the first fence when a second follows" do
        source = "---\ntitle: T\n---\n---\ntitle: U\n---\nflowchart LR\n"

        result = described_class.split(source)

        expect(result[:frontmatter]).to eq("title: T\n")
        expect(result[:body]).to eq("flowchart LR\n")
        expect(result[:degenerate]).to include(:frontmatter)
      end

      it "leaves the mark off when the only fence starts the file" do
        result = described_class.split("---\ntitle: T\n---\nflowchart LR\n")

        expect(result[:degenerate]).to be_empty
      end
    end

    # Mermaid erases a bare `%%` and a headerless `%%{...}%%` whole, and
    # erasing one puts the fence behind it at the front of the file. There
    # mermaid stops on it — "Diagrams beginning with --- are not valid" —
    # for every type, the six that otherwise skip a late fence included.
    # Leaving the fence in the body is what stops it here: detection has
    # nothing left to match.
    context "with a frontmatter fence behind an item mermaid erases" do
      {
        "a bare comment" => "%%\n",
        "a headerless directive" => "%%{}%%\n",
        "a comment then a bare one" => "%% a\n%%\n",
        "a bare comment then a comment" => "%%\n%% a\n"
      }.each do |label, before|
        it "leaves the fence in the body behind #{label}" do
          source = %(#{before}---\ntitle: T\n---\npie\n  "A" : 10\n)

          result = described_class.split(source)

          expect(result[:frontmatter]).to be_nil
          expect(result[:body]).to start_with("---\ntitle: T\n---\n")
          expect(result[:degenerate]).not_to include(:frontmatter)
        end
      end

      it "refuses the diagram even for a type that skips a late fence" do
        # Pie is one of the six that skip a late fence, and it renders one
        # behind a real comment. Behind a bare `%%` mmdc exits nonzero.
        source = %(%%\n---\ntitle: T\n---\npie\n  "A" : 10\n)

        expect { Sirena::Engine.new.render(source) }.to raise_error(Sirena::Error)
      end
    end

    context "with a byte order mark" do
      # A BOM is a byte like any other to mermaid's frontmatter regex, so
      # it costs the title — but it is not part of the diagram either, and
      # leaving it in front of the keyword killed detection.
      it "takes it off the front of the body" do
        expect(described_class.split("\uFEFFflowchart LR\n  A-->B\n")[:body])
          .to eq("flowchart LR\n  A-->B\n")
      end

      it "takes it off in front of a comment" do
        expect(described_class.split("\uFEFF%% a\nflowchart LR\n")[:body])
          .to eq("flowchart LR\n")
      end
    end

    context "with an indented frontmatter closer" do
      # mmdc 11.12.0 rejects this and so must we. 44 corpus cases are damaged
      # in exactly this way, and accepting them would inflate the corpus
      # figure by 44 cases mermaid itself will not render.
      it "does not treat it as frontmatter" do
        source = "---\n  config:\n    theme: base\n  ---\n  flowchart LR\n"

        result = described_class.split(source)

        expect(result[:frontmatter]).to be_nil
        expect(result[:body]).to eq(source)
      end
    end
  end

  describe ".title" do
    it "reads the title out of a frontmatter block" do
      expect(described_class.title("title: My Chart")).to eq("My Chart")
    end

    it "returns nil when the block sets no title" do
      expect(described_class.title("config:\n  theme: base")).to be_nil
    end

    it "returns nil for an empty block" do
      expect(described_class.title("")).to be_nil
    end

    it "returns nil for a block holding only a comment" do
      # Psych.parse returns false here, not nil, so safe navigation did not
      # guard it and the engine raised.
      expect(described_class.title("# comment\n")).to be_nil
    end

    it "returns nil when the document is not a mapping" do
      expect(described_class.title("- a")).to be_nil
      expect(described_class.title("just a scalar")).to be_nil
    end

    it "raises on unparseable YAML rather than reporting no title" do
      # mmdc rejects `title: [`. Collapsing malformed frontmatter into
      # "absent title" meant sirena rendered it.
      expect { described_class.title("a: [unclosed") }
        .to raise_error(Sirena::Source::MalformedFrontmatter)
    end

    it "reads the scalar as written rather than coercing it" do
      # Loading the document turned a date into a Date. mermaid renders the
      # text, so the AST scalar is what we want.
      expect(described_class.title("title: 2026-08-19")).to eq("2026-08-19")
    end

    it "reads a title under a quoted key" do
      # `\"title\"` and `title` name the same JS property, which is the same
      # reason the two collide as duplicates.
      expect(described_class.title(%("title": T))).to eq("T")
    end

    describe "a tag on a value" do
      # mermaid hands the block to a YAML loader that throws on a tag it
      # cannot resolve, and mmdc exits nonzero when it does. Refusing every
      # tag was wrong in the other direction: `!!int 1` draws "1".
      {
        "title: !!int 1" => "1",
        "title: !!float 1.5" => "1.5",
        "title: !!float 1" => "1",
        "title: !!bool true" => "true",
        "title: !!str 0" => "0",
        "title: !!null ~" => nil,
        "title: !!int 0" => nil,
        "title: !!seq [a]" => "a",
        "title: !!map {a: 1}" => "[object Object]",
        # A radix prefix is an integer to the loader and to the plain
        # resolver, so `!!int 0x10` and a bare `0x10` both draw 16.
        "title: !!int 0x10" => "16",
        "title: 0x10" => "16"
      }.each do |yaml, drawn|
        it "resolves #{yaml.inspect} to #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end

      [
        "title: !!int nope", "title: !!int 1.5", "title: !!float nope",
        "title: !!bool nope", "title: !!null x", "title: !custom x",
        "title: !!seq x", "title: !!map x",
        "title: !!timestamp 2001-01-01", "title: !!binary aGk=",
        "title: !custom [a]", "title: !!seq {a: 1}", "title: !!map [a]",
        # `!!float` has a narrower idea of a number than the plain
        # resolver does. Both turn `0x10` into 16, but the tag refuses a
        # radix prefix outright and mmdc exits nonzero on it.
        "title: !!float 0x10", "title: !!float 0o7", "title: !!float 0b1",
        "title: !!float +0x1", "title: !!float -0o7"
      ].each do |yaml|
        it "refuses #{yaml.inspect}" do
          expect { described_class.title(yaml) }
            .to raise_error(Sirena::Source::MalformedFrontmatter)
        end
      end
    end

    # The loader refuses the whole document, not just the title, so a tag
    # it cannot resolve anywhere is a rejection. Only the title was being
    # checked, and `x: !!float nope` rendered here while mmdc exited
    # nonzero.
    describe "a tag elsewhere in the document" do
      [
        "x: !!float nope\ntitle: T",
        "x: !custom v\ntitle: T",
        "x:\n  y: !!int nope\ntitle: T",
        "x: [!!int nope]\ntitle: T"
      ].each do |yaml|
        it "refuses #{yaml.inspect} even though the title is fine" do
          expect { described_class.title(yaml) }
            .to raise_error(Sirena::Source::MalformedFrontmatter)
        end
      end

      it "leaves a tag it can resolve alone" do
        expect(described_class.title("x: !!int 1\ntitle: T")).to eq("T")
      end
    end

    describe "the title mermaid actually draws" do
      # mmdc draws a title only when the value is truthy AND its string is
      # not empty. A string whitelist of "null ~ false 0" got `0.0`, `0x0`
      # and `[]` wrong, because falsiness belongs to the value.
      {
        "title: 0" => nil, "title: 0.0" => nil, "title: 0x0" => nil,
        "title: -0" => nil, "title: +0" => nil, "title: 00" => nil,
        "title: false" => nil, "title: null" => nil, "title: ~" => nil,
        "title: .nan" => nil, "title: ''" => nil, "title:" => nil,
        "title: []" => nil, "title: [~]" => nil, "title: [[]]" => nil,
        "title: 1" => "1", "title: 1.5" => "1.5", "title: 1e3" => "1000",
        "title: .inf" => "Infinity", "title: -.inf" => "-Infinity",
        "title: True" => "true", "title: -0x1" => "-1",
        "title: 0b101" => "5", "title: 0o17" => "15",
        "title: 09" => "9", "title: 017" => "17", "title: 1_0" => "10",
        "title: 190:20" => "190:20",
        %(title: "0") => "0", %(title: "false") => "false",
        %(title: " ") => " "
      }.each do |yaml, drawn|
        it "draws #{drawn.inspect} for #{yaml.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end

      it "stringifies a mapping the way JS does" do
        expect(described_class.title("title: {a: 1}")).to eq("[object Object]")
      end
    end

    # A sequence is joined the way JS joins one, so a null element
    # contributes nothing rather than the word "null". This gave ",," .
    describe "a sequence title" do
      {
        "title: [a, b]" => "a,b",
        "title: [0, false, null]" => "0,false,",
        "title: [[a, b], c]" => "a,b,c",
        "title: [a, [b, [c]]]" => "a,b,c",
        "title: [{a: 1}]" => "[object Object]"
      }.each do |yaml, drawn|
        it "joins #{yaml.inspect} into #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end
    end

    describe "duplicate keys" do
      # mmdc refuses `x: 1` twice. Only top-level scalar keys were compared,
      # so a repeat nested in a mapping or spelled as a complex key sailed
      # through. Keys collide when they name the same JS property, which is
      # why a sequence key and the string spelling it are one key.
      [
        "title: One\ntitle: Two",
        "x: 1\nx: 2\ntitle: T",
        %("a": 1\na: 2\ntitle: T),
        "config:\n  a: 1\n  a: 2\ntitle: T",
        "a:\n  b:\n    c:\n      d: 1\n      d: 2\ntitle: T",
        "x: {a: 1, a: 2}\ntitle: T",
        "x: [{a: 1, a: 2}]\ntitle: T",
        "x:\n  - a: 1\n    a: 2\ntitle: T",
        "title: {a: 1, a: 2}",
        "? [a, b]\n: c\n? [a, b]\n: d\ntitle: T",
        %(? [a, b]\n: c\n"a,b": d\ntitle: T),
        "? {a: 1}\n: c\n? {b: 2}\n: d\ntitle: T",
        %(1: a\n"1": b\ntitle: T),
        %(true: a\n"true": b\ntitle: T),
        %(~: a\n"null": b\ntitle: T)
      ].each do |yaml|
        it "refuses #{yaml.inspect}" do
          expect { described_class.title(yaml) }
            .to raise_error(Sirena::Source::MalformedFrontmatter, /Duplicate/)
        end
      end

      it "reads a title alongside a complex key" do
        # `? [a, b]` has a Sequence for a key, and calling `value` on it
        # raised NoMethodError. mmdc renders this.
        expect(described_class.title("? [a, b]\n: c\ntitle: T")).to eq("T")
      end

      it "leaves two complex keys that differ alone" do
        expect(described_class.title("? [a, b]\n: c\n? [c, d]\n: d\ntitle: T"))
          .to eq("T")
      end

      it "leaves a repeated VALUE alone" do
        expect(described_class.title("a: 1\nb: 1\ntitle: T")).to eq("T")
      end

      it "does not call a merged key a duplicate" do
        # mmdc renders this: `<<` merges rather than colliding with `p`.
        yaml = "a: &x {p: 1}\nb:\n  <<: *x\n  p: 2\ntitle: T"

        expect(described_class.title(yaml)).to eq("T")
      end
    end

    describe "how a number prints" do
      # Every YAML number reaches JS as a double, and JS prints one in
      # plain decimal only while the point sits within 21 digits of the
      # front and 6 of the back. Ruby switches at 1e16 and keeps a bignum
      # exact that JS has already rounded.
      {
        "title: 1e21" => "1e+21",
        "title: 1e20" => "100000000000000000000",
        "title: 1e16" => "10000000000000000",
        "title: 1.5e21" => "1.5e+21",
        "title: -1e21" => "-1e+21",
        "title: 1e100" => "1e+100",
        "title: 1e-5" => "0.00001",
        "title: 1e-6" => "0.000001",
        "title: 1e-7" => "1e-7",
        "title: 1.5e-7" => "1.5e-7",
        "title: 9007199254740993" => "9007199254740992",
        "title: 18446744073709551615" => "18446744073709552000",
        "title: 123456789012345678901234" => "1.2345678901234569e+23"
      }.each do |yaml, drawn|
        it "prints #{yaml.inspect} as #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end
    end

    describe "a radix prefix" do
      # It takes only the digits its base allows. Accepting any hex digit
      # for every base raised ArgumentError out of Integer() on `0o9`,
      # which mmdc simply draws as text.
      {
        "title: 0o9" => "0o9", "title: 0b2" => "0b2", "title: 0o8" => "0o8",
        "title: 0x_" => "0x_", "title: 0o_" => "0o_", "title: 0xg" => "0xg",
        "title: 0b" => "0b", "title: 0_x1" => "0_x1",
        "title: 0x1_2" => "18", "title: +0x1" => "1", "title: -0o7" => "-7"
      }.each do |yaml, drawn|
        it "reads #{yaml.inspect} as #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end
    end

    describe "underscores in a number" do
      # They group digits, and a number cannot end on one — which is the
      # whole difference between `1_0` and `1_`.
      {
        "title: 1_" => "1_", "title: 1.5_" => "1.5_", "title: .5_" => ".5_",
        "title: 0b1_" => "0b1_", "title: _1" => "_1", "title: _" => "_",
        "title: 1__0" => "10", "title: 1_.5" => "1.5",
        "title: 1._5" => "1.5", "title: 1e_3" => "1e_3",
        "title: 1_e3" => "1000"
      }.each do |yaml, drawn|
        it "groups #{yaml.inspect} into #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end
    end

    describe "a sign in front of a number" do
      # In front of a bare fraction it is not a number to mermaid, though
      # in front of digits it is.
      {
        "title: .5" => "0.5", "title: -.5" => "-.5", "title: +.5" => "+.5",
        "title: +1.5" => "1.5", "title: -1.5" => "-1.5",
        "title: +1" => "1", "title: 1." => "1", "title: 1.2.3" => "1.2.3",
        "title: 5:30" => "5:30"
      }.each do |yaml, drawn|
        it "signs #{yaml.inspect} into #{drawn.inspect}" do
          expect(described_class.title(yaml)).to eq(drawn)
        end
      end
    end

    describe "more than one YAML document" do
      # Psych.parse hands back the FIRST document and says nothing about
      # the rest, so this read as a plain title while mmdc exited nonzero.
      it "is refused when a document end marker splits the block" do
        expect { described_class.title("title: T\n...\nx: 1") }
          .to raise_error(Sirena::Source::MalformedFrontmatter)
      end

      it "is refused when a second document starts" do
        expect { described_class.title("title: T\n--- \nx: 1") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /one YAML/)
      end
    end

    describe "a block nested too deeply to walk" do
      # Recursing to Ruby's own limit raised SystemStackError, which is
      # not a StandardError: it escaped the engine's rescue and crashed
      # the caller. The stack this runs on belongs to that caller, and a
      # Fiber's is the smallest one going, so the examples below run
      # there — a bound that only holds on the main thread is not a bound.
      def deep_nest(levels)
        "title: #{'[' * levels}x#{']' * levels}"
      end

      def alias_chain(links)
        lines = ["k0: &a0 [x]"]
        (1..links).each { |i| lines << "k#{i}: &a#{i} [*a#{i - 1}]" }
        (lines << "title: *a#{links}").join("\n")
      end

      def in_a_fiber(yaml)
        Fiber.new do
          described_class.title(yaml)
        rescue Sirena::Source::MalformedFrontmatter
          :refused
        end.resume
      end

      it "draws two hundred levels" do
        expect(described_class.title(deep_nest(200))).to eq("x")
      end

      it "refuses ten thousand rather than exhausting the stack" do
        expect { described_class.title(deep_nest(10_000)) }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /deeply/)
      end

      it "refuses a long alias chain the same way" do
        # Following an alias recurses twice per link, so a chain is its own
        # way to the same crash. One thousand links clears the depth bound
        # while leaving this example's work inside the separate value budget.
        expect { described_class.title(alias_chain(1_000)) }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /deeply/)
      end

      it "refuses rather than crashing on a small stack" do
        # This is the example the old bound of 1,024 failed: a Fiber gave
        # out around 500 levels, so the guard never got to fire.
        expect(in_a_fiber(deep_nest(10_000))).to eq(:refused)
        expect(in_a_fiber(alias_chain(1_000))).to eq(:refused)
      end

      it "still walks what a person would write, on a small stack" do
        expect(in_a_fiber(deep_nest(200))).to eq("x")
      end
    end

    describe "anchors and aliases" do
      it "reads a title from a document that uses an alias elsewhere" do
        expect(described_class.title("x: &a 1\ny: *a\ntitle: T")).to eq("T")
      end

      it "resolves an alias that IS the title" do
        expect(described_class.title("a: &x Hello\ntitle: *x")).to eq("Hello")
      end

      it "resolves an alias to a number the way JS prints it" do
        expect(described_class.title("a: &x 1\ntitle: *x")).to eq("1")
      end

      it "does not follow an anchor that points at itself" do
        # `a: &x [*x]` recursed until the stack gave out — a crash in the
        # caller, from a diagram someone typed. mmdc draws that source with
        # no title at all.
        expect(described_class.title("a: &x [*x]\ntitle: *x")).to be_nil
        expect(described_class.title("a: &x [*x]")).to be_nil
      end

      it "refuses an alias with no anchor" do
        # This example asserted nil and was wrong: mmdc exits nonzero on an
        # undefined alias, so reporting "no title" rendered a source the
        # oracle refuses.
        expect { described_class.title("title: *missing") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /anchor/)
      end

      it "refuses an alias that runs ahead of its anchor" do
        # The loader resolves in document order, so an anchor further down
        # the block is not yet defined. mmdc exits nonzero.
        expect { described_class.title("a: *x\nb: &x 1\ntitle: T") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /anchor/)
      end

      it "binds an alias where it sits, not at the end of the block" do
        # The anchors were all collected before the title was read, so a
        # rebinding further down reached back and changed it. mmdc draws
        # "1" here and "2" when the title comes last.
        expect(described_class.title("a: &x 1\ntitle: *x\nb: &x 2"))
          .to eq("1")
      end

      it "takes the later of two anchors sharing a name" do
        # Last one wins, the way YAML resolves them: mmdc draws "2".
        expect(described_class.title("a: &x 1\nb: &x 2\ntitle: *x")).to eq("2")
      end

      it "keeps a nested alias bound to the value it was built from" do
        # The list under `&y` is built where it sits, holding "one". A
        # later `&x` cannot reach back into it, and resolving the title's
        # alias at the end let it: mmdc draws "one", we drew "two".
        expect(described_class.title("a: &x one\nb: &y [*x]\nc: &x two\n" \
                                     "title: *y")).to eq("one")
      end

      it "keeps the binding through two levels of nesting" do
        expect(described_class.title("a: &x one\nb: &y [*x]\nc: &z [*y]\n" \
                                     "d: &x two\ntitle: *z")).to eq("one")
      end

      it "compares keys by what a nested alias held when it was built" do
        # Two keys collide only when they spell the same name. `*y` spells
        # "one" here, so `[two]` is a different key and mmdc draws "T".
        expect(described_class.title("a: &x one\nb: &y [*x]\nc: &x two\n" \
                                     "? *y\n: 1\n? [two]\n: 2\n" \
                                     "title: T")).to eq("T")
      end

      it "refuses two keys that a nested alias makes identical" do
        # Same block with `[one]` for the second key. mmdc exits nonzero.
        expect do
          described_class.title("a: &x one\nb: &y [*x]\nc: &x two\n" \
                                "? *y\n: 1\n? [one]\n: 2\ntitle: T")
        end.to raise_error(Sirena::Source::MalformedFrontmatter, /Duplicate/)
      end

      it "refuses a sequence nested inside a mapping key" do
        # The loader stops on this shape wherever it sits — "nested
        # arrays are not supported inside keys". mmdc exits nonzero and
        # we rendered a title.
        expect { described_class.title("? [[a]]\n: x\ntitle: T") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /key/)
      end

      it "refuses one reached through an alias" do
        expect { described_class.title("a: &y [[q]]\n? *y\n: 1\ntitle: T") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /key/)
      end

      it "refuses a key holding a list that holds itself" do
        # `[*x]` is a list whose one element is the list itself, and the
        # loader refuses it even though its string is empty.
        expect { described_class.title("a: &x [*x]\n? [*x]\n: 1\ntitle: T") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /key/)
      end

      it "refuses one nested deeper in the document" do
        expect { described_class.title("x:\n  ? [[a]]\n  : 1\ntitle: T") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /key/)
      end

      it "takes a key holding a mapping, a null or nothing" do
        # Only a sequence inside the key is refused. mmdc draws "T" for
        # all three.
        expect(described_class.title("? [{a: 1}]\n: x\ntitle: T")).to eq("T")
        expect(described_class.title("? [~]\n: x\ntitle: T")).to eq("T")
        expect(described_class.title("? []\n: x\ntitle: T")).to eq("T")
      end

      it "takes a sequence nested anywhere but a key" do
        expect(described_class.title("v: [[a]]\ntitle: T")).to eq("T")
        expect(described_class.title("? {a: [b]}\n: x\ntitle: T")).to eq("T")
      end

      it "refuses an alias bomb reached through the title" do
        bomb = "a: &a [x,x,x,x,x,x,x,x,x]\n" \
               "b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]\n" \
               "c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]\n" \
               "d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]\n" \
               "e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d]\n" \
               "title: *e\n"

        expect { described_class.title(bomb) }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /many values/)
      end

      it "allows exactly the work budget and refuses the next value" do
        # The title key and sequence use two visits, leaving 9,998 scalar
        # visits inside the 10,000-value budget.
        values = Array.new(9_998, "x").join(",")

        expect(described_class.title("title: [#{values}]"))
          .to eq(values)
        expect { described_class.title("title: [#{values},x]") }
          .to raise_error(Sirena::Source::MalformedFrontmatter, /many values/)
      end
    end
  end
end
