# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/user_journey'

RSpec.describe Sirena::Parser::UserJourneyParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple user journey with one task' do
      source = <<~MERMAID
        journey
          title My Journey
          section Shopping
            Browse products: 5: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::UserJourney)
      expect(diagram.title).to eq('My Journey')
      expect(diagram.sections.length).to eq(1)
      expect(diagram.sections.first.name).to eq('Shopping')
      expect(diagram.sections.first.tasks.length).to eq(1)
      expect(diagram.sections.first.tasks.first.name).to eq('Browse products')
      expect(diagram.sections.first.tasks.first.score).to eq(5)
      expect(diagram.sections.first.tasks.first.actors).to eq(['Customer'])
    end

    it 'parses user journey without title' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.title).to be_nil
      expect(diagram.sections.length).to eq(1)
    end

    it 'parses multiple sections' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
          section Checkout
            Pay: 3: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(2)
      expect(diagram.sections[0].name).to eq('Shopping')
      expect(diagram.sections[1].name).to eq('Checkout')
    end

    it 'parses multiple tasks in a section' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
            Select: 4: Customer
            Add to cart: 4: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.sections.first.tasks.length).to eq(3)
      expect(diagram.sections.first.tasks[0].name).to eq('Browse')
      expect(diagram.sections.first.tasks[1].name).to eq('Select')
      expect(diagram.sections.first.tasks[2].name).to eq('Add to cart')
    end

    it 'parses tasks with multiple actors' do
      source = <<~MERMAID
        journey
          section Shopping
            Checkout: 3: Customer, Staff
      MERMAID

      diagram = parser.parse(source)

      task = diagram.sections.first.tasks.first
      expect(task.actors).to eq(%w[Customer Staff])
    end

    it 'parses tasks with different scores' do
      source = <<~MERMAID
        journey
          section Test
            Task1: 1: Actor
            Task2: 2: Actor
            Task3: 3: Actor
            Task4: 4: Actor
            Task5: 5: Actor
      MERMAID

      diagram = parser.parse(source)

      tasks = diagram.sections.first.tasks
      expect(tasks[0].score).to eq(1)
      expect(tasks[1].score).to eq(2)
      expect(tasks[2].score).to eq(3)
      expect(tasks[3].score).to eq(4)
      expect(tasks[4].score).to eq(5)
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid'

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end

    it 'raises ParseError for score out of range' do
      source = <<~MERMAID
        journey
          section Test
            Task: 6: Actor
      MERMAID

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
        /Score must be between 1 and 5/
      )
    end

    # ---------------------------------------------------------------------
    # accTitle / accDescr
    #
    # "The oracle" below means mermaid 11.16.1 driven by mermaid-cli 11.12.0.
    # `mmdc --version` reports the CLI; the library that decides these
    # verdicts is the mermaid in the CLI's node_modules, and the two carry
    # different version numbers. To re-run any verdict quoted here, put the
    # source in a file and render it — exit 0 is a render, non-zero a refusal:
    #
    #   printf 'journey\naccDescr {Desc}After: 3: Me\n' > /tmp/case.mmd
    #   mmdc -i /tmp/case.mmd -o /tmp/case.svg; echo "exit $?"
    #
    # When measured, mmdc was at
    # ~/.nvm/versions/node/v22.23.1/bin/mmdc.
    # ---------------------------------------------------------------------

    # The extracted fixture names mislead twice over: the files named
    # "multiline" hold a single-line accTitle, and those named
    # "title_definition" hold an accTitle rather than a title, so they expect
    # a nil title. The seven files carrying a directive collapse to these
    # three sources — 009_..._title_8 and 013_..._title_12 duplicate the
    # first, 008_..._accdescr__7 the second, 009_..._multiline_..._8 the
    # third. Only the second contains an accDescr.
    describe 'an accessibility directive from the corpus' do
      cases = {
        '004_parser_should_handle_a_title_definition_3.mmd' => nil,
        '004_parser_should_handle_an_accessibility_description_accdescr__3.mmd' =>
          'Adding journey diagram functionality to mermaid',
        '005_parser_should_handle_an_accessibility_multiline_description_accdescr__4.mmd' =>
          'Adding journey diagram functionality to mermaid'
      }

      cases.each do |filename, expected_title|
        it "parses #{filename}" do
          source = File.read("spec/mermaid/user_journey/#{filename}")

          diagram = parser.parse(source)

          expect(diagram.title).to eq(expected_title)
          expect(diagram.sections.map(&:name)).to eq(['Order from website'])
        end
      end
    end

    # Every corpus fixture above ends at its `section` line, so a directive
    # that leaked into the model could not reach a task assertion: the
    # builder only reads a task once a section is open. These open the
    # section and a task FIRST.
    #
    # All three of title, section names and tasks are asserted because a leak
    # need not disturb the tasks at all — capturing the braced body as
    # `:title` puts the directive text in `diagram.title` and leaves both
    # tasks intact, which a task-only assertion cannot see.
    #
    # The oracle renders both tasks in every source here.
    describe 'a directive among the tasks' do
      {
        'accTitle' => 'accTitle: The accessible title',
        'accDescr' => 'accDescr: A user journey for family shopping',
        'accTitle with a spaced colon' => 'accTitle : The accessible title',
        'accDescr with a spaced colon' => 'accDescr : A user journey',
        'an indented accTitle' => '    accTitle: The accessible title',
        'a braced accDescr block' => "accDescr {\n  a multi line\n  description\n}",
        'a braced accDescr block on one line' => 'accDescr {Desc}',
        'a braced accDescr block with no gap' => 'accDescr{Desc}',
        'an accTitle with no gap' => 'accTitle:Tight'
      }.each do |label, directive|
        it "discards #{label} and leaves the rest of the diagram alone" do
          source = "journey\ntitle Real title\nsection Order from website\n  " \
                   "Sit down: 5: Me\n#{directive}\n  Check mail: 3: Me\n"

          diagram = parser.parse(source)

          expect(diagram.title).to eq('Real title')
          expect(diagram.sections.map(&:name)).to eq(['Order from website'])
          expect(diagram.sections.first.tasks.map { |t| [t.name, t.score] })
            .to eq([['Sit down', 5], ['Check mail', 3]])
        end
      end
    end

    describe 'the edges of the accessibility rules' do
      it 'takes the keyword whole rather than as a prefix' do
        # The oracle titles the first source `3: Me` and draws no task for
        # it; it renders the second as an ordinary task, since `accTitleNode`
        # only starts with the same letters.
        directive = "journey\nsection Order from website\n  accTitle: 3: Me\n"
        prefixed = "journey\nsection Order from website\n  accTitleNode: 3: Me\n"

        expect(parser.parse(directive).sections.first.tasks.map(&:name)).to eq([])
        expect(parser.parse(prefixed).sections.first.tasks.map(&:name))
          .to eq(['accTitleNode'])
      end

      it 'reads a task-shaped directive as a directive' do
        # The shape that forced the colon gap: with the colon required to
        # touch the keyword, this fell through to the task rule and became a
        # task named accDescr scoring 3. The oracle reads it as a description
        # and draws no task.
        source = "journey\nsection Order from website\n  accDescr : 3: Me\n"

        expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['Order from website', []]])
      end

      it 'requires the block to close, as mermaid does' do
        # The oracle renders the closed source and refuses the unclosed one.
        # Why the brace is required is on the rule itself.
        closed = "journey\naccDescr {desc}\nsection Order from website\n  " \
                 "Sit down: 5: Me\n"
        unclosed = "journey\naccDescr {unterminated\nsection Order from website\n  " \
                   "Sit down: 5: Me\n"

        expect(parser.parse(closed).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['Order from website', ['Sit down']]])
        expect { parser.parse(unclosed) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'refuses a task-shaped opener whose block never closes' do
        # `accDescr {x: 3: Me` is both a block opener and a well-formed task
        # line, so it used to fall through to the task rule and succeed. That
        # disagreed with the oracle, which refuses the source, and it made
        # the parser quadratic: the block rule failed only after scanning to
        # the end of the source, and every later line paid for its own scan.
        # 4000 such lines took 188s and 1 GB of RSS.
        #
        # This example is what kills that regression. Restoring the
        # fallthrough does not merely slow the parse down, it changes the
        # answer: the source becomes a diagram with no sections at all.
        source = "journey\naccDescr {x: 3: Me\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'refuses an opener whose only closing brace sits in a comment' do
        # The comment rule consumes `%% }` whole, so that brace is not a
        # delimiter and the block never closes. The oracle refuses this
        # source too. It is the shape the check above cannot reach, because
        # here a `}` really is present in the source.
        source = "journey\naccDescr {a\nT: 3: Me\n%% }\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'opens a comment only at the start of a line' do
        # A `%%` in the middle of a line is ordinary text, so the `}` after it
        # closes the block and the section and task that follow are read
        # normally. The oracle agrees, giving this source the description
        # `text%%`. Unanchoring the comment rule swallows `%% }` instead, the
        # block never closes, and the whole source is refused.
        source = "journey\naccDescr {text%% }\nsection S\nT: 1: M\n"

        expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['S', ['T']]])
      end

      it 'ends the block at the brace and reads what follows it' do
        # A DIVERGENCE NOW CLOSED. The oracle renders this source with the
        # description `Desc`, the section `S` and one task `After` — the
        # exact sections and tasks asserted here.
        #
        # Requiring a line end after the brace instead read the whole of
        # `accDescr {Desc}After` as one task name, and that cost more than
        # accuracy: the block rule failed only AFTER scanning for its `}`,
        # so every following line paid for its own scan. 1000 such lines
        # took 9.75s; they take 0.82s now.
        source = "journey\nsection S\naccDescr{Desc}After: 3: Me\n"

        expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map { |t| [t.name, t.score] }] })
          .to eq([['S', [['After', 3]]]])
      end

      it 'raises ParseError on a source valid in a non-UTF-8 encoding' do
        # The accessibility rules are the only regexps in this grammar with a
        # fixed encoding — a `\uXXXX` escape sets one even though every
        # character in the set is ASCII — so this 18-byte ISO-8859-1 source
        # reached one and Parslet let Encoding::CompatibilityError out.
        # Parser::Base#parse documents ParseError, and ParseError is what
        # this source produced before the braced form existed.
        source = +"journey\naccDescr{\x9F"
        source.force_encoding(Encoding::ISO_8859_1)
        expect(source).to be_valid_encoding
        expect(source.ascii_only?).to be(false)

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'ends the directive text at the newline' do
        # An empty `accTitle:` is consumed and the next line keeps its own
        # meaning. mermaid's whitespace AFTER the delimiter crosses newlines
        # instead, so the oracle titles the first source
        # `section Order from website` and the second `Big decisions` — a
        # divergence this PR leaves open. Sirena's own gantt and pie parsers
        # reject the second as well; its timeline parser takes an empty title
        # and reads `Big decisions` as content. Closing it needs flowchart's
        # `acc_gap` rule, which skips comments and blank lines after the
        # delimiter, and that also changes what a bare `accTitle:` does to
        # the line after it.
        empty = "journey\naccTitle:\nsection Order from website\n  " \
                "Sit down: 5: Me\n"
        next_line = "journey\naccTitle:\nBig decisions\n" \
                    "section Order from website\n  Sit down: 5: Me\n"

        expect(parser.parse(empty).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['Order from website', ['Sit down']]])
        expect { parser.parse(next_line) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end
    end

    describe 'a comment or a directive inside the block' do
      # Mermaid deletes directive lines and then comment lines before it
      # parses, in two separate passes, so neither can close an accDescr
      # block. But `%%{` opens a DIRECTIVE where `%%` alone opens a COMMENT,
      # and one rule for both disagreed with the oracle in BOTH directions:
      # it accepted `%%{x}`, which the oracle refuses, and refused
      # `%%{init: {"theme":"dark"}}%%`, which the oracle renders.
      #
      # `Swallowed` is inside the block in every source below and so is never
      # a task. `Before` and `After` sit outside it and must both survive.
      {
        'a comment whose text merely starts with a brace' => '%% {x}',
        'a closed init directive' => '%%{init: {"theme":"dark"}}%%',
        'plain text' => 'plain text'
      }.each do |label, directive|
        it "keeps the tasks outside a block holding #{label}" do
          source = "journey\nsection S\nBefore: 5: You\naccDescr {desc\n" \
                   "#{directive}\nSwallowed: 1: Me\n}\nAfter: 4: Us\n"

          expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
            .to eq([['S', %w[Before After]]])
        end
      end

      # Both leave the block unclosed, by different routes. `%%{x}` is a
      # directive, so it is not a comment and its `}` is not swallowed; the
      # oracle refuses it. `%%{init: {...}}` has no closing `}%%`, so this
      # grammar drops it to the character branch where the `}` inside the
      # JSON closes the block early and the rest of the source no longer
      # parses — the oracle refuses it too, but because its own directive
      # pattern runs to the end of the source and leaves `accDescr {` open.
      # Same verdict, different mechanism.
      {
        'a bare braced directive' => '%%{x}',
        'an init directive with no closing tail' => '%%{init: {"theme":"dark"}}'
      }.each do |label, directive|
        it "refuses a block holding #{label}" do
          source = "journey\nsection S\nBefore: 5: You\naccDescr {desc\n" \
                   "#{directive}\nSwallowed: 1: Me\n}\nAfter: 4: Us\n"

          expect { parser.parse(source) }
            .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        end
      end

      it 'reads a mid-line directive as text rather than as a directive' do
        # A DIVERGENCE, pinned rather than endorsed. Mermaid's directive
        # strip is NOT anchored to a line start, so it deletes `%%{x}%%` from
        # the middle of a line; this grammar anchors both of its strips and
        # so leaves it as text. In `directive` the `}` inside `{x}` therefore
        # ends the block, `%%B` is left as an ordinary comment line, and the
        # source parses — where the oracle strips the directive, never closes
        # `accDescr {`, and REFUSES it.
        #
        # `comment` is the control that places the divergence on the
        # directive rather than on mid-line `%%` in general: with a plain
        # comment both tools refuse the source.
        #
        # The anchor is kept because it matches the comment rule beside it
        # and flowchart's `metadata_comment_line`, and because no corpus case
        # puts a directive mid-line. Unanchoring it changes what a directive
        # IS, which wants its own oracle round rather than arriving as a side
        # effect of this one — on the evidence so far it would move TOWARD
        # the oracle on every shape measured.
        directive = "journey\naccDescr {A%%{x}%%B\nsection S\nT: 1: M\n"
        comment = "journey\naccDescr {A%% x}B\nsection S\nT: 1: M\n"

        expect(parser.parse(directive).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['S', ['T']]])
        expect { parser.parse(comment) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'does not read a directive split across two lines' do
        # A DIVERGENCE, pinned. The oracle strips
        # `%%{init: {` / `"theme":"dark"}}%%` across the line break and
        # renders with the description `a\nb` — the same answer it gives the
        # one-line spelling. Here the directive body stops at the line end,
        # so the `}` inside the JSON closes the block, `}%%` is left stranded
        # after it and the source is refused.
        #
        # The bound is deliberate and costs nothing that existed before:
        # `origin/main` and the parser before this change both refuse this
        # source too. Without it every `%%{` inside a block scanned to the
        # end of the source hunting for `}%%`, and a block of them was
        # quadratic.
        source = "journey\naccDescr {a\n%%{init: {\n\"theme\":\"dark\"}}%%\nb}\n" \
                 "section S\nT: 1: M\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'treats a directive with no closing tail as ordinary text' do
        # The directive rule requires its `}%%`, so `%%{x` here is text: the
        # `}` after `b` closes the block and the section and task that follow
        # are read normally.
        #
        # Making the tail optional would be closer to mermaid's own pattern,
        # which runs an unterminated directive to the end of the source — but
        # it is further from the oracle's ANSWER. Mermaid eats `section S`
        # and the task along with the directive and still renders, with the
        # description `a`; making the tail optional here leaves `accDescr {`
        # open instead and refuses a source the oracle accepts.
        source = "journey\naccDescr {a\n%%{x\nb}\nsection S\nT: 1: M\n"

        expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['S', ['T']]])
      end

      it 'does not let a brace inside a comment close the block' do
        # Both the oracle and the parser before this change refuse the first
        # source. Until the block body consumed comment lines whole, it
        # parsed here as a diagram with `Swallowed` silently gone — accepted
        # where the oracle rejects, and quietly short a task. The oracle
        # renders the second source, where a real brace follows the commented
        # one.
        commented_close = "journey\nsection S\nBefore: 5: You\n" \
                          "accDescr {unterminated\nSwallowed: 1: Me\n%% }\n" \
                          "After: 4: Us\n"
        real_close = "journey\naccDescr {\ndescription\n%% }\n" \
                     "still description\n}\nsection S\nTask: 3: Me\n"

        expect { parser.parse(commented_close) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        expect(parser.parse(real_close).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['S', ['Task']]])
      end

      it 'opens a comment on any of the four line terminators' do
        # The oracle refuses each source: a carriage return, U+2028 or U+2029
        # opens the comment just as a newline does, and missing any one of
        # them let the `}` in `%% }` close the block and dropped `Swallowed`
        # without a word. Built from codepoints so no editor can normalise
        # one of the three into another.
        separators = [0x0D, 0x2028, 0x2029].map { |c| c.chr(Encoding::UTF_8) }
        expect(separators.uniq.length).to eq(3)

        separators.each do |sep|
          source = "journey\nsection S\nBefore: 5: You\naccDescr {unterminated\n" \
                   "Swallowed: 1: Me#{sep}%% }"

          expect { parser.parse(source) }
            .to raise_error(Sirena::Parser::ParseError, /Parse error/),
                "U+#{format('%04X', sep.ord)} should open a comment"
        end
      end

      it 'accepts every character of mermaid whitespace as a comment indent' do
        # The indent is matched with mermaid's whitespace set rather than
        # ASCII, because an indent this misses leaves the `}` in `%% }`
        # closing the block and a task disappears in silence — the oracle
        # rejects each of these sources. Only the no-break space was
        # exercised before, so a set narrowed to ASCII passed the suite.
        #
        # U+2028 and U+2029 are absent on purpose: `acc_nl` claims both, and
        # sharing them made a valid document quadratic. A run of them still
        # opens a comment, which the terminator example above covers.
        indents = [0x09, 0x0B, 0x0C, 0x20, 0x00A0, 0x1680, *0x2000..0x200A,
                   0x202F, 0x205F, 0x3000, 0xFEFF].map { |c| c.chr(Encoding::UTF_8) }
        expect(indents.uniq.length).to eq(indents.length)

        indents.each do |ws|
          source = "journey\nsection S\nBefore: 5: You\naccDescr {unterminated\n" \
                   "Swallowed: 1: Me\n#{ws}%% }\nAfter: 4: Us\n"

          expect { parser.parse(source) }
            .to raise_error(Sirena::Parser::ParseError, /Parse error/),
                "U+#{format('%04X', ws.ord)} should indent a comment"
        end
      end
    end

    describe 'the cost of a large source' do
      # These examples are clock-based, which is why each is written against
      # a control rather than a bare stopwatch wherever it can be. They exist
      # because the defects they pin are invisible to every other assertion
      # in this file: two of the three do not change a single parse result,
      # only how long one takes.

      it 'keeps every alternative in the block body line-bounded' do
        # THE INVARIANT. `acc_block_body` runs its alternation at every
        # position in the block, so an alternative whose own repeat can reach
        # the end of the source makes the whole parse quadratic in the length
        # of the block. That has happened twice in this grammar — first in
        # the block body itself, then in the directive rule added to repair
        # it — so it is measured here rather than remembered.
        #
        # Each alternative is driven with 800 lines of its own trigger and
        # compared against plain content, which is the single-character
        # branch and linear by construction. Measured: the comment rule runs
        # at about 1x the control and the directive rule at about 2.6x,
        # against 26x for that same rule with its body unbounded.
        #
        # ADD A ROW when you add an alternative to `acc_block_comment`. One
        # carrying this defect then fails on arrival instead of shipping.
        block = lambda do |line|
          "journey\naccDescr {d\n#{"#{line}\n" * 800}}\nsection S\nT: 1: M\n"
        end
        timed = lambda do |source|
          parser.parse(source)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          parser.parse(source)
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end

        control = timed.call(block.call('x'))

        { 'acc_comment_line' => '%% x', 'acc_directive' => '%%{x' }.each do |rule, line|
          source = block.call(line)

          expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
            .to eq([['S', ['T']]])
          expect(timed.call(source))
            .to be < control * 8, "#{rule} is not line-bounded"
        end
      end

      it 'refuses a long unclosed block without rescanning it per line' do
        # Before the block opener was refused outright, each of these lines
        # succeeded as a task and each scanned to the end of the source
        # first: 2000 lines took 20.0s against 1.0s now, and the gap widens
        # with the line count. The bound is loose enough for a slow machine
        # and still an order of magnitude under the old cost.
        source = "journey\n#{"accDescr {x: 3: Me\n" * 2000}"
        expect(source.bytesize).to be > 30_000

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        expect(elapsed).to be < 10
      end

      it 'parses a long run of U+2028 inside a block in linear time' do
        # U+2028 and U+2029 were in both `acc_nl` and the comment indent set.
        # At every one of them the comment rule opened, the indent repeat ate
        # the whole remaining run, the `%%` failed and all of it backtracked
        # to consume one character. Both sources below parse identically, so
        # only the clock can see the difference: the shared set took 6.2s
        # against 0.09s here, a ratio of 103 where this asserts 15.
        #
        # The no-break space is the control. It is in the indent set and NOT
        # in `acc_nl`, so it cannot open a comment, which is the one property
        # that separates the two runs. Measuring against it rather than
        # against a fixed number of seconds keeps the example honest on a
        # machine of any speed.
        terminator = 0x2028.chr(Encoding::UTF_8)
        control = 0x00A0.chr(Encoding::UTF_8)
        expect(terminator).not_to eq(control)

        sources = [terminator, control].map do |sep|
          "journey\naccDescr {#{sep * 4000}}\nsection S\nT: 3: Me\n"
        end
        expect(sources.first).not_to eq(sources.last)

        results = sources.map do |source|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          parsed = parser.parse(source)
          [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
           parsed.sections.map { |s| [s.name, s.tasks.map(&:name)] }]
        end

        expect(results.map(&:last)).to eq([[['S', ['T']]], [['S', ['T']]]])
        expect(results.first.first).to be < results.last.first * 15
      end
    end
  end
end
