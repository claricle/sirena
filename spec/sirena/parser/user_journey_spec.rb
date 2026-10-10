# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/user_journey"

module UserJourneySpecHelpers
  def section_names_and_tasks(source)
    parser.parse(source).sections.map do |section|
      [section.name, section.tasks.map(&:name)]
    end
  end

  def scored_section_names_and_tasks(source)
    parser.parse(source).sections.map do |section|
      [section.name, section.tasks.map { |task| [task.name, task.score] }]
    end
  end

  def journey_shape(source)
    diagram = parser.parse(source)
    sections = diagram.sections.map do |section|
      tasks = section.tasks.map { |task| [task.name, task.score] }
      [section.name, tasks]
    end
    [diagram.title, sections]
  end

  def expect_parse_error(
    source,
    error = Sirena::Parser::ParseError,
    message = nil,
    failure_message: nil
  )
    matcher = message ? raise_error(error, message) : raise_error(error)
    expect { parser.parse(source) }.to matcher, failure_message
  end

  def expect_score_error(source)
    expect_parse_error(
      source,
      Sirena::Parser::ScoreError,
      /Score must be between 1 and 5/,
    )
  end

  def expect_section_tasks(source, section, tasks)
    expect(section_names_and_tasks(source)).to eq([[section, tasks]])
  end

  def expect_directive_journey(source)
    expected = ["Real title", [["Order from website", [
      ["Sit down", 5], ["Check mail", 3]
    ]]]]
    expect(journey_shape(source)).to eq(expected)
  end

  def expect_invalid_byte_parse_error(source)
    expect_encoded_parse_error(
      source,
      valid: true,
      message: /invalid byte sequence/,
    )
  end

  def expect_task_closed_and_unclosed(closed, unclosed, task)
    expect_closed_and_unclosed(closed, unclosed, [["S", [task]]])
  end

  def expect_comment_brace_behavior
    commented_close = "journey\nsection S\nBefore: 5: You\n" \
                      "accDescr {unterminated\nSwallowed: 1: Me\n%% }\n" \
                      "After: 4: Us\n"
    real_close = "journey\naccDescr {\ndescription\n%% }\n" \
                 "still description\n}\nsection S\nTask: 3: Me\n"
    expect_task_closed_and_unclosed(real_close, commented_close, "Task")
  end

  def expect_closed_and_unclosed(closed, unclosed, expected)
    expect(section_names_and_tasks(closed)).to eq(expected)
    expect_parse_error(unclosed, Sirena::Parser::ParseError, /Parse error/)
  end

  def expect_encoded_parse_error(source, valid:, ascii_only: nil, message: nil)
    expected_encoding = [valid, ascii_only].compact
    actual_encoding = [source.valid_encoding?, source.ascii_only?]
      .first(expected_encoding.length)
    expect(actual_encoding).to eq(expected_encoding)
    expect_parse_error(source, Sirena::Parser::ParseError, message)
  end

  def expect_comment_openers(codepoints)
    separators = codepoints.map { |codepoint| codepoint.chr(Encoding::UTF_8) }
    expect(separators.uniq.length).to eq(3)

    separators.each do |separator|
      source = "journey\nsection S\nBefore: 5: You\n" \
               "accDescr {unterminated\nSwallowed: 1: Me#{separator}%% }"
      failure_message = "U+#{format('%04X', separator.ord)} should " \
                        "open a comment"
      expect_parse_error(
        source,
        Sirena::Parser::ParseError,
        /Parse error/,
        failure_message: failure_message,
      )
    end
  end

  def expect_comment_indents(codepoints)
    indents = codepoints.map { |codepoint| codepoint.chr(Encoding::UTF_8) }
    expect(indents.uniq.length).to eq(indents.length)

    indents.each do |indent|
      source = "journey\nsection S\nBefore: 5: You\n" \
               "accDescr {unterminated\nSwallowed: 1: Me\n#{indent}%% }\n" \
               "After: 4: Us\n"
      failure_message = "U+#{format('%04X', indent.ord)} should " \
                        "indent a comment"
      expect_parse_error(
        source,
        Sirena::Parser::ParseError,
        /Parse error/,
        failure_message: failure_message,
      )
    end
  end

  def journey_block(line)
    "journey\naccDescr {d\n#{"#{line}\n" * 800}}\nsection S\nT: 1: M\n"
  end

  def best_parse_time(source)
    Array.new(3) { wall_time { parser.parse(source) } }.min
  end

  def expect_line_bounded_alternative(rule, line, control)
    source = journey_block(line)
    expect(section_names_and_tasks(source)).to eq([["S", ["T"]]])
    failure_message = "#{rule} is not line-bounded"
    expect(best_parse_time(source)).to be < control * 8, failure_message
  end

  def expect_block_alternatives_line_bounded
    control = best_parse_time(journey_block("x"))
    alternatives = { "acc_comment_line" => "%% x", "acc_directive" => "%%{x" }
    alternatives.each do |rule, line|
      expect_line_bounded_alternative(rule, line, control)
    end
  end

  def unclosed_block_ratio(source, control_source)
    refused = wall_time do
      expect_parse_error(source, Sirena::Parser::ParseError, /Parse error/)
    end
    accepted = wall_time do
      expect(section_names_and_tasks(control_source)).to eq([["S", ["T"]]])
    end
    refused / accepted
  end

  def expect_unclosed_block_linear
    source = "journey\n#{"accDescr {x: 3: Me\n" * 2000}"
    control_source = "journey\n#{"accDescr {x: 3: Me}\n" * 2000}" \
                     "section S\nT: 1: M\n"
    expect(source.bytesize).to be > 30_000

    ratios = Array.new(3) { unclosed_block_ratio(source, control_source) }
    expect(ratios.min).to be < 8
  end

  def unicode_block_sources
    [0x2028, 0x00A0].map do |codepoint|
      separator = codepoint.chr(Encoding::UTF_8)
      "journey\naccDescr {#{separator * 4000}}\nsection S\nT: 3: Me\n"
    end
  end

  def expect_unicode_results(results)
    expect(results.map(&:last)).to eq([[["S", ["T"]]], [["S", ["T"]]]])
    expect(results.first.first).to be < results.last.first * 15
  end

  def expect_unicode_line_separator_linear
    sources = unicode_block_sources
    expect(sources.first).not_to eq(sources.last)

    results = sources.map do |source|
      [best_parse_time(source), section_names_and_tasks(source)]
    end
    expect_unicode_results(results)
  end

  def journey_fixture(filename)
    File.read(
      File.expand_path("../../mermaid/user_journey/#{filename}", __dir__),
    )
  end
end

RSpec.describe Sirena::Parser::UserJourney do
  include UserJourneySpecHelpers

  let(:parser) { described_class.new }

  describe "#parse" do
    basic_cases = {
      "parses simple user journey with one task" => [
        <<~MERMAID,
          journey
            title My Journey
            section Shopping
              Browse products: 5: Customer
        MERMAID
        lambda do |diagram|
          task = diagram.sections.first.tasks.first
          [diagram.class, diagram.title, diagram.sections.length,
           diagram.sections.first.name, diagram.sections.first.tasks.length,
           task.name, task.score, task.actors]
        end,
        [Sirena::Diagram::UserJourney, "My Journey", 1, "Shopping", 1,
         "Browse products", 5, ["Customer"]],
      ],
      "parses user journey without title" => [
        "journey\nsection Shopping\nBrowse: 5: Customer\n",
        ->(diagram) { [diagram.title, diagram.sections.length] },
        [nil, 1],
      ],
      "parses multiple sections" => [
        "journey\nsection Shopping\nBrowse: 5: Customer\n" \
        "section Checkout\nPay: 3: Customer\n",
        ->(diagram) { diagram.sections.map(&:name) },
        %w[Shopping Checkout],
      ],
      "parses multiple tasks in a section" => [
        "journey\nsection Shopping\nBrowse: 5: Customer\n" \
        "Select: 4: Customer\nAdd to cart: 4: Customer\n",
        ->(diagram) { diagram.sections.first.tasks.map(&:name) },
        ["Browse", "Select", "Add to cart"],
      ],
      "parses tasks with multiple actors" => [
        "journey\nsection Shopping\nCheckout: 3: Customer, Staff\n",
        ->(diagram) { diagram.sections.first.tasks.first.actors },
        %w[Customer Staff],
      ],
      "parses tasks with different scores" => [
        "journey\nsection Test\nTask1: 1: Actor\nTask2: 2: Actor\n" \
        "Task3: 3: Actor\nTask4: 4: Actor\nTask5: 5: Actor\n",
        ->(diagram) { diagram.sections.first.tasks.map(&:score) },
        [1, 2, 3, 4, 5],
      ],
    }

    basic_cases.each do |description, (source, projection, expected)|
      it description do
        expect(projection.call(parser.parse(source))).to eq(expected)
      end
    end

    it "raises ParseError for invalid syntax" do
      source = "invalid"

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
      )
    end

    # Corpus cases 008/012 (parser_should_handle_a_task_definition) and 004
    # (rendering_journey.spec_user_journey_3): the actor group (`: actors`)
    # is optional, an empty actor list after a trailing colon is allowed,
    # and a space is permitted between the score and the second colon.
    describe "a task line with no actors" do
      cases = {
        "no second colon at all" => ["Task: 5", 5, []],
        "a trailing colon with no actors" => ["Task: 5:", 5, []],
        "a space before the second colon" => ["Task : 5 : Alice", 5, ["Alice"]],
      }

      cases.each do |label, (task_line, expected_score, expected_actors)|
        it "parses #{label}" do
          source = "journey\nsection S\n#{task_line}\n"

          diagram = parser.parse(source)
          task = diagram.sections.first.tasks.first

          expect([task.score, task.actors])
            .to eq([expected_score, expected_actors])
        end
      end
    end

    # mmdc renders a task written before the first `section` (checked with
    # `mmdc -i case.mmd`): it keeps the task and draws no section header.
    describe "a task before the first section" do
      let(:diagram) do
        parser.parse("journey\n  Lead: 3: Me\n  section S1\n  Next: 4: You\n")
      end

      it "keeps it in an unnamed first section" do
        expect(diagram.sections.map(&:name)).to eq(["", "S1"])
      end

      it "keeps its name, score and actors" do
        task = diagram.sections.first.tasks.first

        expect([task.name, task.score, task.actors]).to eq(["Lead", 3, ["Me"]])
      end
    end

    it "raises ScoreError for score out of range" do
      source = "journey\nsection Test\nTask: 6: Actor\n"
      expect_score_error(source)
    end

    # "The oracle" below means mermaid 11.16.1 via mermaid-cli 11.12.0. To
    # re-run a verdict: `mmdc -i case.mmd -o case.svg; echo "exit $?"` --
    # exit 0 is a render, non-zero a refusal.

    # Fixture names are misleading: "multiline" files hold a single-line
    # accTitle, and "title_definition" files hold an accTitle (nil title).
    # Only the accdescr case actually contains an accDescr.
    describe "an accessibility directive from the corpus" do
      cases = {
        "004_parser_should_handle_a_title_definition_3.mmd" => nil,
        "004_parser_should_handle_an_accessibility_description_" \
        "accdescr__3.mmd" =>
          "Adding journey diagram functionality to mermaid",
        "005_parser_should_handle_an_accessibility_multiline_" \
        "description_accdescr__4.mmd" =>
          "Adding journey diagram functionality to mermaid",
      }

      cases.each do |filename, expected_title|
        it "parses #{filename}" do
          diagram = parser.parse(journey_fixture(filename))
          actual = [diagram.title, diagram.sections.map(&:name)]
          expect(actual).to eq([expected_title, ["Order from website"]])
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
    describe "a directive among the tasks" do
      {
        "accTitle" => "accTitle: The accessible title",
        "accDescr" => "accDescr: A user journey for family shopping",
        "accTitle with a spaced colon" => "accTitle : The accessible title",
        "accDescr with a spaced colon" => "accDescr : A user journey",
        "an indented accTitle" => "    accTitle: The accessible title",
        "a braced accDescr block" =>
          "accDescr {\n  a multi line\n  description\n}",
        "a braced accDescr block on one line" => "accDescr {Desc}",
        "a braced accDescr block with no gap" => "accDescr{Desc}",
        "an accTitle with no gap" => "accTitle:Tight",
      }.each do |label, directive|
        it "discards #{label} and leaves the rest of the diagram alone" do
          source = "journey\ntitle Real title\nsection Order from website\n  " \
                   "Sit down: 5: Me\n#{directive}\n  Check mail: 3: Me\n"
          expect_directive_journey(source)
        end
      end
    end

    describe "the edges of the accessibility rules" do
      it "takes the keyword whole rather than as a prefix" do
        # The oracle titles the first source `3: Me` and draws no task for
        # it; it renders the second as an ordinary task, since `accTitleNode`
        # only starts with the same letters.
        section = "journey\nsection Order from website\n  "
        directive = "#{section}accTitle: 3: Me\n"
        prefixed = "#{section}accTitleNode: 3: Me\n"
        expect_section_tasks(directive, "Order from website", [])
        expect_section_tasks(prefixed, "Order from website", ["accTitleNode"])
      end

      it "matches accTitle/accDescr case-insensitively, as the oracle does" do
        # Confirmed against mermaid 11.16.1's own compiled journey parser:
        # `ACCDESCR: 3: Me` is read as a description with no task, not a task
        # literally named "ACCDESCR".
        source = "journey\nsection S\nACCDESCR: 3: Me\n"

        expect(section_names_and_tasks(source)).to eq([["S", []]])
      end

      it "matches a mixed-case braced accDescr opener case-insensitively" do
        source = "journey\nAccDescr {Desc}\nsection S\nT: 1: M\n"

        expect(section_names_and_tasks(source)).to eq([["S", ["T"]]])
      end

      it "still takes a mixed-case keyword whole rather than as a prefix" do
        # Same boundary as "takes the keyword whole rather than as a prefix"
        # above, now checked with the keyword upper-cased -- word_ci has no
        # boundary check of its own, it relies on the required colon failing
        # to match the next character.
        prefixed = "journey\nsection S\nACCTITLENODE: 3: Me\n"

        expected = [["S", ["ACCTITLENODE"]]]
        expect(section_names_and_tasks(prefixed)).to eq(expected)
      end

      it "reads a task-shaped directive as a directive" do
        # The shape that forced the colon gap: with the colon required to
        # touch the keyword, this fell through to the task rule and became a
        # task named accDescr scoring 3. The oracle reads it as a description
        # and draws no task.
        source = "journey\nsection Order from website\n  accDescr : 3: Me\n"

        expect(section_names_and_tasks(source))
          .to eq([["Order from website", []]])
      end

      it "requires the block to close, as mermaid does" do
        # The oracle renders the closed source and refuses the unclosed one.
        # Why the brace is required is on the rule itself.
        task = "section Order from website\n  Sit down: 5: Me\n"
        closed = "journey\naccDescr {desc}\n#{task}"
        unclosed = "journey\naccDescr {unterminated\n#{task}"
        expected = [["Order from website", ["Sit down"]]]
        expect_closed_and_unclosed(closed, unclosed, expected)
      end

      it "refuses a task-shaped opener whose block never closes" do
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

        expect_parse_error(source, Sirena::Parser::ParseError, /Parse error/)
      end

      it "refuses an opener whose only closing brace sits in a comment" do
        # The comment rule consumes `%% }` whole, so that brace is not a
        # delimiter and the block never closes. The oracle refuses this
        # source too. It is the shape the check above cannot reach, because
        # here a `}` really is present in the source.
        source = "journey\naccDescr {a\nT: 3: Me\n%% }\n"

        expect_parse_error(source, Sirena::Parser::ParseError, /Parse error/)
      end

      it "opens a comment only at the start of a line" do
        # A `%%` in the middle of a line is ordinary text, so the `}` after it
        # closes the block and the section and task that follow are read
        # normally. The oracle agrees, giving this source the description
        # `text%%`. Unanchoring the comment rule swallows `%% }` instead, the
        # block never closes, and the whole source is refused.
        source = "journey\naccDescr {text%% }\nsection S\nT: 1: M\n"

        expect(section_names_and_tasks(source)).to eq([["S", ["T"]]])
      end

      it "lets a brace in a later, unrelated line close " \
         "an earlier open block" do
        # A stray `}` inside a later task's actor name closes the block
        # early and silently drops every section/task in between -- here
        # "section Alpha" and its task vanish entirely, with no error.
        # Not a divergence: mermaid's own bundled lexer (11.16.1) does the
        # identical thing, confirmed by driving its compiled journey parser
        # directly with this exact source -- it emits only `addSection
        # "Beta"` and `addTask "AnotherTask"`, never touching "Alpha". The
        # grammar matches the oracle's silent-drop behavior, not a bug.
        source = "journey\naccDescr {oops\nsection Alpha\n" \
                 "RealTask: 5: Person}\nsection Beta\nAnotherTask: 2: Someone\n"

        expected = [["Beta", ["AnotherTask"]]]
        expect(section_names_and_tasks(source)).to eq(expected)
      end

      it "ends the block at the brace and reads what follows it" do
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

        expect(scored_section_names_and_tasks(source))
          .to eq([["S", [["After", 3]]]])
      end

      it "raises ParseError on a source valid in a non-UTF-8 encoding" do
        # The accessibility rules are the only regexps in this grammar with a
        # fixed encoding — a `\uXXXX` escape sets one even though every
        # character in the set is ASCII — so this 18-byte ISO-8859-1 source
        # reached one and Parslet let Encoding::CompatibilityError out.
        # Parser::Base#parse documents ParseError, and ParseError is what
        # this source produced before the braced form existed.
        source = +"journey\naccDescr{\x9F"
        source.force_encoding(Encoding::ISO_8859_1)
        expect_encoded_parse_error(source, valid: true, ascii_only: false)
      end

      it "raises ParseError on a UTF-8-tagged source with " \
         "an invalid byte sequence" do
        # A different failure mode from the ISO-8859-1 case above: this source
        # is tagged UTF-8 but is not valid UTF-8, so Parslet::Source.new raises
        # ArgumentError ("invalid byte sequence in UTF-8") from StringScanner
        # while indexing line endings -- before any grammar rule runs, and
        # before an EncodingError could ever be raised. Parser::Base#parse
        # documents ParseError as the one contract; a raw ArgumentError would
        # break it.
        source = (+"journey\naccTitle: \xFF\xFE\n")
          .force_encoding(Encoding::UTF_8)
        expect_encoded_parse_error(source, valid: false)
      end

      it "raises ParseError on a source valid in a non-UTF-8 encoding " \
         "that only fails once the tree is built" do
        # A third failure mode: this source is valid Big5-HKSCS throughout
        # and passes grammar parsing entirely, then raises ArgumentError from
        # `String#strip` inside build_diagram_from_tree, on the actor slice.
        # Before the parse-time rescue widened to cover the whole method,
        # this escaped as a raw ArgumentError (via Sirena::Engine as
        # PipelineError), not the ParseError this parser's contract promises.
        source = "journey\naccTitle: description\nsection S\nTask: 1: é\n"
          .encode("Big5-HKSCS")
        expect_invalid_byte_parse_error(source)
      end

      it "ends the directive text at the newline" do
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
        task = "section Order from website\n  Sit down: 5: Me\n"
        empty = "journey\naccTitle:\n#{task}"
        next_line = "journey\naccTitle:\nBig decisions\n#{task}"
        expected = [["Order from website", ["Sit down"]]]
        expect_closed_and_unclosed(empty, next_line, expected)
      end
    end

    describe "a comment or a directive inside the block" do
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
        "a comment whose text merely starts with a brace" => "%% {x}",
        "a closed init directive" => '%%{init: {"theme":"dark"}}%%',
        "plain text" => "plain text",
      }.each do |label, directive|
        it "keeps the tasks outside a block holding #{label}" do
          source = "journey\nsection S\nBefore: 5: You\naccDescr {desc\n" \
                   "#{directive}\nSwallowed: 1: Me\n}\nAfter: 4: Us\n"

          expect(section_names_and_tasks(source))
            .to eq([["S", %w[Before After]]])
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
        "a bare braced directive" => "%%{x}",
        "an init directive with no closing tail" =>
          '%%{init: {"theme":"dark"}}',
      }.each do |label, directive|
        it "refuses a block holding #{label}" do
          source = "journey\nsection S\nBefore: 5: You\naccDescr {desc\n" \
                   "#{directive}\nSwallowed: 1: Me\n}\nAfter: 4: Us\n"

          expect_parse_error(source, Sirena::Parser::ParseError, /Parse error/)
        end
      end

      it "reads a mid-line directive as text rather than as a directive" do
        # Known divergence, pinned: mermaid's directive strip isn't anchored
        # to a line start (it strips `%%{x}%%` mid-line), this grammar's is,
        # so this parses where the oracle refuses it. `comment` is the
        # control -- a plain mid-line `%%` still gets refused by both.
        directive = "journey\naccDescr {A%%{x}%%B\nsection S\nT: 1: M\n"
        comment = "journey\naccDescr {A%% x}B\nsection S\nT: 1: M\n"

        expected = [["S", ["T"]]]
        expect_closed_and_unclosed(directive, comment, expected)
      end

      it "does not read a directive split across two lines" do
        # Known divergence, pinned: the oracle strips a directive split
        # across lines and renders; here the directive body stops at the
        # line end (required -- see the invariant on acc_block_body), so the
        # `}` inside the JSON closes the block early and this refuses it.
        source = "journey\naccDescr {a\n%%{init: {\n" \
                 "\"theme\":\"dark\"}}%%\nb}\n" \
                 "section S\nT: 1: M\n"

        expect_parse_error(source, Sirena::Parser::ParseError, /Parse error/)
      end

      it "treats a directive with no closing tail as ordinary text" do
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

        expect(section_names_and_tasks(source)).to eq([["S", ["T"]]])
      end

      it "does not let a brace inside a comment close the block" do
        # Both the oracle and the parser before this change refuse the first
        # source. Until the block body consumed comment lines whole, it
        # parsed here as a diagram with `Swallowed` silently gone — accepted
        # where the oracle rejects, and quietly short a task. The oracle
        # renders the second source, where a real brace follows the commented
        # one.
        expect_comment_brace_behavior
      end

      it "opens a comment on any of the four line terminators" do
        # The oracle refuses each source: a carriage return, U+2028 or U+2029
        # opens the comment just as a newline does, and missing any one of
        # them let the `}` in `%% }` close the block and dropped `Swallowed`
        # without a word. Built from codepoints so no editor can normalise
        # one of the three into another.
        expect_comment_openers([0x0D, 0x2028, 0x2029])
      end

      it "accepts every character of mermaid whitespace as a comment indent" do
        # The indent is matched with mermaid's whitespace set rather than
        # ASCII, because an indent this misses leaves the `}` in `%% }`
        # closing the block and a task disappears in silence — the oracle
        # rejects each of these sources. Only the no-break space was
        # exercised before, so a set narrowed to ASCII passed the suite.
        #
        # U+2028 and U+2029 are absent on purpose: `acc_nl` claims both, and
        # sharing them made a valid document quadratic. A run of them still
        # opens a comment, which the terminator example above covers.
        codepoints = [0x09, 0x0B, 0x0C, 0x20, 0x00A0, 0x1680,
                      *0x2000..0x200A, 0x202F, 0x205F, 0x3000, 0xFEFF]
        expect_comment_indents(codepoints)
      end
    end

    describe "the cost of a large source", :speed do
      # These examples are clock-based, which is why each is written against
      # a control rather than a bare stopwatch wherever it can be. They exist
      # because the defects they pin are invisible to every other assertion
      # in this file: two of the three do not change a single parse result,
      # only how long one takes.

      it "keeps every alternative in the block body line-bounded" do
        # ADD A ROW here when you add an alternative to `acc_block_comment` --
        # this is what catches an alternative that isn't LINE-BOUNDED (the
        # invariant on `acc_block_body`) before it ships. Each side is the
        # MINIMUM of three runs: noise only ever adds time, so a spike has to
        # hit every sample to produce a false failure.
        expect_block_alternatives_line_bounded
      end

      it "refuses a long unclosed block without rescanning it per line" do
        # Control: the SAME 2000 openers with braces CLOSED, isolating the
        # refusal's cost from machine speed. Do NOT split the two timed sides
        # into separate phases and `min` each separately -- that flakes under
        # load. Measure as ADJACENT PAIRS and take the minimum over the
        # per-pair ratios, so both halves of a sample share one load regime.
        expect_unclosed_block_linear
      end

      it "parses a long run of U+2028 inside a block in linear time" do
        # `acc_nl` and `acc_line_space` must stay disjoint (see the
        # invariant on `acc_line_space`) -- folding U+2028/U+2029 into both
        # makes this quadratic again. The no-break space is the control: it
        # is in the indent set and NOT in `acc_nl`, so it cannot open a
        # comment, isolating the one property under test.
        expect_unicode_line_separator_linear
      end
    end
  end
end
