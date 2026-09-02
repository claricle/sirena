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

    # The extracted fixture names mislead twice over: the files named
    # "multiline" hold a single-line accTitle, and those named
    # "title_definition" hold an accTitle rather than a title, so they expect
    # a nil title. The seven files carrying a directive collapse to these
    # three sources — 009_..._title_8 and 013_..._title_12 duplicate the
    # first, 008_..._accdescr__7 the second, 009_..._multiline_..._8 the
    # third. Only the second contains an accDescr.
    context 'with an accessibility directive from the corpus' do
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
    # mmdc 11.12.0 renders both tasks in every source here.
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
        # mmdc 11.12.0 titles the first source `3: Me` and draws no task for
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
        # task named accDescr scoring 3. mmdc reads it as a description and
        # draws no task.
        source = "journey\nsection Order from website\n  accDescr : 3: Me\n"

        expect(parser.parse(source).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['Order from website', []]])
      end

      it 'requires the block to close, as mermaid does' do
        # mmdc 11.12.0 renders the closed source and refuses the unclosed
        # one. Why the brace is required is on the rule itself.
        closed = "journey\naccDescr {desc}\nsection Order from website\n  " \
                 "Sit down: 5: Me\n"
        unclosed = "journey\naccDescr {unterminated\nsection Order from website\n  " \
                   "Sit down: 5: Me\n"

        expect(parser.parse(closed).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['Order from website', ['Sit down']]])
        expect { parser.parse(unclosed) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end

      it 'does not let a brace inside a comment close the block' do
        # Both c09c975 and mmdc 11.12.0 refuse the first source. Until the
        # block body consumed comment lines whole, it parsed here as a
        # diagram with `Swallowed` silently gone — accepted where the oracle
        # rejects, and quietly short a task. The indent is matched with
        # mermaid's whitespace set, not just ASCII, because a no-break-space
        # before the `%%` brought the same silent loss back — mmdc rejects
        # that source too. It also rejects each source in `breaks`, where a
        # carriage return, U+2028 or U+2029 opens the comment instead of a
        # newline — mermaid strips comment lines by ECMAScript's four line
        # terminators, and missing any one of them dropped `Swallowed`
        # without a word. mmdc renders the last source here, where a real
        # brace follows the commented one.
        commented_close = "journey\nsection S\nBefore: 5: You\n" \
                          "accDescr {unterminated\nSwallowed: 1: Me\n%% }\n" \
                          "After: 4: Us\n"
        real_close = "journey\naccDescr {\ndescription\n%% }\n" \
                     "still description\n}\nsection S\nTask: 3: Me\n"

        nbsp_close = commented_close.sub("\n%% }", "\n\u00A0%% }")
        breaks = ["\r", "\u2028", "\u2029"].map do |sep|
          "journey\nsection S\nBefore: 5: You\naccDescr {unterminated\n" \
            "Swallowed: 1: Me#{sep}%% }"
        end

        expect { parser.parse(commented_close) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        expect { parser.parse(nbsp_close) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        breaks.each do |source|
          expect { parser.parse(source) }
            .to raise_error(Sirena::Parser::ParseError, /Parse error/)
        end
        expect(parser.parse(real_close).sections.map { |s| [s.name, s.tasks.map(&:name)] })
          .to eq([['S', ['Task']]])
      end

      it 'ends the directive text at the newline' do
        # An empty `accTitle:` is consumed and the next line keeps its own
        # meaning. mermaid's whitespace AFTER the delimiter crosses newlines
        # instead, so mmdc 11.12.0 titles the first source
        # `section Order from website` and the second `Big decisions` — a
        # divergence this PR leaves open. Sirena's own gantt and pie parsers
        # reject the second as well; its timeline parser takes an empty title
        # and reads `Big decisions` as content. Closing it needs flowchart's
        # comment-skipping gap
        # (grammars/flowchart.rb:145), which also changes what a bare
        # `accTitle:` does to the line after it.
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
  end
end
